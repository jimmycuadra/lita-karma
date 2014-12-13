module Lita::Handlers::Karma
  class Config < Lita::Handler
    namespace "karma"

    CALLABLE_VALIDATOR = proc do |value|
        t("callable_required") unless value.respond_to?(:call)
    end

    class << self
      def default_decay_distributor(decay_interval, index, item_count)
        decay_interval.to_f / (item_count + 1) * (index + 1)
      end

      def default_modified_upgrader(_score, user_ids)
        user_ids.map { |t| [1, t] }
      end

      def default_term_normalizer(term)
        term.to_s.downcase.strip
      end
    end

    config :cooldown, types: [Integer, nil], default: 300
    config :link_karma_threshold, types: [Integer, nil], default: 10
    config :term_pattern, type: Regexp, default: /[\[\]\p{Word}\._|\{\}]{2,}/
    config :term_normalizer, default: method(:default_term_normalizer) do
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
