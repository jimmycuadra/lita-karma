module Lita::Handlers::Karma::Upgrade
  class ModifiedCounts
    extend Lita::Handler::EventRouter

    namespace "karma"

    on :loaded, :modified_counts

    def modified_counts(payload)
      unless redis.exists('support:modified_counts')
        log.debug "Upgrading data to include modified counts."

        upgrade = config.upgrade_modified

        all_terms.each { |(term, score)| upgrade_term(term, score, upgrade) }

        redis.incr("support:modified_counts")
      end
    end

    private

    def all_terms
      redis.zrange('terms', 0, -1, with_scores: true)
    end

    def delete_keys(keys)
      keys.each { |key| redis.del(key) }
    end

    def set?(key)
      redis.type(key) == "set"
    end

    def upgrade_term(term, score, upgrade)
      (key, tmp_key = keys_for(term)) or return
      result = upgrade.call(score.to_i, user_ids_for(key))
      delete_keys([key, tmp_key])
      redis.zadd(key, result)
    end

    def keys_for(term)
      key = "modified:#{term}"
      return unless set?(key)
      tmp_key = "modified_flat:#{term}"
      [key, tmp_key]
    end

    def user_ids_for(key)
      redis.smembers(key)
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Upgrade::ModifiedCounts)
