module Lita::Handlers::Karma
  class Action
    attr_reader :term, :user_id, :delta, :at

    def initialize(term, user_id, delta = 1, at = Time.now)
      (@term, @user_id, @delta, @at) = [term, user_id, delta, at.to_time]
    end

    def serialize
      MultiJson.dump [term, user_id, delta, at.to_f]
    end

    def self.deserialize(str)
      tuple = MultiJson.load(str)
      tuple[3] = Time.at(tuple[3])
      self.new(*tuple)
    end

    def to_s
      [term, user_id, delta, at].inspect
    end
  end
end
