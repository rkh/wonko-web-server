require 'wonko'

require 'eventmachine'
require 'http/parser'
require 'socket'
require 'rack'
require 'kgio'

module Wonko
  class Server
    include Utils

    attr_accessor :app, :port, :host, :socket, :workers
    attr_reader :listener, :pids, :running

    def self.run(app, options = {})
      server = new options.merge(:app => app)
      yield server if block_given?
      server.start
    end

    def self.start(*args, &app)
      app = Rack::Builder.app(&app) if app and app.arity.between?(-1, 0) 
      new(app, *args).start
    end

    def initialize(*args)
      @after_fork, @pids = [], []
      parse_args(args)
      yield self if block_given?
      set_defaults
    end

    def after_fork(&block)
      @after_fork << block
    end

    def start
      warn "Wonko web server (v#{VERSION} codename The Sane)"
      warn "Using #{workers} workers"
      @running = true
      @listener = socket ?
        Kgio::UNIXServer.new(socket) :
        Kgio::TCPServer.new(host, port)

      EventMachine.epoll
      EventMachine.kqueue

      # set up more fancy signals here
      at_exit { stop }
      workers.times { start_worker }

      while @running
        child = Process.wait
        if @running
          warn "Process #{child} died, launching new worker"
          pids.delete child
          start_worker
        end
      end
    end

    def stop
      @running = false
      pids.each { |pid| Process.kill(:TERM, pid) rescue nil }
      EventMachine.stop_event_loop if EventMachine.reactor_running?
    end

    def start_worker
      parent = Process.pid
      pids << fork do
        # set up more fancy signals here
        map :exit, :INT, :TERM
        warn "Started worker with PID #{Process.pid}"

        EventMachine.run do
          @after_fork.each(&:call)
          c = EventMachine.watch(listener, Acceptor, self)
          c.notify_readable = true
        end
      end
    end

    private

    def warn(msg)
      super ">> #{msg}"
    end

    def map(method, *sigs)
      sigs.each { |s| trap(s) { send(method) }}
    end

    def set_defaults
      set_default :workers, cpu_count*2

      if socket
        set_default :host, Socket.gethostname
        set_default :port, 80
      else
        set_default :host, '0.0.0.0'
        set_default :port, 8080
      end
    end

    def parse_args(args)
      args.each do |arg|
        case arg
        when Hash             then arg.each { |k,v| set k, v }
        when /^\d+$/, Integer then set :port,   arg
        when /\//             then set :socket, arg
        when String           then set :host,   arg
        else                       set :app,    arg
        end
      end
    end

    def set_default(option, value)
      set(option, value) if send(option).nil?
    end

    def set(option, value)
      setter = "#{option.to_s.downcase}="
      raise ArgumentError, "unkown option #{option}" unless respond_to? setter
      send(setter, value)
    end
  end
end
