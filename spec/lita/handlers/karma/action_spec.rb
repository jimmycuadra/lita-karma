require "spec_helper"

describe Lita::Handlers::Karma::Action do
  let(:term) { 'fnord' }
  let(:user_id) { 23 }
  let(:delta) { 42 }
  let(:time) { Time.now }

  describe '#serialize' do
    subject { described_class.new(term, user_id, time) }
    it 'should return a score and JSON' do
      tuple = MultiJson.load(subject.serialize)
      expect(tuple[0,2]).to eq([term, user_id])
      expect(tuple.last).to be_within(0.1).of(time.to_f)
    end
  end

  describe '.deserialize' do
    subject { described_class.deserialize(MultiJson.dump([term, user_id, delta, time.to_f])) }

    it 'should create a valid object' do
      expect(subject.term).to eq(term)
      expect(subject.user_id).to eq(user_id)
      expect(subject.delta).to eq(delta)
      # float precision is making this test finicky
      expect(subject.at.class).to be(Time)
      expect(subject.at).to be_within(0.1).of(time)
    end

  end
end
