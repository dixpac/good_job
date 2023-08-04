module GoodJob
  class HttpServer
    def initialize
      @server = nil
      @running = Concurrent::AtomicBoolean.new(false)
    end

    def run(app, port)
      @running.make_true
      @server = TCPServer.new('0.0.0.0', port)

      Thread.new do
        while @running.true?
          client = @server.accept
          begin
            request = client.gets
            status, headers, body = app.call(parse_request(request))
            respond(client, status, headers, body)
          rescue => e
            respond(client, 500, { "Content-Type" => "text/plain" }, ["Internal Server Error"])
          ensure
            client.close
          end
        end
      end
    end

    def stop
      @running.make_false
      @server&.close
    end

    def running?
      @running.true?
    end

    private

    def parse_request(request)
      method, full_path = request.split(' ')
      path, query = full_path.split('?')
      { 'REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => query || '' }
    end

    def respond(client, status, headers, body)
      client.write "HTTP/1.1 #{status}\r\n"
      headers.each { |key, value| client.write "#{key}: #{value}\r\n" }
      client.write "\r\n"
      body.each { |part| client.write part.to_s }
    end
  end
end
