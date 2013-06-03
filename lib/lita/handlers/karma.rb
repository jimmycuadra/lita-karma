require "lita"

module Lita
  module Handlers
    class Karma < Handler
      listener :increment, /([^\s]{2,})\+\+/
      listener :decrement, /([^\s]{2,})--/
      listener :check, /([^\s]{2,})~~/
      command :karma, /karma/
      command :link, /([^\s]{2,})\s*\+=\s*([^\s]{2,})/
      command :unlink, /([^\s]{2,})\s*-=\s*([^\s]{2,})/
    end

    Lita.register_handler(Karma)
  end
end
