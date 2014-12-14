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

        # joe gets 1k & 3k, amy gets 2k, 4k, & 5k
        (1..5).to_a.reverse.zip(actions.map(&:last)).each do |expectation, value|
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

      it 'creates anonymous actions that decay before known actor modifications' do
        registry.config.handlers.karma.decay_distributor = Proc.new do |interval, i, count|
          1000 * (i + 1)
        end

        subject.redis.zadd('terms', sign * 10, 'foo')
        subject.redis.zadd('modified:foo', { joe: 2, amy: 3 }.invert.to_a)
        time = Time.now
        subject.decay(payload)
        actions = subject.redis.zrange('actions', 0, -1, with_scores: true).map do |x|
          Lita::Handlers::Karma::Action.from_json(x[0])
        end

        users = ([nil] * 5) + %w{amy amy joe amy joe}

        (1..10).to_a.reverse.zip(users, actions).each do |diff, user_id, action|
          expect(action.user_id).to eql(user_id)
          expect((time - action.time).to_f).to be_within(100).of(1000 * diff)
        end
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
