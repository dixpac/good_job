require 'socket'
require 'rack'

module GoodJob
  class HttpServer
    def self.run(app, options = {})
      @instance = new(app, options)
      @instance.start
      @instance
    end

    def self.stop
      @instance&.stop
    end

    def initialize(app, options = {})
      port = options.fetch(:port, 7001)
      @server = TCPServer.new(port)
      @app = app
      @running = Concurrent::AtomicBoolean.new(true)
    end

    def start
      Thread.new do
        while @running.value
          client = @server.accept
          request = client.gets
          method, full_path = request.split(' ')
          path, query = full_path.split('?')

          status, headers, body = @app.call({
                                            'REQUEST_METHOD' => method,
                                            'PATH_INFO' => path,
                                            'QUERY_STRING' => query || ''
                                          })

          client.puts "HTTP/1.1 #{status}\r"
          headers.each { |key, value| client.puts "#{key}: #{value}\r" }
          client.puts "\r"
          body.each { |part| client.puts part }
          client.close
        end
        @server.close
      end
    end

    def stop
      @running.value = false
    end
  end
end

Rack::Handler.register('httpserver', GoodJob::HttpServer)
