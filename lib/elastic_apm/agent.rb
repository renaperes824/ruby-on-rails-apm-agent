# frozen_string_literal: true

module ElasticAPM
  # @api private
  class Agent
    KEY = :__elastic_transaction_key
    LOCK = Mutex.new

    # @api private
    class TransactionInfo
      def current
        Thread.current[KEY]
      end

      def current=(transaction)
        Thread.current[KEY] = transaction
      end
    end

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

    def self.started?
      !!@instance
    end

    def initialize(config)
      @config = config

      @transaction_info = TransactionInfo.new

      @queue = Queue.new
      @pending_transactions = []
    end

    attr_reader :pending_transactions

    def start
      boot_worker

      self
    end

    def stop
      kill_worker

      self
    end

    at_exit do
      stop
    end

    # instrumentation

    def current_transaction
      @transaction_info.current
    end

    def current_transaction=(transaction)
      @transaction_info.current = transaction
    end

    # rubocop:disable Metrics/MethodLength
    def transaction(*args)
      if (transaction = current_transaction)
        yield transaction if block_given?
        return transaction
      end

      transaction = Transaction.new self, *args

      self.current_transaction = transaction
      return transaction unless block_given?

      begin
        yield transaction
      ensure
        self.current_transaction = nil
        transaction.done
      end

      transaction
    end
    # rubocop:enable Metrics/MethodLength

    def trace(*args, &block)
      transaction.trace(*args, &block)
    end

    # reporting

    def submit_transaction(transaction)
      @pending_transactions << transaction
    end

    private

    def boot_worker
      @worker_thread = Thread.new do
        Worker.new(@config, @queue).run_forever
      end
    end

    def kill_worker
      @queue << Worker::StopMessage.new

      unless @worker_thread.join(5) # 5 secs
        raise 'Failed to wait for worker, not all messages sent'
      end

      @worker_thread = nil
    end
  end
end
