require "lita"

Lita.load_locales Dir[File.expand_path(
  File.join("..", "..", "locales", "*.yml"), __FILE__
)]

require "lita/handlers/karma"
require 'lita/handlers/karma/action'
require 'lita/handlers/karma/config'
require 'lita/handlers/karma/upgrade'
