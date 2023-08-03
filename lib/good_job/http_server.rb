require 'socket'

module GoodJob
  class HttpServer
    def self.run(app, options = {})
      @instance = new(app, options)
      @instance.start
      @instance
    end

    def initialize(app, options = {})
      port     = options.fetch(:port, 7001)
      @server  = TCPServer.new(port)
      @app     = app
      @running = Concurrent::AtomicBoolean.new(true)
    end

    def start
      Thread.new do
        while @running.value
          client = @server.accept
          begin
            request = client.gets

            status, headers, body = parse_request(request)
            respond(client, status, headers, body)
          rescue => e
            respond(client, 500, { "Content-Type" => "text/plain"}, ["Internal Server Error"] )
          ensure
            client.close
          end
        end
        @server.close
      end
    end

    def running?
      @running.value
    end

    def stop
      @running.value = false
    end

    def parse_request(request)
      method, full_path = request.split(' ')
      path, query = full_path.split('?')

      @app.call({ 'REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => query || '' })
    end

    def respond(client, status, headers, body)
      client.write "HTTP/1.1 #{status}\r\n"
      headers.each { |key, value| client.write "#{key}: #{value}\r\n" }
      client.write "\r\n"
      body.each { |part| client.write part.to_s }
      # client.write "\r\n"
    end
  end
end
