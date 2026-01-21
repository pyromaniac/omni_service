# frozen_string_literal: true

# Validates caller-provided context values against type specifications.
# Use for values passed at call time (current_user, request), not fetched entities.
# Only validates keys defined in schema; passes through undefined keys unchanged.
#
# @example Validate caller-provided context
#   context(
#     current_user: Types::Instance(User),
#     correlation_id: Types::String.optional,
#     logger: Types::Interface(:info, :error)
#   )
#
class OmniService::Context
  extend Dry::Initializer

  param :schema, OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Interface(:call, :try))
  option :raise_on_error, OmniService::Types::Bool, default: -> { true }

  def call(*params, **context)
    validated = validated_context(context)
    failures = failures_from(validated)

    if failures.any?
      failure_result(params, context, failures)
    else
      OmniService::Result.build(self, params:, context: context.merge(validated.transform_values(&:input)))
    end
  end

  def signature
    [0, true]
  end

  private

  def validated_context(context)
    schema.each_with_object({}) do |(key, type), result|
      validation_result = type.try(context[key])
      next if !context.key?(key) && validation_result.success?

      result[key] = validation_result
    end
  end

  def failures_from(validated)
    validated.select { |_, result| result.failure? }
  end

  def failure_result(params, context, failures)
    errors = failures.values.map { |result| OmniService::Error.build(self, message: result.error.message) }
    result = OmniService::Result.build(self, params:, errors:, context:)

    raise OmniService::OperationFailed, result if raise_on_error

    result
  end
end
