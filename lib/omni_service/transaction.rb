# frozen_string_literal: true

# Wraps component execution in a database transaction with callback support.
# Rolls back on failure; executes on_success callbacks after commit, on_failure after rollback.
#
# Callbacks run asynchronously by default (configurable via OmniService.with_sync_callbacks).
# Async callback execution uses OmniService::CallbackExecutor (global fixed-size pool).
# on_success callbacks receive the same params and context as the main component.
# on_failure callbacks are backward-compatible:
# - legacy single-argument callbacks receive only the failed Result
# - multi-argument callbacks receive original params, then failed Result, and context
#
# @example Post creation with notifications
#   transaction(
#     chain(validate_params, create_post),
#     on_success: [send_notifications, update_feed],
#     on_failure: [log_failure, alert_admin]
#   )
#
# @example Nested transactions
#   transaction(
#     chain(
#       create_post,
#       transaction(create_comments, on_success: [notify_commenters])
#     ),
#     on_success: [notify_author]
#   )
#
class OmniService::Transaction
  extend Dry::Initializer
  include Dry::Equalizer(:component, :on_success, :on_failure)
  include OmniService::Inspect.new(:component, :on_success, :on_failure)
  include OmniService::Strict

  # Internal exception to trigger transaction rollback on component failure.
  class Halt < StandardError
    attr_reader :result

    def initialize(result)
      @result = result
      super
    end
  end

  param :component, OmniService::Types::Interface(:call)
  option :on_success, OmniService::Types::Coercible::Array.of(OmniService::Types::Interface(:call)),
    default: proc { [] }
  option :on_failure, OmniService::Types::Coercible::Array.of(OmniService::Types::Interface(:call)),
    default: proc { [] }

  def call(*params, **context)
    result = call_transaction(*params, **context).merge(operation: self)

    return result if result.success?

    on_failure_results = on_failure_callbacks.map { |callback| call_on_failure_callback(callback, result) }
    result.merge(on_failure: result.on_failure + on_failure_results)
  end

  def signature
    @signature ||= [component_wrapper.signature.first, true]
  end

  private

  def call_transaction(*params, **context)
    transaction_result = ActiveRecord::Base.transaction(requires_new: true) do |transaction|
      result = component_wrapper.call(*params, **context)

      return result if result.shortcut?
      raise Halt, result if result.failure?

      handle_on_success(transaction, result)
    end

    resolve_callback_promises(transaction_result)
  rescue Halt => e
    e.result
  end

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end

  def on_success_callbacks
    @on_success_callbacks ||= OmniService::Component.wrap(on_success)
  end

  def on_failure_callbacks
    @on_failure_callbacks ||= OmniService::Component.wrap(on_failure)
  end

  def call_on_failure_callback(callback, result)
    # Preserve existing behavior for strictly single-argument callbacks.
    callback.signature == [1, false] ? callback.call(result) : callback.call(*result.params, result, **result.context)
  end

  def on_success_promises(result)
    captured_sync = OmniService.sync_callbacks?
    executor = captured_sync ? :immediate : OmniService::CallbackExecutor.executor

    on_success_callbacks.map do |callback|
      promise = Concurrent::Promises
        .delay_on(executor, callback, result, captured_sync) do |on_success_callback, operation_result, sync_value|
          OmniService.with_sync_callbacks(sync_value) do
            on_success_callback.call(*operation_result.params, **operation_result.context)
          end
        end

      # In async mode, escape promise exception capture so error tracking services can catch it via thread reporting.
      promise = promise.on_rejection { |error| Thread.new { raise error } } unless captured_sync
      promise
    end
  end

  def handle_on_success(transaction, result)
    on_success_promises = on_success_promises(result)

    if OmniService.sync_callbacks?
      transaction.after_commit { Concurrent::Promises.zip(*on_success_promises).wait }
    else
      transaction.after_commit { on_success_promises.each(&:touch) }
    end

    result.merge(on_success: result.on_success + on_success_promises)
  end

  def resolve_callback_promises(result)
    result.merge(on_success: result.on_success.map do |callback_result|
      next callback_result unless callback_result.is_a?(Concurrent::Promises::Future)

      OmniService.sync_callbacks? ? callback_result.value! : callback_result
    end)
  end
end
