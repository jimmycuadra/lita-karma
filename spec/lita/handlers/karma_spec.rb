require "spec_helper"

describe Lita::Handlers::Karma, lita_handler: true do
  let(:payload) { double("payload") }

  before do
    Lita.config.handlers.karma.cooldown = nil
    described_class.routes.clear
    subject.define_routes(payload)
  end

  it { routes("foo++").to(:increment) }
  it { routes("foo--").to(:decrement) }
  it { routes("foo~~").to(:check) }
  it { routes_command("karma best").to(:list_best) }
  it { routes_command("karma worst").to(:list_worst) }
  it { routes_command("karma modified").to(:modified) }
  it { routes_command("karma delete").to(:delete) }
  it { routes_command("karma").to(:list_best) }
  it { routes_command("foo += bar").to(:link) }
  it { routes_command("foo -= bar").to(:unlink) }
  it { doesnt_route("+++++").to(:increment) }
  it { doesnt_route("-----").to(:decrement) }

  describe "#update_data" do
    before { subject.redis.flushdb }

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

  describe "#increment" do
    it "increases the term's score by one and says the new score" do
      send_message("foo++")
      expect(replies.last).to eq("foo: 1")
    end

    it "matches multiple terms in one message" do
      send_message("foo++ bar++")
      expect(replies).to eq(["foo: 1", "bar: 1"])
    end

    it "doesn't start from zero if the term already has a positive score" do
      send_message("foo++")
      send_message("foo++")
      expect(replies.last).to eq("foo: 2")
    end

    it "replies with a warning if term increment is on cooldown" do
      Lita.config.handlers.karma.cooldown = 10
      send_message("foo++")
      send_message("foo++")
      expect(replies.last).to match(/cannot modify foo/)
    end

    it "is case insensitive" do
      send_message("foo++")
      send_message("FOO++")
      expect(replies.last).to eq("foo: 2")
    end

    it "handles Unicode word characters" do
      send_message("föö++")
      expect(replies.last).to eq("föö: 1")
    end
  end

  describe "#decrement" do
    it "decreases the term's score by one and says the new score" do
      send_message("foo--")
      expect(replies.last).to eq("foo: -1")
    end

    it "matches multiple terms in one message" do
      send_message("foo-- bar--")
      expect(replies).to eq(["foo: -1", "bar: -1"])
    end

    it "doesn't start from zero if the term already has a positive score" do
      send_message("foo++")
      send_message("foo--")
      expect(replies.last).to eq("foo: 0")
    end

    it "replies with a warning if term increment is on cooldown" do
      Lita.config.handlers.karma.cooldown = 10
      send_message("foo--")
      send_message("foo--")
      expect(replies.last).to match(/cannot modify foo/)
    end
  end

  describe "#check" do
    it "says the term's current score" do
      send_message("foo~~")
      expect(replies.last).to eq("foo: 0")
    end

    it "matches multiple terms in one message" do
      send_message("foo~~ bar~~")
      expect(replies).to eq(["foo: 0", "bar: 0"])
    end
  end

  describe "#list" do
    it "replies with a warning if there are no terms" do
      send_command("karma")
      expect(replies.last).to match(/no terms being tracked/)
    end

    context "with modified terms" do
      before do
        send_message(
          "one++ one++ one++ two++ two++ three++ four++ four-- five--"
        )
      end

      it "lists the top 5 terms by default" do
        send_command("karma")
        expect(replies.last).to eq <<-MSG.chomp
1. one (3)
2. two (2)
3. three (1)
4. four (0)
5. five (-1)
MSG
      end

      it 'lists the bottom 5 terms when passed "worst"' do
        send_command("karma worst")
        expect(replies.last).to eq <<-MSG.chomp
1. five (-1)
2. four (0)
3. three (1)
4. two (2)
5. one (3)
MSG
      end

      it "limits the list to the count passed as the second argument" do
        send_command("karma best 2")
        expect(replies.last).to eq <<-MSG.chomp
