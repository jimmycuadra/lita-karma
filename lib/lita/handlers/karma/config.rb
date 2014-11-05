module Lita::Handlers::Karma
  class Config < Lita::Handler
    namespace "karma"

    CALLABLE_VALIDATOR = proc do |value|
        t("callable_required") unless value.respond_to?(:call)
    end

    class << self
      def default_decay_distributor(decay_interval, index, item_count)
        x = 4 * decay_interval / (item_count + 1) * (index + 1)
        decay_interval - (decay_interval * x.to_f / Math.sqrt(x ** 2 + decay_interval ** 2))
      end

      def default_modified_upgrader(_score, user_ids)
        user_ids.map { |t| [1, t] }
      end
    end

    config :cooldown, types: [Integer, nil], default: 300
    config :link_karma_threshold, types: [Integer, nil], default: 10
    config :term_pattern, type: Regexp, default: /[\[\]\p{Word}\._|\{\}]{2,}/
    config :term_normalizer do
      validate(&CALLABLE_VALIDATOR)
    end
    config :upgrade_modified, default: method(:default_modified_upgrader) do
      validate(&CALLABLE_VALIDATOR)
    end
    config :decay, types: [TrueClass, FalseClass], required: true, default: false
    config :decay_interval, type: Integer, default: 30 * 24 * 60 * 60
    config :decay_distributor, default: method(:default_decay_distributor) do
      validate(&CALLABLE_VALIDATOR)
    end
  end
end

Lita.register_handler(Lita::Handlers::Karma::Config)
