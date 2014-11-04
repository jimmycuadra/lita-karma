module Lita::Handlers::Karma
  # Tracks karma points for arbitrary terms.
  class Chat < Lita::Handler
    namespace "karma"

    on :loaded, :define_routes

    def define_routes(payload)
      define_static_routes
      define_dynamic_routes(config.term_pattern.source)
    end

    def increment(response)
      modify(response, 1)
    end

    def decrement(response)
      modify(response, -1)
    end

    def check(response)
      output = []

      process_decay

      response.matches.each do |match|
        term = normalize_term(match[0])
        total_score, own_score, links = scores_for(term)

        string = "#{term}: #{total_score}"
        unless links.empty?
          string << " (#{own_score}), #{t("linked_to")}: #{links.join(", ")}"
        end
        output << string
      end

      response.reply *output
    end

    def list_best(response)
      list(response, :zrevrange)
    end

    def list_worst(response)
      list(response, :zrange)
    end

    def link(response)
      response.matches.each do |match|
        term1, term2 = normalize_term(match[0]), normalize_term(match[1])

        if config.link_karma_threshold
          threshold = config.link_karma_threshold.abs

          _total_score, term2_score, _links = scores_for(term2)
          _total_score, term1_score, _links = scores_for(term1)

          if term1_score.abs < threshold || term2_score.abs < threshold
            response.reply t("threshold_not_satisfied", threshold: threshold)
            return
          end
        end

        if redis.sadd("links:#{term1}", term2)
          redis.sadd("linked_to:#{term2}", term1)
          response.reply t("link_success", source: term2, target: term1)
        else
          response.reply t("already_linked", source: term2, target: term1)
        end
      end
    end

    def unlink(response)
      response.matches.each do |match|
        term1, term2 = normalize_term(match[0]), normalize_term(match[1])

        if redis.srem("links:#{term1}", term2)
          redis.srem("linked_to:#{term2}", term1)
          response.reply t("unlink_success", source: term2, target: term1)
        else
          response.reply t("already_unlinked", source: term2, target: term1)
        end
      end
    end

    def modified(response)
      term = normalize_term(response.args[1])

      process_decay

      user_ids = redis.zrevrange("modified:#{term}", 0, -1, with_scores: true)

      if user_ids.empty?
        response.reply t("never_modified", term: term)
      else
        output = user_ids.map do |(id, score)|
          "#{Lita::User.find_by_id(id).name} (#{score.to_i})"
        end.join(", ")
        response.reply output
      end
    end

    def delete(response)
      term = response.message.body.sub(/^karma delete /, "")

      redis.del("modified:#{term}")
      redis.del("links:#{term}")
      redis.smembers("linked_to:#{term}").each do |key|
        redis.srem("links:#{key}", term)
      end
      redis.del("linked_to:#{term}")

      if redis.zrem("terms", term)
        response.reply t("delete_success", term: term)
      else
        response.reply t("delete_failure", term: term)
      end
    end

    private

    def cooling_down?(term, user_id, response)
      ttl = redis.ttl("cooldown:#{user_id}:#{term}")

      if ttl >= 0
        response.reply t("cooling_down", term: term, ttl: ttl, count: ttl)
        return true
      else
        return false
      end
    end

    def define_dynamic_routes(pattern)
      self.class.route(
        %r{(#{pattern})\+\+},
        :increment,
        help: { t("help.increment_key") => t("help.increment_value") }
      )

      self.class.route(
        %r{(#{pattern})\-\-},
        :decrement,
        help: { t("help.decrement_key") => t("help.decrement_value") }
      )

      self.class.route(
        %r{(#{pattern})~~},
        :check,
        help: { t("help.check_key") => t("help.check_value") }
      )

      self.class.route(
        %r{^(#{pattern})\s*\+=\s*(#{pattern})},
        :link,
        command: true,
        help: { t("help.link_key") => t("help.link_value") }
      )

      self.class.route(
        %r{^(#{pattern})\s*-=\s*(#{pattern})},
        :unlink,
        command: true,
        help: { t("help.unlink_key") => t("help.unlink_value") }
      )
    end

    def define_static_routes
      self.class.route(
        %r{^karma\s+worst},
        :list_worst,
        command: true,
        help: { t("help.list_worst_key") => t("help.list_worst_value") }
      )

      self.class.route(
        %r{^karma\s+best},
        :list_best,
        command: true,
        help: { t("help.list_best_key") => t("help.list_best_value") }
      )

      self.class.route(
        %r{^karma\s+modified\s+.+},
        :modified,
        command: true,
        help: { t("help.modified_key") => t("help.modified_value") }
      )

      self.class.route(
        %r{^karma\s+delete},
        :delete,
        command: true,
        restrict_to: :karma_admins,
        help: { t("help.delete_key") => t("help.delete_value") }
      )

      self.class.route(%r{^karma\s*$}, :list_best, command: true)
    end

    def modify(response, delta)
      response.matches.each do |match|
        term = normalize_term(match[0])
        user_id = response.user.id

        return if cooling_down?(term, user_id, response)

        redis.zincrby("terms", delta, term)
        redis.zincrby("modified:#{term}", 1, user_id)
        set_cooldown(term, response.user.id)
        add_action(term, user_id, delta)
      end

      check(response)
    end

    def normalize_term(term)
      if config.term_normalizer
        config.term_normalizer.call(term)
      else
        term.to_s.downcase.strip
      end
    end

    def list(response, redis_command)
      n = (response.args[1] || 5).to_i - 1
      n = 25 if n > 25

      process_decay

      terms_scores = redis.public_send(
        redis_command, "terms", 0, n, with_scores: true
      )

      output = terms_scores.each_with_index.map do |term_score, index|
        "#{index + 1}. #{term_score[0]} (#{term_score[1].to_i})"
      end.join("\n")

      if output.length == 0
        response.reply t("no_terms")
      else
        response.reply output
      end
    end

    def scores_for(term)
      process_decay
      own_score = total_score = redis.zscore("terms", term).to_i
      links = []

      redis.smembers("links:#{term}").each do |link|
        link_score = redis.zscore("terms", link).to_i
        links << "#{link}: #{link_score}"
        total_score += link_score
      end

      [total_score, own_score, links]
    end

    def set_cooldown(term, user_id)
      redis.setex("cooldown:#{user_id}:#{term}", config.cooldown.to_i, 1) if config.cooldown
    end

    def decay_enabled?
      config.decay && config.decay_interval > 0
    end

    def process_decay
      return unless decay_enabled?
      cutoff = Time.now.to_f - Lita.config.handlers.karma.decay_interval.to_f
      terms = []
      redis.zrangebyscore(:actions, '-inf', cutoff).each do |action|
        action = Action.deserialize(action)
        redis.zincrby(:terms, -action.delta, action.term)
        if action.user_id
          redis.zincrby("modified:#{action.term}", -1, action.user_id)
        end
        terms << action.term
      end

      redis.zremrangebyscore(:actions, '-inf', cutoff)
      terms.each {|t| redis.zremrangebyscore("modified:#{t}", '-inf', 0)}
    end

    def add_action(term, user_id, delta = 1, at = Time.now)
      return unless decay_enabled?
      action = Action.new(term, user_id, delta, at)
      redis.zadd(:actions, at.to_f, action.serialize)
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Chat)
