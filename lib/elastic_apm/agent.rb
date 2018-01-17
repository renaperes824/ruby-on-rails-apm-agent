# frozen_string_literal: true

require 'elastic_apm/naively_hashable'
require 'elastic_apm/context_builder'
require 'elastic_apm/error_builder'
require 'elastic_apm/error'
require 'elastic_apm/http'
require 'elastic_apm/injectors'
require 'elastic_apm/serializers'
require 'elastic_apm/worker'

module ElasticAPM
  # rubocop:disable Metrics/ClassLength
  # @api private
  class Agent
    include Log

    LOCK = Mutex.new

    # life cycle

    def self.instance # rubocop:disable Style/TrivialAccessors
      @instance
    end

    def self.start(config)
      return @instance if @instance

      LOCK.synchronize do
        return @instance if @instance
        @instance = new(config).start
      end
    end

    def self.stop
      LOCK.synchronize do
        return unless @instance

        @instance.stop
        @instance = nil
      end
    end

    def self.running?
      !!@instance
    end

    # rubocop:disable Metrics/MethodLength
    def initialize(config)
      config = Config.new(config) if config.is_a?(Hash)

      @config = config

      @http = Http.new(config)
      @queue = Queue.new

      @instrumenter = Instrumenter.new(config, self)
      @context_builder = ContextBuilder.new(config)
      @error_builder = ErrorBuilder.new(config)

      @serializers = Struct.new(:transactions, :errors).new(
        Serializers::Transactions.new(config),
        Serializers::Errors.new(config)
      )
    end
    # rubocop:enable Metrics/MethodLength

    attr_reader :config, :queue, :instrumenter, :context_builder, :http

    def start
      debug 'Starting agent reporting to %s', config.server_url

      @instrumenter.start

      boot_worker

      config.enabled_injectors.each do |lib|
        require "elastic_apm/injectors/#{lib}"
      end

      self
    end

    def stop
      debug 'Stopping agent'

      @instrumenter.stop

      kill_worker

      self
    end

    at_exit do
      stop
    end

    def enqueue_transactions(transactions)
      data = @serializers.transactions.build_all(transactions)
      @queue << Worker::Request.new('/v1/transactions', data)
    end

    def enqueue_errors(errors)
      data = @serializers.errors.build_all(errors)
      @queue << Worker::Request.new('/v1/errors', data)
      errors
    end

    # instrumentation

    def current_transaction
      instrumenter.current_transaction
    end

    def transaction(*args, &block)
      instrumenter.transaction(*args, &block)
    end

    def span(*args, &block)
      instrumenter.span(*args, &block)
    end

    def build_context(rack_env)
      @context_builder.build(rack_env)
    end

    # errors

    def report(exception, handled: true)
      error = @error_builder.build_exception(
        exception,
        handled: handled
      )
      enqueue_errors error
    end

    def report_message(message, backtrace: nil, **attrs)
      error = @error_builder.build_log(
        message,
        backtrace: backtrace,
        **attrs
      )
      enqueue_errors error
    end

    # context

    def set_tag(*args)
      instrumenter.set_tag(*args)
    end

    def set_custom_context(*args)
      instrumenter.set_custom_context(*args)
    end

    def set_user(*args)
      instrumenter.set_user(*args)
    end

    def add_filter(key, callback)
      @http.filters.add(key, callback)
    end

    def inspect
      '<ElasticAPM::Agent>'
    end

    private

    def boot_worker
      debug 'Booting worker in thread'

      @worker_thread = Thread.new do
        Worker.new(@config, @queue, @http).run_forever
      end
    end

    def kill_worker
      @queue << Worker::StopMessage.new

      unless @worker_thread.join(5) # 5 secs
        raise 'Failed to wait for worker, not all messages sent'
      end

      @worker_thread = nil

      debug 'Killed worker'
    end
  end
  # rubocop:enable Metrics/ClassLength
end
