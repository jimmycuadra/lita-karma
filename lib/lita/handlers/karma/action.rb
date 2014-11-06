module Lita::Handlers::Karma
  class Action < Struct.new(:term, :user_id, :delta, :time)
    class << self
      def create(redis, term, user_id, delta, time = Time.now)
        action = new(term, user_id, delta, time)
        redis.zadd(:actions, time.to_i, action.serialize)
      end

      def from_json(string)
        tuple = MultiJson.load(string)
        tuple[3] = Time.at(tuple[3])
        self.new(*tuple)
      end
    end

    def serialize
      MultiJson.dump([term, user_id, delta, time.to_i])
    end
  end
end
