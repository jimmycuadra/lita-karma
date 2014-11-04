require "spec_helper"

describe Lita::Handlers::Karma::Action do
  let(:term) { "fnord" }
  let(:user_id) { 23 }
  let(:delta) { 42 }
  let(:epoch) { 1415136366 }
  let(:time) { Time.at(epoch) }
  let(:action) { described_class.new(term, user_id, delta, time) }

  describe "#serialize" do
    subject { MultiJson.load(action.serialize) }

    it "converts the object into an array" do
      expect(subject[0]).to eq(term)
      expect(subject[1]).to eq(user_id)
      expect(subject[2]).to eq(delta)
      expect(subject[3]).to eq(epoch)
    end
  end

  describe ".from_json" do
    subject { described_class.from_json(action.serialize) }

    it "should create a valid object" do
      expect(subject.term).to eq(term)
      expect(subject.user_id).to eq(user_id)
      expect(subject.delta).to eq(delta)
      expect(subject.time).to eq(time)
    end
  end
end
