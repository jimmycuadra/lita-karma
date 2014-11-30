require "spec_helper"

describe Lita::Handlers::Karma::Upgrade::Decay, lita_handler: true do
  let(:payload) { double("payload") }

  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  describe "#decay" do
    shared_examples_for 'decay' do
      before do
        subject.redis.flushdb
        registry.config.handlers.karma.decay = true
        registry.config.handlers.karma.decay_interval = 24 * 60 * 60
      end

      it 'creates actions for every counted modification' do
        subject.redis.zadd('terms', sign * 5, 'foo')
        subject.redis.zadd('modified:foo', { joe: 2, amy: 3 }.invert.to_a)
        subject.decay(payload)
        expect(subject.redis.zcard('actions')).to eq(5)
      end

      it 'spreads actions out using the decay_distributor Proc' do
        registry.config.handlers.karma.decay_distributor = Proc.new do |interval, i, count|
          1000 * (i + 1)
        end
        subject.redis.zadd('terms', sign * 5, 'foo')
        subject.redis.zadd('modified:foo', { joe: 2, amy: 3 }.invert.to_a)
        time = Time.now
        subject.decay(payload)
        actions = subject.redis.zrange('actions', 0, -1, with_scores: true)

        # bar gets 1k & 2k, baz get 3k, 2k, & 1k
        [3,2,2,1,1].zip(actions.map(&:last)).each do |expectation, value|
          expect((time - value).to_f).to be_within(100).of(expectation * 1000)
        end
      end

      it 'creates anonymous actions for the unknown modifications' do
        subject.redis.zadd('terms', sign * 50, 'foo')
        subject.redis.zadd('modified:foo', { joe: 2, amy: 3 }.invert.to_a)
        subject.decay(payload)
        action_scores = subject.redis.zrange('actions', 0, -1, withscores:true).map do |x|
          Lita::Handlers::Karma::Action.from_json(x[0]).delta
        end
        expect(action_scores.inject(0, &:+)).to eq(sign * 50)
      end

      it 'only creates missing actions' do
        subject.redis.zadd('terms', sign * 7, 'foo')
        subject.redis.zadd('modified:foo', { joe: 2, amy: 3 }.invert.to_a)
        [:joe, :amy, nil].each do |modifying_user_id|
          Lita::Handlers::Karma::Action.create(subject.redis, 'foo', modifying_user_id, sign)
        end
        subject.decay(payload)
        action_scores = subject.redis.zrange('actions', 0, -1, withscores:true).map do |x|
          Lita::Handlers::Karma::Action.from_json(x[0]).delta
        end
        expect(action_scores.inject(0, &:+)).to eq(sign * 7)
      end

      it "skips if the update if it's already been done" do
        expect(subject.log).to receive(:debug).with(/decay/).once
        subject.decay(payload)
        subject.decay(payload)
      end
    end

    context 'with positive karma' do
      include_examples 'decay' do
        let(:sign) { 1 }
      end
    end

    context 'with negative karma' do
      include_examples 'decay' do
        let(:sign) { -1 }
      end
    end
  end
end
