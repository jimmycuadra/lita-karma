require "spec_helper"

describe Lita::Handlers::Karma::Upgrade::ModifiedCounts, lita_handler: true do
  let(:payload) { double("payload") }

  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  describe "#modified_counts" do
    before do
      subject.redis.flushdb
      subject.redis.zadd('terms', 2, 'foo')
      subject.redis.sadd('modified:foo', %w{bar baz})
    end

    it 'gives every modifier a single point' do
      subject.modified_counts(payload)
      expect(subject.redis.type('modified:foo')).to eq 'zset'
      expect(subject.redis.zrange('modified:foo', 0, -1, with_scores: true)).to eq(
        [['bar', 1.0], ['baz', 1.0]]
      )
    end

    it "skips the update if it's already been done" do
      expect(subject.log).to receive(:debug).with(/modified counts/).once
      subject.modified_counts(payload)
      subject.modified_counts(payload)
    end

    it 'uses the upgrade Proc, if configured' do
      registry.config.handlers.karma.upgrade_modified = Proc.new do |score, uids|
        uids.sort.each_with_index.map {|u, i| [i * score, u]}
      end

      subject.modified_counts(payload)
      expect(subject.redis.zrange('modified:foo', 0, -1, with_scores: true)).to eq(
        [['bar', 0.0], ['baz', 2.0]]
      )
    end

    it 'upgrades the sets for which there are no terms' do
      subject.redis.sadd('modified:bar', %w{baz bot})

      subject.modified_counts(payload)
      expect(subject.redis.type('modified:bar')).to eq 'zset'
    end
  end
end
