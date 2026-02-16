# frozen_string_literal: true

# Defines a thread pool for executing callbacks asynchronously.
module OmniService::CallbackExecutor
  THREADS_ENV_KEY = 'OMNI_SERVICE_CALLBACK_THREADS'
  DEFAULT_THREADS = 1
  DEFAULT_SHUTDOWN_TIMEOUT = 5
  DEFAULT_FORCE_KILL_WAIT_TIMEOUT = 1
  EXECUTOR_NAME = 'omni_service_callbacks'

  class << self
    def executor
      @executor ||= build_executor(configured_threads)
    end

    def shutdown(timeout = nil) # rubocop:disable Naming/PredicateMethod
      callback_executor = @executor
      return true unless callback_executor

      @executor = nil
      callback_executor.shutdown
      return true if callback_executor.wait_for_termination(timeout || DEFAULT_SHUTDOWN_TIMEOUT)

      callback_executor.kill
      callback_executor.wait_for_termination(DEFAULT_FORCE_KILL_WAIT_TIMEOUT)
      false
    end

    private

    def configured_threads
      env_value = ENV.fetch(THREADS_ENV_KEY, nil)
      return DEFAULT_THREADS if env_value.nil? || env_value.empty?

      coerce_threads(env_value)
    end

    def coerce_threads(value)
      threads_count = Integer(value)
      raise ArgumentError, 'callback_threads must be greater than 0' unless threads_count.positive?

      threads_count
    rescue ArgumentError, TypeError
      raise ArgumentError, 'callback_threads must be greater than 0'
    end

    def build_executor(threads_count)
      Concurrent::FixedThreadPool.new(
        threads_count,
        max_queue: 0,
        fallback_policy: :abort,
        auto_terminate: false,
        name: EXECUTOR_NAME
      )
    end
  end
end

OmniService::CallbackExecutor.executor

at_exit do
  OmniService::CallbackExecutor.shutdown
end
