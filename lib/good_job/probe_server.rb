# frozen_string_literal: true

module GoodJob
  class ProbeServer
    def self.task_observer(time, output, thread_error) # rubocop:disable Lint/UnusedMethodArgument
      return if thread_error.is_a? Concurrent::CancelledOperationError

      GoodJob._on_thread_error(thread_error) if thread_error
    end

    def initialize(port:)
      @port = port
      @running = Concurrent::AtomicBoolean.new(true)
    end

    def start
      @server  = TCPServer.new(@port)

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
      # @future&.value # wait for Future to exit
    end

    def call(env)
      case Rack::Request.new(env).path
      when '/', '/status'
        [200, {}, ["OK"]]
      when '/status/started'
        started = GoodJob::Scheduler.instances.any? && GoodJob::Scheduler.instances.all?(&:running?)
        started ? [200, {}, ["Started"]] : [503, {}, ["Not started"]]
      when '/status/connected'
        connected = GoodJob::Scheduler.instances.any? && GoodJob::Scheduler.instances.all?(&:running?) &&
                    GoodJob::Notifier.instances.any? && GoodJob::Notifier.instances.all?(&:listening?)
        connected ? [200, {}, ["Connected"]] : [503, {}, ["Not connected"]]
      else
        [404, {}, ["Not found"]]
      end
    end

    private

    def parse_request(request)
      method, full_path = request.split(' ')
      path, query = full_path.split('?')

      call({ 'REQUEST_METHOD' => method, 'PATH_INFO' => path, 'QUERY_STRING' => query || '' })
    end

    def respond(client, status, headers, body)
      client.write "HTTP/1.1 #{status}\r\n"
      headers.each { |key, value| client.write "#{key}: #{value}\r\n" }
      client.write "\r\n"
      body.each { |part| client.write part.to_s }
    end
  end
end
