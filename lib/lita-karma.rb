require "lita"

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

module Lita
  module Handlers
    module Karma
    end
  end
end

require 'lita/handlers/karma/action'
require "lita/handlers/karma/chat"
require 'lita/handlers/karma/config'
require 'lita/handlers/karma/term'
require 'lita/handlers/karma/upgrade'
