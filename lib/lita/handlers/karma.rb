require "lita"

module Lita
  module Handlers
    class Karma < Handler
      route %r{([^\s]{2,})\+\+}, to: :increment
      route %r{([^\s]{2,})\-\-}, to: :decrement
      route %r{([^\s]{2,})~~}, to: :check
      route %r{karma}, to: :list, command: true
      route %r{([^\s]{2,})\s*\+=\s*([^\s]{2,})}, to: :link, command: true
      route %r{([^\s]{2,})\s*-=\s*([^\s]{2,})}, to: :unlink, command: true

      def increment(matches)
        modify(matches, 1)
      end

      def decrement(matches)
        modify(matches, -1)
      end

      def check(matches)
        matches.each do |match|
          term = match[0]
          score = redis.zscore("terms", term).to_i
          redis.smembers("links:#{term}").each do |link|
            score += redis.zscore("terms", link).to_i
          end
          reply "#{term}: #{score}"
        end
      end

      def list(matches)
        redis_command = case args.first
        when "worst"
          :zrange
        else
          :zrevrange
        end

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

      private

      def modify(matches, delta)
        matches.each do |match|
          term = match[0]
          score = redis.zincrby("terms", delta, term).to_i
          reply "#{term}: #{score}"
        end
      end
    end

    Lita.register_handler(Karma)
  end
end
