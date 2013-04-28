require "lita"

# TODO:
# - Rate limiting
# - Term modification lists
# - Linking
#
# lita:handlers:karma:terms { foo(3) }
# lita:handlers:karma:terms:foo:modified ["jimmy", "tamara"]
# lita:handlers:karma:recent:jimmy:foo "1"
# lita:handlers:karma:term_links:foo ["bar"]
module Lita
  module Handlers
    class Karma < Handler
      listener :increment, /([^\s]{2,})\+\+/
      listener :decrement, /([^\s]{2,})--/
      listener :check, /([^\s]{2,})~~/
      # command :karma, "karma"
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

      private

      def modify(delta)
        user_id = message.user.id

        matches.each do |match|
          term = match[0]
          score = storage.zincrby("terms", delta, term).to_i
          storage.sadd("terms:#{term}:modified", user_id)
          say "#{term}: #{score}"
        end
      end
    end

    Lita.register_handler(Karma)
  end
end
