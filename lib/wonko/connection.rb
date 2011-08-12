require 'wonko'

require 'rack'
require 'stringio'
require 'eventmachine'

module Wonko
  class Connection < EventMachine::Connection
    include Utils

    def initialize(server)
      @parser    = HTTP::RequestParser.new(self)
      @app       = server.app
      @proto_env = {
        "rack.url_scheme"   => %w[yes on 1].include?(ENV["HTTPS"]) ? "https" : "http", 
        "SERVER_NAME"       => server.host,
        "SERVER_PORT"       => server.port,
        "rack.version"      => Rack::VERSION,
        "rack.multithread"  => true,
        "rack.multiprocess" => @multi,
        "rack.run_once"     => false,
        "rack.errors"       => $stdout
      }
      super()
    end

    def post_init
      @parser.reset!
      @keep_alive   = false
      @input        = StringIO.new(binary)
      @async_close  = EventMachine::DefaultDeferrable.new
      @env          = {
        "SCRIPT_NAME"     => binary, "rack.input"  => @input,
        "async.callback"  => self,   "async.close" => @async_close
      }
      @env.merge! @proto_env
    end

    def receive_data(data)
      @parser << data
    end

    def on_headers_complete(headers)
      @env["REQUEST_METHOD"] = binary(@parser.http_method)
      @env["PATH_INFO"]      = binary(@parser.request_path)
      @env["QUERY_STRING"]   = binary(@parser.query_string.to_s)

      headers.each do |key, value|
        if key == 'Content-Length'
          next unless value.to_s =~ /^\d+$/
          key = 'CONTENT_LENGTH'
        else
          key = "HTTP_" << key.split('-').map { |e| e.upcase }.join('_')
        end

        @env[key] = binary(value)
      end
    end

    def on_message_complete
      defer { catch(:async) { call @app.call(@env) } }
    end

    def on_body(chunk)
      @input << binary(chunk)
    end

    def call(response)
      return if response.first == -1

      status, headers, body = response
      meta = "HTTP/1.#{@parser.http_minor} #{status} #{HTTP_STATUS_CODES[status]}\r\n"
      @has_content_length, @connection_mode = false, nil

      headers.each do |key, values|
        next if key == 'Connection'
        @keep_alive = true if key == 'Content-Length' and @parser.keep_alive?
        values.split("\n").each { |value| meta << "#{key}: #{value}\r\n" }
      end

      if @keep_alive and @parser.http_minor == 0
        meta << "Connection: Keep-Alive\r\n"
      end

      meta << "\r\n"
      schedule { send_data meta }

      defer do
        body.each { |s| schedule { send_data s } }
        if body.respond_to? :callback and body.respond_to? :errback
          body.callback { close_request(body) }
          body.errback  { close_request(body) }
        else
          close_request(body)
        end
      end
    end

    def unbind
      @async_close.succeed
    end

    private

    def close_request(body)
      body.close if body.respond_to? :close
      EventMachine.schedule do
        @async_close.succeed
        @keep_alive ? post_init : close_connection_after_writing rescue nil
      end
    end

    def schedule
      EventMachine.schedule { yield }
    end

    def defer
      EventMachine.defer do
        begin
          yield
        rescue Exception => error
          schedule { raise error }
        end
      end
    end

    defined?(Encoding) ?
      def binary(str = '') str.force_encoding('binary') end :
      def binary(str = '') str end
  end
end
