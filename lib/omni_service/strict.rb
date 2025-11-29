# frozen_string_literal: true

module OmniService
  # Exception raised by call! when operation fails.
  # Contains the full operation result for inspection.
  class OperationFailed < StandardError
    attr_reader :operation_result

    def initialize(operation_result)
      @operation_result = operation_result
      super(operation_result.errors.pretty_inspect)
    end
  end

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
  module Strict
    def call!(*params, **context)
      result = call(*params, **context)
      raise OmniService::OperationFailed, result if result.failure?

      result
    end
  end
end
