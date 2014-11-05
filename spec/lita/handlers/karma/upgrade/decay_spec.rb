require "spec_helper"

describe Lita::Handlers::Karma::Upgrade::Decay, lita_handler: true do
  let(:payload) { double("payload") }

  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  describe "#decay" do
    before do
      subject.redis.flushdb
      registry.config.handlers.karma.decay = true
      registry.config.handlers.karma.decay_interval = 24 * 60 * 60
    end

    it 'creates actions for every counted modification' do
      subject.redis.zadd('terms', 5, 'foo')
      subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
      subject.decay(payload)
      expect(subject.redis.zcard('actions')).to eq(5)
    end

    it 'spreads actions out using the decay_distributor Proc' do
      registry.config.handlers.karma.decay_distributor = Proc.new do |interval, i, count|
        1000 * (i + 1)
      end
      subject.redis.zadd('terms', 5, 'foo')
      subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
      time = Time.now
      subject.decay(payload)
      actions = subject.redis.zrange('actions', 0, -1, with_scores: true)

      # bar gets 1k & 2k, baz get 3k, 2k, & 1k
      [3,2,2,1,1].zip(actions.map(&:last)).each do |expectation, value|
        expect((time - value).to_f).to be_within(100).of(expectation * 1000)
      end
    end

    it 'creates anonymous actions for the unknown modifications' do
      subject.redis.zadd('terms', 50, 'foo')
      subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
      subject.decay(payload)
      expect(subject.redis.zcard('actions')).to eq(50)
    end

    it 'only creates missing actions' do
      subject.redis.zadd('terms', 7, 'foo')
      subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
      [:bar, :baz, nil].each {|mod| subject.send(:add_action, 'foo', mod, 1)}
      subject.decay(payload)
      expect(subject.redis.zcard('actions')).to eq(7)
    end

    it "skips if the update if it's already been done" do
      expect(subject.log).to receive(:debug).with(/decay/).once
      subject.decay(payload)
      subject.decay(payload)
    end
  end
end
