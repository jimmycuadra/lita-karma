require "spec_helper"

describe Lita::Handlers::Karma::Chat, lita_handler: true do
  let(:payload) { double("payload") }

  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  before do
    registry.config.handlers.karma.cooldown = nil
    registry.config.handlers.karma.link_karma_threshold = nil
    described_class.routes.clear
    subject.define_routes(payload)
  end

  it { is_expected.to route("foo++").to(:increment) }
  it { is_expected.to route("foo--").to(:decrement) }
  it { is_expected.to route("foo++ bar").to(:increment) }
  it { is_expected.to route("foo-- bar").to(:decrement) }
  it { is_expected.to route("foo~~").to(:check) }
  it { is_expected.to route_command("karma best").to(:list_best) }
  it { is_expected.to route_command("karma worst").to(:list_worst) }
  it { is_expected.to route_command("karma modified foo").to(:modified) }
  it do
    is_expected.to route_command("karma delete").with_authorization_for(:karma_admins).to(:delete)
  end
  it { is_expected.to route_command("karma").to(:list_best) }
  it { is_expected.to route_command("foo += bar").to(:link) }
  it { is_expected.to route_command("foo += bar++").to(:link) }
  it { is_expected.to route_command("foo += bar--").to(:link) }
  it { is_expected.to route_command("foo += bar~~").to(:link) }
  it { is_expected.to route_command("foo -= bar").to(:unlink) }
  it { is_expected.to route_command("foo -= bar++").to(:unlink) }
  it { is_expected.to route_command("foo -= bar--").to(:unlink) }
  it { is_expected.to route_command("foo -= bar~~").to(:unlink) }
  it { is_expected.not_to route("+++++").to(:increment) }
  it { is_expected.not_to route("-----").to(:decrement) }
  it { is_expected.not_to route("foo++bar").to(:increment) }
  it { is_expected.not_to route("foo--bar").to(:decrement) }

  describe "#increment" do
    it "increases the term's score by one and says the new score" do
      send_message("foo++")
      expect(replies.last).to eq("foo: 1")
    end

    it "matches multiple terms in one message" do
      send_message("foo++ bar++")
      expect(replies.last).to eq("foo: 1; bar: 1")
    end

    it "doesn't start from zero if the term already has a positive score" do
      send_message("foo++")
      send_message("foo++")
      expect(replies.last).to eq("foo: 2")
    end

    it "replies with a warning if term increment is on cooldown" do
      registry.config.handlers.karma.cooldown = 10
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
      expect(replies.last).to eq("foo: -1; bar: -1")
    end

    it "doesn't start from zero if the term already has a positive score" do
      send_message("foo++")
      send_message("foo--")
      expect(replies.last).to eq("foo: 0")
    end

    it "replies with a warning if term increment is on cooldown" do
      registry.config.handlers.karma.cooldown = 10
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
      expect(replies.last).to eq("foo: 0; bar: 0")
    end

    it "doesn't match the same term multiple times in one message" do
      send_message("foo~~ foo~~")
      expect(replies.size).to eq(1)
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

    context "when link_karma_threshold is set" do
      before do
        registry.config.handlers.karma.link_karma_threshold = 1
      end

      it "doesn't allow a term to be linked if both are below the threshold" do
        send_command("foo += bar")
        expect(replies.last).to include("must have less than")
      end

      it "doesn't allow a term to be linked if it's below the threshold" do
        send_command("foo++")
        send_command("foo += bar")
        expect(replies.last).to include("must have less than")
      end

      it "doesn't allow a term to be linked to another term below the threshold" do
        send_command("bar++")
        send_command("foo += bar")
        expect(replies.last).to include("must have less than")
      end

      it "allows links if both terms meet the threshold" do
        send_command("foo++ bar++")
        send_command("foo += bar")
        expect(replies.last).to include("has been linked")
        send_command("bar += foo")
        expect(replies.last).to include("has been linked")
      end

      it "uses the absolute value for terms with negative karma" do
        send_command("foo-- bar--")
        send_command("foo += bar")
        expect(replies.last).to include("has been linked")
        send_command("bar += foo")
        expect(replies.last).to include("has been linked")
      end
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
    it "replies with a message if the term hasn't been modified" do
      send_command("karma modified foo")
      expect(replies.last).to match(/never been modified/)
    end

    it "lists users who have modified the given term in count order" do
      other_user = Lita::User.create("2", name: "Other User")
      send_message("foo++", as: user)
      send_message("foo++", as: user)
      send_message("foo++", as: other_user)
      send_command("karma modified foo")
      expect(replies.last).to eq("#{user.name}, #{other_user.name}")
    end
  end

  describe "#delete" do
    before do
      robot.auth.add_user_to_group!(user, :karma_admins)
    end

    it "deletes the term" do
      send_message("foo++")
      send_command("karma delete foo")
      expect(replies.last).to eq("foo has been deleted.")
      send_message("foo~~")
      expect(replies.last).to eq("foo: 0")
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
      registry.config.handlers.karma.term_pattern = /[<:]([^>:]+)[>:]/
      registry.config.handlers.karma.term_normalizer = lambda do |term|
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
