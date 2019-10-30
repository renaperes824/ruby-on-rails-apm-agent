# frozen_string_literal: true

require 'elastic_apm/transport/connection/proxy_pipe'

module ElasticAPM
  module Transport
    class Connection
      # @api private
      class Http
        include Logging

        def initialize(config, headers: nil)
          @config = config
          @headers = headers || Headers.new(config)
          @client = build_client
        end

        def open(url)
          @closed = Concurrent::AtomicBoolean.new
          @rd, @wr = ProxyPipe.pipe(compress: @config.http_compression?)
          @request = open_request_in_thread(url)
        end

        def self.open(config, url)
          new(config).tap do |http|
            http.open(url)
          end
        end

        def post(url, body: nil, headers: nil)
          request(:post, url, body: body, headers: headers)
        end

        def get(url, headers: nil)
          request(:get, url, headers: headers)
        end

        def request(method, url, body: nil, headers: nil)
          @client.send(
            method,
            url,
            body: body,
            headers: (headers ? @headers.merge(headers) : @headers).to_h,
            ssl_context: @config.ssl_context
          ).flush
        end

        def write(str)
          @wr.write(str)
          @wr.bytes_sent
        end

        def close(reason)
          return if closed?

          debug '%s: Closing request with reason %s', thread_str, reason
          @closed.make_true

          @wr&.close(reason)
          return if @request.nil? || @request&.join(5)

          error(
            '%s: APM Server not responding in time, terminating request',
            thread_str
          )
          @request.kill
        end

        def closed?
          @closed.true?
        end

        def inspect
          format(
            '%s closed: %s>',
            super.split.first,
            closed?
          )
        end

        private

        def thread_str
          format('[THREAD:%s]', Thread.current.object_id)
        end

        # rubocop:disable Metrics/MethodLength
        def open_request_in_thread(url)
          debug '%s: Opening new request', thread_str
          Thread.new do
            begin
              resp = post(url, body: @rd, headers: @headers.chunked.to_h)

              if resp&.status == 202
                debug 'APM Server responded with status 202'
              elsif resp
                error "APM Server responded with an error:\n%p", resp.body.to_s
              end
            rescue Exception => e
              error(
                "Couldn't establish connection to APM Server:\n%p", e.inspect
              )
            end
          end
        end
        # rubocop:enable Metrics/MethodLength

        def build_client
          client = HTTP.headers(@headers)
          return client unless @config.proxy_address && @config.proxy_port

          client.via(
            @config.proxy_address,
            @config.proxy_port,
            @config.proxy_username,
            @config.proxy_password,
            @config.proxy_headers
          )
        end
      end
    end
  end
end
