module Lita::Handlers::Karma::Upgrade
  class Decay
    extend Lita::Handler::EventRouter

    namespace "karma"

    on :loaded, :decay

    def decay(payload)
      return unless decay_enabled? && !decay_already_processed?

      log.debug "Upgrading data to include karma decay."

      populate_current

      all_terms.each do |(term, score)|
        backfill_term(term, score.to_i)
      end

      redis.incr('support:decay')
    end

    private

    def action_class
      Lita::Handlers::Karma::Action
    end

    def add_action(term, user_id, delta, time)
      return unless decay_enabled?

      action_class.create(redis, term, user_id, delta, time)
    end

    def all_actions
      redis.zrange(:actions, 0, -1)
    end

    def all_terms
      redis.zrange('terms', 0, -1, with_scores: true)
    end

    def backfill_term(term, score)
      key = "modified:#{term}"
      total = 0
      distributor = config.decay_distributor
      score_sign = (score <=> 0)

      modified_counts_for(key).each do |(user_id, count)|
        count = count.to_i
        total += count

        (count - current[term][user_id]).times do |i|
          action_time = Time.now - distributor.call(decay_interval, i, count)
          add_action(term, user_id, score_sign, action_time)
        end
      end

      backfill_term_anonymously(score, total, term)
    end

    def backfill_term_anonymously(score, total, term)
      remainder = score.abs - total - current[term][nil]
      distributor = config.decay_distributor
      score_sign = (score <=> 0)

      remainder.times do |i|
        action_time = Time.now - distributor.call(decay_interval, i, remainder)
        add_action(term, nil, score_sign, action_time)
      end
    end

    def current
      @current ||= Hash.new { |h, k| h[k] = Hash.new { |h,k| h[k] = 0 } }
    end

    def decay_already_processed?
      redis.exists('support:decay')
    end

    def decay_enabled?
      config.decay && decay_interval > 0
    end

    def decay_interval
      config.decay_interval
    end

    def modified_counts_for(key)
      redis.zrange(key, 0, -1, with_scores: true)
    end

    def populate_current
      all_actions.each do |json|
        action = action_class.from_json(json)
        current[action.term][action.user_id] += 1
      end
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Upgrade::Decay)
