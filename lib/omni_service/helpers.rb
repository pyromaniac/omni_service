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
module OmniService::Helpers
  def process_errors(result, path_prefix: [])
    return result if result.success?

    Failure(OmniService::Error.process(self, result.failure).map do |error|
      error.new(path: [*path_prefix, *error.path])
    end)
  end
end
