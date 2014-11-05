module Lita::Handlers::Karma
  class Term
    include Lita::Handler::Common

    namespace "karma"

    attr_reader :term

    class << self
      def list_best(robot, n = 5)
        list(:zrevrange, robot, n)
      end

      def list_worst(robot, n = 5)
        list(:zrange, robot, n)
      end

      private

      def list(redis_command, robot, n)
        n = 24 if n > 24

        handler = new(robot, '', normalize: false)
        handler.decay
        handler.redis.public_send(redis_command, "terms", 0, n, with_scores: true)
      end
    end

    def initialize(robot, term, normalize: true)
      super(robot)
      @term = normalize ? normalize_term(term) : term
      @link_cache = {}
    end

    def ==(other)
      term == other.term
    end

    def check
      decay

      string = "#{self}: #{total_score}"

      unless links_with_scores.empty?
        link_text = links_with_scores.map { |term, score| "#{term}: #{score}" }.join(", ")
        string << " (#{own_score}), #{t("linked_to")}: #{link_text}"
      end

      string
    end

    def decay
      return unless config.decay
      cutoff = Time.now.to_i - config.decay_interval
      terms = redis.zrangebyscore(:actions, '-inf', cutoff).map { |json| decay_action(json) }
      delete_decayed(terms, cutoff)
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
      decay

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
      decay

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

    def add_action(user_id, delta, time = Time.now)
      return unless config.decay
      action = Action.new(term, user_id, delta, time)
      redis.zadd(:actions, time.to_i, action.serialize)
    end

    def decay_action(json)
      action = Action.from_json(json)
      redis.zincrby(:terms, -action.delta, action.term)
      redis.zincrby("modified:#{action.term}", -1, action.user_id) if action.user_id
      action.term
    end

    def delete_decayed(terms, cutoff)
      redis.zremrangebyscore(:actions, '-inf', cutoff)
      terms.each { |term| redis.zremrangebyscore("modified:#{term}", '-inf', 0) }
    end

    def modify(user, delta)
      decay

      ttl = redis.ttl("cooldown:#{user.id}:#{term}")

      if ttl > 0
        t("cooling_down", term: self, ttl: ttl, count: ttl)
      else
        modify!(user, delta)
      end
    end

    def modify!(user, delta)
      user_id = user.id
      redis.zincrby("terms", delta, term)
      redis.zincrby("modified:#{self}", 1, user_id)
      redis.setex("cooldown:#{user_id}:#{self}", config.cooldown, 1) if config.cooldown
      add_action(user_id, delta)
      check
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
