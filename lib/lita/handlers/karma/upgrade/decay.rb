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

      redis.del('support:decay')
      redis.incr('support:decay_with_negatives')
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

      modified = modified_counts_for(key)

      modified.keys.each do |user_id|
        modified[user_id] -= current[term][user_id]
        total += current[term][user_id]
      end

      total = backfill_round_robin(term, score, modified, total)

      backfill_term_anonymously(term, score, total)
    end

    def backfill_round_robin(term, score, modified, total)
      distributor = config.decay_distributor
      score_sign = (score <=> 0)

      begin
        modified.each do |user_id, count|
          if count > 0
            index = total + current[term][user_id]
            action_time = Time.now - distributor.call(decay_interval, index, score.abs)
            add_action(term, user_id, score_sign, action_time)
            total += 1
            modified[user_id] -= 1
          else
            modified.delete(user_id)
          end
        end
      end until modified.empty?

      return total
    end

    def backfill_term_anonymously(term, score, total)
      remainder = score.abs - total - current[term][nil]
      distributor = config.decay_distributor
      score_sign = (score <=> 0)

      remainder.times do |i|
        action_time = Time.now - distributor.call(decay_interval, i + remainder, remainder)
        add_action(term, nil, score_sign, action_time)
      end
    end

    def current
      @current ||= Hash.new { |h, k| h[k] = Hash.new { |h,k| h[k] = 0 } }
    end

    def decay_already_processed?
      redis.exists('support:decay_with_negatives')
    end

    def decay_enabled?
      config.decay && decay_interval > 0
    end

    def decay_interval
      config.decay_interval
    end

    def modified_counts_for(key)
      Hash[redis.zrange(key, 0, -1, with_scores: true).map {|uid, score| [uid, score.to_i]}]
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
