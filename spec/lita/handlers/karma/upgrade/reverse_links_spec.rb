require "spec_helper"

describe Lita::Handlers::Karma::Upgrade::ReverseLinks, lita_handler: true do
  let(:payload) { double("payload") }

  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  describe "#reverse_links" do
    before { subject.redis.flushdb }

    it "adds reverse link data for all linked terms" do
      subject.redis.sadd("links:foo", ["bar", "baz"])
      subject.reverse_links(payload)
      expect(subject.redis.sismember("linked_to:bar", "foo")).to be(true)
      expect(subject.redis.sismember("linked_to:baz", "foo")).to be(true)
    end

    it "skips the update if it's already been done" do
      expect(subject.log).to receive(:debug).with(/reverse links/).once
      subject.reverse_links(payload)
      subject.reverse_links(payload)
    end
  end
end
