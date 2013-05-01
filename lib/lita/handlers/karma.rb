require "lita"

# TODO:
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
      command :link, /([^\s]{2,})\s*\+=\s*([^\s]{2,})/
      command :unlink, /([^\s]{2,})\s*-=\s*([^\s]{2,})/

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
        when "modified"
          modified
        when "worst"
          list(:zrange)
        else
          list(:zrevrange)
        end
      end

      def link
        matches.each do |match|
          term1, term2 = match
          storage.sadd("links:#{term1}", term2)
          say "#{term2} has been linked to #{term1}."
        end
      end

      def unlink
        matches.each do |match|
          term1, term2 = match
          storage.srem("links:#{term1}", term2)
          say "#{term2} has been unlinked from #{term1}."
        end
      end

      private

      def modify(delta)
        matches.each do |match|
          term = match[0]

          if rate_limited?(term)
            say "Sorry, #{message.user}, you can only upvote or downvote a " +
              "term once per five minutes."
          else
            score, *unused = storage.multi do |multi|
              multi.zincrby("terms", delta, term)
              multi.sadd("modified:#{term}", message.user.id)
              multi.set("recent:#{message.user.id}:#{term}", 1)
              multi.expire("recent:#{message.user.id}:#{term}", RATE_LIMIT)
            end

            say "#{term}: #{score.to_i}"
          end
        end
      end

      def rate_limited?(term)
        storage.ttl("recent:#{message.user.id}:#{term}") >= 0
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

      def modified
        term = args[1]

        if term.nil? || term.empty?
          return say "You must tell me which term you are curious about."
        end

        users = storage.smembers("modified:#{term}")

        if users.empty?
          say "#{term} has never been modified."
        else
          say "#{term} has been modified by: #{users.join(", ")}"
        end
      end
    end

    Lita.register_handler(Karma)
  end
end
