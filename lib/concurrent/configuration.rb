require 'thread'
require 'concurrent/atomics'
require 'concurrent/errors'
require 'concurrent/at_exit'
require 'concurrent/executors'
require 'concurrent/utility/processor_count'
require 'concurrent/utility/deprecation'

module Concurrent
  extend Logging
  extend Deprecation

  # Suppresses all output when used for logging.
  NULL_LOGGER = lambda { |level, progname, message = nil, &block| }

  # @!visibility private
  GLOBAL_LOGGER = AtomicReference.new(NULL_LOGGER)
  private_constant :GLOBAL_LOGGER

  # @!visibility private
  GLOBAL_FAST_EXECUTOR = Delay.new { Concurrent.new_fast_executor(auto_terminate: true) }
  private_constant :GLOBAL_FAST_EXECUTOR

  # @!visibility private
  GLOBAL_IO_EXECUTOR = Delay.new { Concurrent.new_io_executor(auto_terminate: true) }
  private_constant :GLOBAL_IO_EXECUTOR

  # @!visibility private
  GLOBAL_TIMER_SET = Delay.new { TimerSet.new(auto_terminate: true) }
  private_constant :GLOBAL_TIMER_SET

  # @!visibility private
  GLOBAL_IMMEDIATE_EXECUTOR = ImmediateExecutor.new
  private_constant :GLOBAL_IMMEDIATE_EXECUTOR

  def self.global_logger
    GLOBAL_LOGGER.value
  end

  def self.global_logger=(value)
    GLOBAL_LOGGER.value = value
  end

  # Disables AtExit hooks including pool auto-termination hooks.
  # When disabled it will be the application
  # programmer's responsibility to ensure that the hooks
  # are shutdown properly prior to application exit
  # by calling {AtExit.run} method.
  #
  # @note this option should be needed only because of `at_exit` ordering
  #   issues which may arise when running some of the testing frameworks.
  #   E.g. Minitest's test-suite runs itself in `at_exit` callback which
  #   executes after the pools are already terminated. Then auto termination
  #   needs to be disabled and called manually after test-suite ends.
  # @note This method should *never* be called
  #   from within a gem. It should *only* be used from within the main
  #   application and even then it should be used only when necessary.
  # @see AtExit
  def self.disable_at_exit_hooks!
    AtExit.enabled = false
  end

  def self.disable_executor_auto_termination!
    deprecated_method 'disable_executor_auto_termination!', 'disable_at_exit_hooks!'
    disable_at_exit_hooks!
  end

  # @return [true,false]
  # @see .disable_executor_auto_termination!
  def self.disable_executor_auto_termination?
    deprecated_method 'disable_executor_auto_termination?', 'Concurrent::AtExit.enabled?'
    AtExit.enabled?
  end

  # terminates all pools and blocks until they are terminated
  # @see .disable_executor_auto_termination!
  def self.terminate_pools!
    deprecated_method 'terminate_pools!', 'Concurrent::AtExit.run'
    AtExit.run
  end

  # Global thread pool optimized for short, fast *operations*.
  #
  # @return [ThreadPoolExecutor] the thread pool
  def self.global_fast_executor
    GLOBAL_FAST_EXECUTOR.value
  end

  # Global thread pool optimized for long, blocking (IO) *tasks*.
  #
  # @return [ThreadPoolExecutor] the thread pool
  def self.global_io_executor
    GLOBAL_IO_EXECUTOR.value
  end

  def self.global_immediate_executor
    GLOBAL_IMMEDIATE_EXECUTOR
  end

  # Global thread pool user for global *timers*.
  #
  # @return [Concurrent::TimerSet] the thread pool
  #
  # @see Concurrent::timer
  def self.global_timer_set
    GLOBAL_TIMER_SET.value
  end

  # General access point to global executors.
  # @param [Symbol, Executor] executor_identifier symbols:
  #   - :fast - {Concurrent.global_fast_executor}
  #   - :io - {Concurrent.global_io_executor}
  #   - :immediate - {Concurrent.global_immediate_executor}
  # @return [Executor]
  def self.executor(executor_identifier)
    Executor.executor(executor_identifier)
  end

  def self.new_fast_executor(opts = {})
    FixedThreadPool.new(
        [2, Concurrent.processor_count].max,
        auto_terminate:  opts.fetch(:auto_terminate, true),
        idletime:        60, # 1 minute
        max_queue:       0, # unlimited
        fallback_policy: :abort # shouldn't matter -- 0 max queue
    )
  end

  def self.new_io_executor(opts = {})
    ThreadPoolExecutor.new(
        min_threads:     [2, Concurrent.processor_count].max,
        max_threads:     ThreadPoolExecutor::DEFAULT_MAX_POOL_SIZE,
        # max_threads:     1000,
        auto_terminate:  opts.fetch(:auto_terminate, true),
        idletime:        60, # 1 minute
        max_queue:       0, # unlimited
        fallback_policy: :abort # shouldn't matter -- 0 max queue
    )
  end

  # A gem-level configuration object.
  class Configuration
    include Deprecation

    # Create a new configuration object.
    def initialize
    end

    # if assigned to {#logger}, it will log nothing.
    # @deprecated Use Concurrent::NULL_LOGGER instead
    def no_logger
      warn '[DEPRECATED] Use Concurrent::NULL_LOGGER instead'
      deprecated_method 'Concurrent.configuration.no_logger', 'Concurrent::NULL_LOGGER'
      NULL_LOGGER
    end

    # a proc defining how to log messages, its interface has to be:
    #   lambda { |level, progname, message = nil, &block| _ }
    #
    # @deprecated Use Concurrent.global_logger instead
    def logger
      deprecated_method 'Concurrent.configuration.logger', 'Concurrent.global_logger'
      Concurrent.global_logger.value
    end

    # a proc defining how to log messages, its interface has to be:
    #   lambda { |level, progname, message = nil, &block| _ }
    #
    # @deprecated Use Concurrent.global_logger instead
    def logger=(value)
      deprecated_method 'Concurrent.configuration.logger=', 'Concurrent.global_logger='
      Concurrent.global_logger = value
    end

    # @deprecated Use Concurrent.global_io_executor instead
    def global_task_pool
      deprecated_method 'Concurrent.configuration.global_task_pool', 'Concurrent.global_io_executor'
      Concurrent.global_io_executor
    end

    # @deprecated Use Concurrent.global_fast_executor instead
    def global_operation_pool
      deprecated_method 'Concurrent.configuration.global_operation_pool', 'Concurrent.global_fast_executor'
      Concurrent.global_fast_executor
    end

    # @deprecated Use Concurrent.global_timer_set instead
    def global_timer_set
      deprecated_method 'Concurrent.configuration.global_timer_set', 'Concurrent.global_timer_set'
      Concurrent.global_timer_set
    end

    # @deprecated Replacing global thread pools is deprecated.
    #   Use the :executor constructor option instead.
    def global_task_pool=(executor)
      deprecated 'Replacing global thread pools is deprecated. Use the :executor constructor option instead.'
      GLOBAL_IO_EXECUTOR.reconfigure { executor } or
          raise ConfigurationError.new('global task pool was already set')
    end

    # @deprecated Replacing global thread pools is deprecated.
    #   Use the :executor constructor option instead.
    def global_operation_pool=(executor)
      deprecated 'Replacing global thread pools is deprecated. Use the :executor constructor option instead.'
      GLOBAL_FAST_EXECUTOR.reconfigure { executor } or
          raise ConfigurationError.new('global operation pool was already set')
    end

    # @deprecated Use Concurrent.new_io_executor instead
    def new_task_pool
      deprecated_method 'Concurrent.configuration.new_task_pool', 'Concurrent.new_io_executor'
      Concurrent.new_io_executor
    end

    # @deprecated Use Concurrent.new_fast_executor instead
    def new_operation_pool
      deprecated_method 'Concurrent.configuration.new_operation_pool', 'Concurrent.new_fast_executor'
      Concurrent.new_fast_executor
    end

    # @deprecated Use Concurrent.disable_auto_termination_of_global_executors! instead
    def auto_terminate=(value)
      deprecated_method 'Concurrent.configuration.auto_terminate=', 'Concurrent.disable_auto_termination_of_global_executors!'
      Concurrent.disable_auto_termination_of_global_executors! if !value
    end

    # @deprecated Use Concurrent.auto_terminate_global_executors? instead
    def auto_terminate
      deprecated_method 'Concurrent.configuration.auto_terminate', 'Concurrent.auto_terminate_global_executors?'
      Concurrent.auto_terminate_global_executors?
    end
  end

  # create the default configuration on load
  CONFIGURATION = AtomicReference.new(Configuration.new)
  private_constant :CONFIGURATION

  # @return [Configuration]
  def self.configuration
    CONFIGURATION.value
  end

  # Perform gem-level configuration.
  #
  # @yield the configuration commands
  # @yieldparam [Configuration] the current configuration object
  def self.configure
    yield(configuration)
  end
end
