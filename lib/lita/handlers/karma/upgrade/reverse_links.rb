module Lita::Handlers::Karma::Upgrade
  class ReverseLinks
    extend Lita::Handler::EventRouter

    namespace "karma"

    on :loaded, :reverse_links

    def reverse_links(payload)
      unless redis.exists("support:reverse_links")
        log.debug "Upgrading data to include reverse links."

        redis.keys("links:*").each do |key|
          term = key.sub(/^links:/, "")
          redis.smembers(key).each do |link|
            redis.sadd("linked_to:#{link}", term)
          end
        end
        redis.incr("support:reverse_links")
      end
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Upgrade::ReverseLinks)
