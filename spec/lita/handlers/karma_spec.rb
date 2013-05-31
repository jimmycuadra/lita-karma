require "spec_helper"

describe Lita::Handlers::Karma, lita_handler: true do
  describe "#increment listener" do
    it "is triggered by term++" do
      described_class.any_instance.should_receive(:increment)
      chat("foo++")
    end
  end

  describe "#decrement listener" do
    it "is triggered by term--" do
      described_class.any_instance.should_receive(:decrement)
      chat("foo--")
    end
  end

  describe "#check listener" do
    it "is triggered by term~~" do
      described_class.any_instance.should_receive(:check)
      chat("foo~~")
    end
  end

  describe "#karma command" do
    it "is triggered by karma" do
      described_class.any_instance.should_receive(:karma)
      chat("#{robot.name}: karma")
    end
  end

  describe "#link command" do
    it "is triggered by foo += bar" do
      described_class.any_instance.should_receive(:link)
      chat("#{robot.name}: foo += bar")
    end
  end

  describe "#unlink command" do
    it "is triggered by foo -= bar" do
      described_class.any_instance.should_receive(:unlink)
      chat("#{robot.name}: foo -= bar")
    end
  end
end
