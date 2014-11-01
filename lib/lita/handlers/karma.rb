require "lita"

module Lita
  module Handlers
    # Tracks karma points for arbitrary terms.
    class Karma < Handler
      config :cooldown, types: [Integer, nil], default: 300
      config :link_karma_threshold, types: [Integer, nil], default: 10
      config :term_pattern, type: Regexp, default: /[\[\]\p{Word}\._|\{\}]{2,}/
      config :term_normalizer do
        validate do |value|
          "must be a callable object" unless value.respond_to?(:call)
        end
      end

      config(:upgrade_modified, default: Proc.new {|score, user_ids| user_ids.map {|t| [1, t] } }) do
        validate do |value|
          "must be a callable object" unless value.respond_to?(:call)
        end
      end

      on :loaded, :upgrade_data
      on :loaded, :define_routes

      def upgrade_data(payload)
        unless redis.exists("support:reverse_links")
          redis.keys("links:*").each do |key|
            term = key.sub(/^links:/, "")
            redis.smembers(key).each do |link|
              redis.sadd("linked_to:#{link}", term)
            end
          end
          redis.incr("support:reverse_links")
        end

        unless redis.exists('support:modified_counts')
          terms = redis.zrange('terms', 0, -1, with_scores: true)

          upgrade = Lita.config.handlers.karma.upgrade_modified

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
            Lita.logger.debug("Karma: Upgraded modified set for '#{term}'")
          end

          redis.incr("support:modified_counts")
        end
      end

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

        response.matches.each do |match|
          term = normalize_term(match[0])
          total_score, own_score, links = scores_for(term)

          string = "#{term}: #{total_score}"
          unless links.empty?
            string << " (#{own_score}), linked to: #{links.join(", ")}"
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
              response.reply "Terms must have less than -#{threshold} or more than #{threshold} karma to be linked or linked to."
              return
            end
          end

          if redis.sadd("links:#{term1}", term2)
            redis.sadd("linked_to:#{term2}", term1)
            response.reply "#{term2} has been linked to #{term1}."
          else
            response.reply "#{term2} is already linked to #{term1}."
          end
        end
      end

      def unlink(response)
        response.matches.each do |match|
          term1, term2 = normalize_term(match[0]), normalize_term(match[1])

          if redis.srem("links:#{term1}", term2)
            redis.srem("linked_to:#{term2}", term1)
            response.reply "#{term2} has been unlinked from #{term1}."
          else
            response.reply "#{term2} is not linked to #{term1}."
          end
        end
      end

      def modified(response)
        term = normalize_term(response.args[1])

        if term.empty?
          response.reply "Format: #{robot.name}: karma modified TERM"
          return
        end

        user_ids = redis.zrevrange("modified:#{term}", 0, -1, with_scores: true)

        if user_ids.empty?
          response.reply "#{term} has never been modified."
        else
          output = user_ids.map do |(id, score)|
            "#{User.find_by_id(id).name} (#{score.to_i})"
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
          response.reply("#{term} has been deleted.")
        else
          response.reply("#{term} does not exist.")
        end
      end

      private

      def cooling_down?(term, user_id, response)
        ttl = redis.ttl("cooldown:#{user_id}:#{term}")

        if ttl >= 0
          cooldown_message =
            "You cannot modify #{term} for another #{ttl} second"
          cooldown_message << (ttl == 1 ? "." : "s.")
          response.reply cooldown_message
          return true
        else
          return false
        end
      end

      def define_dynamic_routes(pattern)
        self.class.route(
          %r{(#{pattern})\+\+},
          :increment,
          help: { "TERM++" => "Increments TERM by one." }
        )

        self.class.route(
          %r{(#{pattern})\-\-},
          :decrement,
          help: { "TERM--" => "Decrements TERM by one." }
        )

        self.class.route(
          %r{(#{pattern})~~},
          :check,
          help: { "TERM~~" => "Shows the current karma of TERM." }
        )

        self.class.route(
          %r{^(#{pattern})\s*\+=\s*(#{pattern})},
          :link,
          command: true,
          help: {
            "TERM1 += TERM2" => <<-HELP.chomp
Links TERM2 to TERM1. TERM1's karma will then be displayed as the sum of its \
own and TERM2's karma.
HELP
          }
        )

        self.class.route(
          %r{^(#{pattern})\s*-=\s*(#{pattern})},
          :unlink,
          command: true,
          help: {
            "TERM1 -= TERM2" => <<-HELP.chomp
Unlinks TERM2 from TERM1. TERM1's karma will no longer be displayed as the sum \
of its own and TERM2's karma.
HELP
          }
        )
      end

      def define_static_routes
        self.class.route(
          %r{^karma\s+worst},
          :list_worst,
          command: true,
          help: {
            "karma worst [N]" => <<-HELP.chomp
Lists the bottom N terms by karma. N defaults to 5.
HELP
          }
        )

        self.class.route(
          %r{^karma\s+best},
          :list_best,
          command: true,
          help: {
            "karma best [N]" => <<-HELP.chomp
Lists the top N terms by karma. N defaults to 5.
HELP
          }
        )

        self.class.route(
          %r{^karma\s+modified},
          :modified,
          command: true,
          help: {
            "karma modified TERM" => <<-HELP.chomp
Lists the names of users who have upvoted or downvoted TERM.
HELP
          }
        )

        self.class.route(
          %r{^karma\s+delete},
          :delete,
          command: true,
          restrict_to: :karma_admins,
          help: {
            "karma delete TERM" => <<-HELP.chomp
Permanently removes TERM and all its links. TERM is matched exactly as typed \
and does not adhere to the usual pattern for terms.
HELP
          }
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

        terms_scores = redis.public_send(
          redis_command, "terms", 0, n, with_scores: true
        )

        output = terms_scores.each_with_index.map do |term_score, index|
          "#{index + 1}. #{term_score[0]} (#{term_score[1].to_i})"
        end.join("\n")

        if output.length == 0
          response.reply "There are no terms being tracked yet."
        else
          response.reply output
        end
      end

      def scores_for(term)
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
    end

    Lita.register_handler(Karma)
  end
end
