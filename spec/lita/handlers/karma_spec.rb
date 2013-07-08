require "spec_helper"

describe Lita::Handlers::Karma, lita_handler: true do
  before { Lita.config.handlers.karma.cooldown = nil }

  it { routes("foo++").to(:increment) }
  it { routes("foo--").to(:decrement) }
  it { routes("foo~~").to(:check) }
  it { routes_command("karma best").to(:list_best) }
  it { routes_command("karma worst").to(:list_worst) }
  it { routes_command("karma modified").to(:modified) }
  it { routes_command("karma").to(:list_best) }
  it { routes_command("foo += bar").to(:link) }
  it { routes_command("foo -= bar").to(:unlink) }

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
end
