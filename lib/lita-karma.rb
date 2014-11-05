require "lita"

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

module Lita
  module Handlers
    module Karma
      module Upgrade
      end
    end
  end
end

require 'lita/handlers/karma/action'
require "lita/handlers/karma/chat"
require 'lita/handlers/karma/config'
require 'lita/handlers/karma/term'
require 'lita/handlers/karma/upgrade/reverse_links'
require 'lita/handlers/karma/upgrade/modified_counts'
require 'lita/handlers/karma/upgrade/decay'
