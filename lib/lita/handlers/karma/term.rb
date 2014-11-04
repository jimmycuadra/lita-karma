module Lita::Handlers::Karma
  class Term
    include Lita::Handler::Common

    namespace "karma"

    attr_reader :term

    def initialize(robot, term, normalize: true)
      super(robot)
      @term = normalize ? normalize_term(term) : term
      @link_cache = {}
    end

    def ==(other)
      term == other.term
    end

    def check
      string = "#{self}: #{total_score}"

      unless links_with_scores.empty?
        link_text = links_with_scores.map { |term, score| "#{term}: #{score}" }.join(", ")
        string << " (#{own_score}), #{t("linked_to")}: #{link_text}"
      end

      string
    end

    def decrement(user)
      modify(user, -1)
    end

    def delete
      redis.zrem("terms", to_s)
      redis.del("modified:#{self}")
      redis.del("links:#{self}")
      redis.smembers("linked_to:#{self}").each do |key|
        redis.srem("links:#{key}", to_s)
      end
      redis.del("linked_to:#{self}")
    end

    def increment(user)
      modify(user, 1)
    end

    def link(other)
      if config.link_karma_threshold
        threshold = config.link_karma_threshold.abs

        if own_score.abs < threshold || other.own_score.abs < threshold
          return threshold
        end
      end

      redis.sadd("links:#{self}", other.to_s) && redis.sadd("linked_to:#{other}", to_s)
    end

    def links
      @links ||= begin
        redis.smembers("links:#{self}").each do |term|
          linked_term = self.class.new(robot, term)
          @link_cache[linked_term.term] = linked_term
        end
      end
    end

    def links_with_scores
      @links_with_scores ||= begin
        {}.tap do |h|
          links.each do |link|
            h[link] = @link_cache[link].own_score
          end
        end
      end
    end

    def modified
      redis.zrevrange("modified:#{self}", 0, -1, with_scores: true).map do |(user_id, score)|
        [Lita::User.find_by_id(user_id), score.to_i]
      end
    end

    def own_score
      @own_score ||= redis.zscore("terms", term).to_i
    end

    def to_s
      term
    end

    def total_score
      @total_score ||= begin
        links.inject(own_score) do |memo, linked_term|
          memo + @link_cache[linked_term].own_score
        end
      end
    end

    def unlink(other)
      redis.srem("links:#{self}", other.to_s) && redis.srem("linked_to:#{other}", to_s)
    end

    private

    def modify(user, delta)
      user_id = user.id

      ttl = redis.ttl("cooldown:#{user_id}:#{term}")

      if ttl > 0
        t("cooling_down", term: self, ttl: ttl, count: ttl)
      else
        redis.zincrby("terms", delta, term)
        redis.zincrby("modified:#{self}", 1, user_id)
        redis.setex("cooldown:#{user_id}:#{self}", config.cooldown, 1) if config.cooldown
        check
      end
    end

    def normalize_term(term)
      if config.term_normalizer
        config.term_normalizer.call(term)
      else
        term.to_s.downcase.strip
      end
    end
  end
end
