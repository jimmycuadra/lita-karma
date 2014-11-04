module Lita::Handlers::Karma
  class Upgrade
    extend Lita::Handler::EventRouter

    namespace "karma"

    on :loaded, :upgrade_data

    def upgrade_data(payload)
      upgrade_links
      upgrade_modified_counts
      upgrade_decay
    end

    def upgrade_links
      unless redis.exists("support:reverse_links")
        log.debug "Upgrading data to include reverse links."

        redis.keys("links:*").each do |key|
          term = key.sub(/^links:/, "")
          redis.smembers(key).each do |link|
            redis.sadd("linked_to:#{link}", term)
          end
        end
        redis.incr("support:reverse_links")
      end
    end

    def upgrade_modified_counts
      unless redis.exists('support:modified_counts')
        log.debug "Upgrading data to include modified counts."

        terms = redis.zrange('terms', 0, -1, with_scores: true)

        upgrade = config.upgrade_modified

        terms.each do |(term, score)|
          mod_key = "modified:#{term}"
          next unless redis.type(mod_key) == 'set'
          tmp_key = "modified_flat:#{term}"

          user_ids = redis.smembers(mod_key)
          score = score.to_i
          result = upgrade.call(score, user_ids)
          redis.rename(mod_key, tmp_key)
          redis.zadd(mod_key, result)
          redis.del(tmp_key)
          log.debug("Karma: Upgraded modified set for '#{term}'")
        end

        redis.incr("support:modified_counts")
      end
    end

    def upgrade_decay
      if decay_enabled? && !redis.exists('support:decay')
        log.debug "Upgrading data to include karma decay."

        current = Hash.new { |h, k| h[k] = Hash.new {|h,k| h[k] = 0} }
        redis.zrange(:actions, 0, -1).each_with_object(current) do |json, hash|
          action = Action.from_json(json)
          hash[action.term][action.user_id] += 1
        end

        terms = redis.zrange('terms', 0, -1, with_scores: true)
        distributor = config.decay_distributor

        terms.each do |(term, term_score)|
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

    def add_action(term, user_id, delta = 1, at = Time.now)
      return unless decay_enabled?
      action = Action.new(term, user_id, delta, at)
      redis.zadd(:actions, at.to_f, action.serialize)
    end

    def decay_enabled?
      config.decay && config.decay_interval > 0
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Upgrade)
