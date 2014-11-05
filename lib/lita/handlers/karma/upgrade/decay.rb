module Lita::Handlers::Karma::Upgrade
  class Decay
    extend Lita::Handler::EventRouter

    namespace "karma"

    on :loaded, :decay

    def decay(payload)
      if decay_enabled? && !redis.exists('support:decay')
        log.debug "Upgrading data to include karma decay."

        current = Hash.new { |h, k| h[k] = Hash.new {|h,k| h[k] = 0} }
        redis.zrange(:actions, 0, -1).each_with_object(current) do |json, hash|
          action = action_class.from_json(json)
          hash[action.term][action.user_id] += 1
        end

        distributor = config.decay_distributor

        all_terms.each do |(term, term_score)|
          mod_key = "modified:#{term}"
          total = 0
          redis.zrange(mod_key, 0, -1, with_scores: true).each do |(mod, mod_score)|
            mod_score = mod_score.to_i
            total += mod_score

            (mod_score - current[term][mod]).times do |i|
              action_time = Time.now - distributor.call(config.decay_interval, i, mod_score)
              add_action(term, mod, 1, action_time)
            end
          end

          remainder = term_score.to_i - total - current[term][nil]
          remainder.times do |i|
            action_time = Time.now - distributor.call(config.decay_interval, i, remainder)
            add_action(term, nil, 1, action_time)
          end
          known = current[term].values.inject(0, &:+)

          log.debug("Karma: decay update for '#{term}': known: #{known}, new: #{total - known}")
        end
        redis.incr('support:decay')
      end
    end

    private

    def action_class
      Lita::Handlers::Karma::Action
    end

    def add_action(term, user_id, delta = 1, at = Time.now)
      return unless decay_enabled?
      action = action_class.new(term, user_id, delta, at)
      redis.zadd(:actions, at.to_f, action.serialize)
    end

    def all_terms
      redis.zrange('terms', 0, -1, with_scores: true)
    end

    def decay_enabled?
      config.decay && config.decay_interval > 0
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Upgrade::Decay)
