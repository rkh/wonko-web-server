require 'wonko'

module Wonko
  class Acceptor < EventMachine::Connection
    def initialize(server)
      @server = server
      super()
    end

    def notify_readable
      io = @io.kgio_tryaccept
      EventMachine.attach(io, Connection, @server) if io
    end
  end
end