module GoodJob
  class HttpServer
    def initialize
      @server = nil
      @running = Concurrent::AtomicBoolean.new(false)
    end

    def run(app, port, logger)
      @running.make_true
      begin
        @server = TCPServer.new('0.0.0.0', port)
      rescue StandardError => e
        logger.error "Server encountered an error: #{e}"
        @running.make_false
        return
      end

      begin
        while @running.true?
          ready_sockets, _, _ = IO.select([@server], nil, nil, 0.1)
          next unless ready_sockets

          client = @server.accept_nonblock(exception: false)
          request = client.gets
          status, headers, body = app.call(parse_request(request))
          respond(client, status, headers, body)
          client.close
        end
      rescue IO::WaitReadable, Errno::EINTR
        retry
      rescue Errno::EBADF
        # Do nothing
      rescue StandardError => e
        logger.error "Server encountered an error: #{e}"
      ensure
        @server.close if @server
        @running.make_false
      end
    end

    def stop
      @running.make_false
      @server&.close
      @server = nil
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
