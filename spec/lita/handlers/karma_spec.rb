require "spec_helper"

describe Lita::Handlers::Karma, lita_handler: true do
  it { handles("foo++").with(:increment) }
  it { handles("foo--").with(:decrement) }
  it { handles("foo~~").with(:check) }
  it { handles("#{robot.name}: karma").with(:karma) }
  it { handles("#{robot.name} foo += bar").with(:link) }
  it { handles("#{robot.name}: foo -= bar").with(:unlink) }
end
