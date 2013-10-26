require "lita"

module Lita
  module Handlers
    # Tracks karma points for arbitrary terms.
    class Karma < Handler
      TERM_REGEX = /[\[\]\w\._|\{\}]{2,}/

      route %r{(#{TERM_REGEX.source})\+\+}, :increment, help: {
        "TERM++" => "Increments TERM by one."
      }
      route %r{(#{TERM_REGEX.source})\-\-}, :decrement, help: {
        "TERM--" => "Decrements TERM by one."
      }
      route %r{(#{TERM_REGEX.source})~~}, :check, help: {
        "TERM~~" => "Shows the current karma of TERM."
      }
      route %r{^karma\s+worst}, :list_worst, command: true, help: {
        "karma worst [N]" => <<-HELP.chomp
Lists the bottom N terms by karma. N defaults to 5.
HELP
      }
      route %r{^karma\s+best}, :list_best, command: true, help: {
        "karma best [N]" => <<-HELP.chomp
Lists the top N terms by karma. N defaults to 5.
HELP
      }
      route %r{^karma\s+modified}, :modified, command: true, help: {
        "karma modified TERM" => <<-HELP.chomp
Lists the names of users who have upvoted or downvoted TERM.
HELP
      }
      route(
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
      route %r{^karma\s*$}, :list_best, command: true
      route(
        %r{^(#{TERM_REGEX.source})\s*\+=\s*(#{TERM_REGEX.source})},
        :link,
        command: true,
        help: {
          "TERM1 += TERM2" => <<-HELP.chomp
Links TERM2 to TERM1. TERM1's karma will then be displayed as the sum of its \
own and TERM2's karma.
HELP
        }
      )
      route(
        %r{^(#{TERM_REGEX.source})\s*-=\s*(#{TERM_REGEX.source})},
        :unlink,
        command: true,
        help: {
          "TERM1 -= TERM2" => <<-HELP.chomp
Unlinks TERM2 from TERM1. TERM1's karma will no longer be displayed as the sum \
of its own and TERM2's karma.
HELP
        }
      )

      def self.default_config(config)
        config.cooldown = 300
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

        user_ids = redis.smembers("modified:#{term}")

        if user_ids.empty?
          response.reply "#{term} has never been modified."
        else
          output = user_ids.map do |id|
            User.find_by_id(id).name
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

        if redis.zrem("terms", term)
          response.reply("#{term} has been deleted.")
        else
          response.reply("#{term} does not exist.")
        end
      end

      private

      def modify(response, delta)
        response.matches.each do |match|
          term = normalize_term(match[0])

          ttl = redis.ttl("cooldown:#{response.user.id}:#{term}")
          if ttl >= 0
            cooldown_message =
              "You cannot modify #{term} for another #{ttl} second"
            cooldown_message << (ttl == 1 ? "." : "s.")
            response.reply cooldown_message
            return
          else
            redis.zincrby("terms", delta, term)
            redis.sadd("modified:#{term}", response.user.id)
            cooldown = Lita.config.handlers.karma.cooldown
            if cooldown
              redis.setex(
                "cooldown:#{response.user.id}:#{term}",
                cooldown.to_i,
                1
              )
            end
          end
        end

        check(response)
      end

      def normalize_term(term)
        term.to_s.downcase.strip
      end

      def list(response, redis_command)
        n = (response.args[1] || 5).to_i - 1

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
    end

    Lita.register_handler(Karma)
  end
end
