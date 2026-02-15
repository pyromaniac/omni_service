# frozen_string_literal: true

# Instance-level utility methods included via OmniService::Convenience.
#
# @example Converting external failures to OmniService errors
#   def call(params, **)
#     result = external_service.validate(params)
#     yield process_errors(result, path_prefix: [:external])
#     # Failure from external becomes: [{ path: [:external, :field], code: :invalid }]
#   end
#
# @example Processing an array of errors directly
#   process_errors([{ code: :invalid, path: [:field] }], path_prefix: [:external])
#   # => Failure([#<OmniService::Error code=:invalid path=[:external, :field]>])
#
module OmniService::Helpers
  def process_errors(result_or_errors, path_prefix: [])
    return result_or_errors if result_or_errors.respond_to?(:success?) && result_or_errors.success?

    failures = case result_or_errors
    in OmniService::Result
      result_or_errors.errors
    in Dry::Monads::Failure[*failures]
      failures
    in Array
      result_or_errors
    else
      raise ArgumentError, "Unsupported result payload `#{result_or_errors.inspect}`"
    end

    Failure(OmniService::Error.process(self, failures).map do |error|
      error.new(path: [*path_prefix, *error.path])
    end)
  end
end
