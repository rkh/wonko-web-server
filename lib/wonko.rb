module Wonko
  autoload :Acceptor,   'wonko/acceptor'
  autoload :Connection, 'wonko/connection'
  autoload :Server,     'wonko/server'
  autoload :Utils,      'wonko/utils'
  autoload :VERSION,    'wonko/version'

  def self.run(*args, &block)   Server.run(*args, &block)   end
  def self.start(*args, &block) Server.start(*args, &block) end
end

require 'rack'
Rack::Handler.register 'wonko', 'Wonko'
