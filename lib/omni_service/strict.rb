# frozen_string_literal: true

# Provides call! method that raises OperationFailed on failure.
# Included in all framework components.
#
# @example Raising on failure
#   operation.call!(params)  # => raises OperationFailed if result.failure?
#
# @example Rescuing
#   begin
#     operation.call!(params)
#   rescue OmniService::OperationFailed => e
#     e.operation_result.errors  # => [#<Error ...>]
#   end
#
module OmniService::Strict
  def call!(*params, **context)
    result = call(*params, **context)
    raise OmniService::OperationFailed, result if result.failure?

    result
  end
end
