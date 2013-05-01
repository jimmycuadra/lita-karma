require "lita"

# TODO:
# - Term modification lists
# - Linking
#
# lita:handlers:karma:terms { foo(3) }
# lita:handlers:karma:modified:foo ["jimmy", "tamara"]
# lita:handlers:karma:recent:jimmy:foo "1"
# lita:handlers:karma:links:foo ["bar"]
module Lita
  module Handlers
    class Karma < Handler
      RATE_LIMIT = 5 * 60 # 5 minutes

      listener :increment, /([^\s]{2,})\+\+/
      listener :decrement, /([^\s]{2,})--/
      listener :check, /([^\s]{2,})~~/
      command :karma, "karma"
      # command :link, /([^\s]{2,})\s*\+=\s*([^\s]{2,})/
      # command :unlink, /([^\s]{2,})\s*-=\s*([^\s]{2,})/

      def increment
        modify(1)
      end

      def decrement
        modify(-1)
      end

      def check
        matches.each do |match|
          term = match[0]
          score = storage.zscore("terms", term).to_i
          say "#{term}: #{score}"
        end
      end

      def karma
        case args.first
        when "worst"
          list(:zrange)
        else
          list(:zrevrange)
        end
      end

      private

      def modify(delta)
        matches.each do |match|
          term = match[0]

          if rate_limited?(message.user, term)
            say "Sorry, #{message.user}, you can only upvote or downvote a " +
              "term once per five minutes."
          else
            score = storage.zincrby("terms", delta, term).to_i
            storage.sadd("modified:#{term}", message.user.id)
            storage.set("recent:#{message.user.id}:#{term}", 1)
            storage.expire("recent:#{message.user.id}:#{term}", RATE_LIMIT)
            say "#{term}: #{score}"
          end
        end
      end

      def rate_limited?(user, term)
        storage.ttl("recent:#{user.id}:#{term}") >= 0
      end

      def list(redis_command)
        n = (args[1] || 5).to_i - 1

        terms = storage.public_send(
          redis_command, "terms", 0, n, with_scores: true
        )
        terms = terms.each_with_index.map do |term_with_score, index|
          "#{index + 1}. #{term_with_score[0]} (#{term_with_score[1].to_i})"
        end

        say terms
      end
    end

    Lita.register_handler(Karma)
  end
end
