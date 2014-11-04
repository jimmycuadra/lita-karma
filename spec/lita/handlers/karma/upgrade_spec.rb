require "spec_helper"

describe Lita::Handlers::Karma::Upgrade, lita_handler: true do
  let(:payload) { double("payload") }

  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  describe "#update_data" do
    before { subject.redis.flushdb }

    describe 'reverse links' do
      it "adds reverse link data for all linked terms" do
        subject.redis.sadd("links:foo", ["bar", "baz"])
        subject.upgrade_data(payload)
        expect(subject.redis.sismember("linked_to:bar", "foo")).to be(true)
        expect(subject.redis.sismember("linked_to:baz", "foo")).to be(true)
      end

      it "skips the update if it's already been done" do
        expect(subject.redis).to receive(:keys).once.and_return([])
        subject.upgrade_data(payload)
        subject.upgrade_data(payload)
      end
    end

    describe 'modified counts' do
      before do
        subject.redis.zadd('terms', 2, 'foo')
        subject.redis.sadd('modified:foo', %w{bar baz})
      end

      it 'gives every modifier a single point' do
        subject.upgrade_data(payload)
        expect(subject.redis.type('modified:foo')).to eq 'zset'
        expect(subject.redis.zrange('modified:foo', 0, -1, with_scores: true)).to eq [['bar', 1.0], ['baz', 1.0]]
      end

      xit "skips the update if it's already been done" do
        expect(subject.redis).to receive(:zrange).once.and_return([])
        subject.upgrade_data(payload)
        subject.upgrade_data(payload)
      end

      it 'uses the upgrade Proc, if configured' do
        registry.config.handlers.karma.upgrade_modified = Proc.new do |score, uids|
          uids.sort.each_with_index.map {|u, i| [i * score, u]}
        end

        subject.upgrade_data(payload)
        expect(subject.redis.zrange('modified:foo', 0, -1, with_scores: true)).to eq [['bar', 0.0], ['baz', 2.0]]
      end
    end

    describe 'score decay' do
      before do
        registry.config.handlers.karma.decay = true
        registry.config.handlers.karma.decay_interval = 24 * 60 * 60
      end

      it 'creates actions to match the current scores' do
        subject.redis.zadd('terms', 2, 'foo')
        subject.redis.sadd('modified:foo', %w{bar baz})
        subject.upgrade_data(payload)
        expect(subject.redis.zcard('actions')).to be(2)
      end

      it 'creates actions for every counted modification' do
        subject.redis.zadd('terms', 5, 'foo')
        subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
        subject.upgrade_data(payload)
        expect(subject.redis.zcard('actions')).to be(5)
      end

      it 'spreads actions out using the decay_distributor Proc' do
        registry.config.handlers.karma.decay_distributor = Proc.new {|i, count| 1000 * (i + 1) }
        subject.redis.zadd('terms', 5, 'foo')
        subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
        time = Time.now
        subject.upgrade_data(payload)
        actions = subject.redis.zrange('actions', 0, -1, with_scores: true)

        # bar gets 1k & 2k, baz get 3k, 2k, & 1k
        [3,2,2,1,1].zip(actions.map(&:last)).each do |expectation, value|
          expect((time - value).to_f).to be_within(100).of(expectation * 1000)
        end
      end

      it 'creates anonymous actions for the unknown modifications' do
        subject.redis.zadd('terms', 50, 'foo')
        subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
        subject.upgrade_data(payload)
        expect(subject.redis.zcard('actions')).to be(50)
      end

      it 'only creates missing actions' do
        subject.redis.zadd('terms', 7, 'foo')
        subject.redis.zadd('modified:foo', {bar: 2, baz: 3}.invert.to_a)
        [:bar, :baz, nil].each {|mod| subject.send(:add_action, 'foo', mod)}
        subject.upgrade_data(payload)
        expect(subject.redis.zcard('actions')).to be(7)
      end

      it 'skips if the actions are up-to-date' do
        expect(subject.redis).to receive(:zrange).thrice.and_return([])
        subject.upgrade_data(payload)
        subject.upgrade_data(payload)
      end
    end
  end
end
