require "lita"

module Lita
  module Handlers
    class Karma < Handler
      route %r{([^\s]{2,})\+\+}, to: :increment
      route %r{([^\s]{2,})\-\-}, to: :decrement
      route %r{([^\s]{2,})~~}, to: :check
      route %r{^karma\s+worst}, to: :list_worst, command: true
      route %r{^karma\s+best}, to: :list_best, command: true
      route %r{^karma\s+modified}, to: :modified, command: true
      route %r{^karma\s*$}, to: :list_best, command: true
      route %r{^([^\s]{2,})\s*\+=\s*([^\s]{2,})}, to: :link, command: true
      route %r{^([^\s]{2,})\s*-=\s*([^\s]{2,})}, to: :unlink, command: true

      def increment(matches)
        modify(matches, 1)
      end

      def decrement(matches)
        modify(matches, -1)
      end

      def check(matches)
        output = []

        matches.each do |match|
          term = match[0]
          own_score = score = redis.zscore("terms", term).to_i
          links = []
          redis.smembers("links:#{term}").each do |link|
            link_score = redis.zscore("terms", link).to_i
            links << "#{link}: #{link_score}"
            score += link_score
          end

          string = "#{term}: #{score}"
          unless links.empty?
            string << " (#{own_score}), linked to: "
            string << links.join(", ")
          end
          output << string
        end

        reply *output
      end

      def list_best(matches)
        list(:zrevrange)
      end

      def list_worst(matches)
        list(:zrange)
      end

      def link(matches)
        matches.each do |match|
          term1, term2 = match

          if redis.sadd("links:#{term1}", term2)
            reply "#{term2} has been linked to #{term1}."
          else
            reply "#{term2} is already linked to #{term1}."
          end
        end
      end

      def unlink(matches)
        matches.each do |match|
          term1, term2 = match

          if redis.srem("links:#{term1}", term2)
            reply "#{term2} has been unlinked from #{term1}."
          else
            reply "#{term2} is not linked to #{term1}."
          end
        end
      end

      def modified(matches)
        term = args[1]

        if term.nil? || term.strip.empty?
          reply "Format: #{robot.name}: karma modified TERM"
          return
        end

        user_ids = redis.smembers("modified:#{term}")

        if user_ids.empty?
          reply "#{term} has never been modified."
        else
          reply user_ids.map { |id| User.find_by_id(id).name }.join(", ")
        end
      end

      private

      def modify(matches, delta)
        matches.each do |match|
          term = match[0]

          ttl = redis.ttl("cooldown:#{user.id}:#{term}")
          if ttl >= 0
            cooldown_message =
              "You cannot modify #{term} for another #{ttl} second"
            cooldown_message << (ttl == 1 ? "." : "s.")
            reply cooldown_message
            return
          else
            redis.zincrby("terms", delta, term)
            redis.sadd("modified:#{term}", user.id)
            cooldown = Lita.config.handlers.karma.cooldown
            if cooldown
              redis.setex("cooldown:#{user.id}:#{term}", cooldown.to_i, 1)
            end
          end
        end

        check(matches)
      end

      def list(redis_command)
        n = (args[1] || 5).to_i - 1

        terms_scores = redis.public_send(
          redis_command, "terms", 0, n, with_scores: true
        )

        output = terms_scores.each_with_index.map do |term_score, index|
          "#{index + 1}. #{term_score[0]} (#{term_score[1].to_i})"
        end.join("\n")

        if output.length == 0
          reply "There are no terms being tracked yet."
        else
          reply output
        end
      end
    end

    Lita.config.handlers.karma = Config.new
    Lita.config.handlers.karma.cooldown = 300
    Lita.register_handler(Karma)
  end
end