1. one (3)
2. two (2)
MSG
      end
    end
  end

  describe "#link" do
    it "says that it's linked term 2 to term 1" do
      send_command("foo += bar")
      expect(replies.last).to eq("bar has been linked to foo.")
    end

    it "says that term 2 was already linked to term 1 if it was" do
      send_command("foo += bar")
      send_command("foo += bar")
      expect(replies.last).to eq("bar is already linked to foo.")
    end

    it "causes term 1's score to be modified by term 2's" do
      send_message("foo++ bar++ baz++")
      send_command("foo += bar")
      send_command("foo += baz")
      send_message("foo~~")
      expect(replies.last).to match(
        /foo: 3 \(1\), linked to: ba[rz]: 1, ba[rz]: 1/
      )
    end
  end

  describe "#unlink" do
    it "says that it's unlinked term 2 from term 1" do
      send_command("foo += bar")
      send_command("foo -= bar")
      expect(replies.last).to eq("bar has been unlinked from foo.")
    end

    it "says that term 2 was not linked to term 1 if it wasn't" do
      send_command("foo -= bar")
      expect(replies.last).to eq("bar is not linked to foo.")
    end

    it "causes term 1's score to stop being modified by term 2's" do
      send_message("foo++ bar++")
      send_command("foo += bar")
      send_command("foo -= bar")
      send_message("foo~~")
      expect(replies.last).to eq("foo: 1")
    end
  end

  describe "#modified" do
    it "replies with the required format if a term is not provided" do
      send_command("karma modified")
      expect(replies.last).to match(/^Format:/)
    end

    it "replies with the required format if the term is an empty string" do
      send_command("karma modified '   '")
      expect(replies.last).to match(/^Format:/)
    end

    it "replies with a message if the term hasn't been modified" do
      send_command("karma modified foo")
      expect(replies.last).to match(/never been modified/)
    end

    it "lists users who have modified the given term" do
      allow(Lita::User).to receive(:find_by_id).and_return(user)
      send_message("foo++")
      send_command("karma modified foo")
      expect(replies.last).to eq(user.name)
    end
  end

  describe "#delete" do
    before do
      allow(Lita::Authorization).to receive(:user_in_group?).and_return(true)
    end

    it "deletes the term" do
      send_message("foo++")
      send_command("karma delete foo")
      expect(replies.last).to eq("foo has been deleted.")
      send_message("foo~~")
      expect(replies.last).to eq("foo: 0")
    end

    it "replies with a warning if the term doesn't exist" do
      send_command("karma delete foo")
      expect(replies.last).to eq("foo does not exist.")
    end

    it "matches terms exactly, including leading whitespace" do
      term = "  'foo bar* 'baz''/ :"
      subject.redis.zincrby("terms", 1, term)
      send_command("karma delete #{term}")
      expect(replies.last).to include("has been deleted")
    end

    it "clears the modification list" do
      send_message("foo++")
      send_command("karma delete foo")
      send_command("karma modified foo")
      expect(replies.last).to eq("foo has never been modified.")
    end

    it "clears the deleted term's links" do
      send_command("foo += bar")
      send_command("foo += baz")
      send_command("karma delete foo")
      send_message("foo++")
      expect(replies.last).to eq("foo: 1")
    end

    it "clears links from other terms connected to the deleted term" do
      send_command("bar += foo")
      send_command("baz += foo")
      send_command("karma delete foo")
      send_message("bar++")
      expect(replies.last).to eq("bar: 1")
      send_message("baz++")
      expect(replies.last).to eq("baz: 1")
    end
  end

  describe "custom term patterns and normalization" do
    before do
      Lita.config.handlers.karma.term_pattern = /[<:]([^>:]+)[>:]/
      Lita.config.handlers.karma.term_normalizer = lambda do |term|
        term.to_s.downcase.strip.sub(/[<:]([^>:]+)[>:]/, '\1')
      end
      described_class.routes.clear
      subject.define_routes(payload)
    end

    it "increments multi-word terms bounded by delimeters" do
      send_message(":Some Thing:++")
      expect(replies.last).to eq("some thing: 1")
    end

    it "increments terms with symbols that are bounded by delimeters" do
      send_message("<C++>++")
      expect(replies.last).to eq("c++: 1")
    end

    it "decrements multi-word terms bounded by delimeters" do
      send_message(":Some Thing:--")
      expect(replies.last).to eq("some thing: -1")
    end

    it "checks multi-word terms bounded by delimeters" do
      send_message(":Some Thing:~~")
      expect(replies.last).to eq("some thing: 0")
    end
  end
end
