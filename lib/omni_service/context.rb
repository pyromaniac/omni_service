# frozen_string_literal: true

# Validates caller-provided context values against type specifications.
# Use for values passed at call time (current_user, request), not fetched entities.
# Raises Dry::Types::CoercionError on type mismatches (not validation errors).
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
  include Dry::Monads[:result]

  param :schema, OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Interface(:call))

  def call(*params, **context)
    validated = schema.to_h { |key, type| [key, type.call(context[key])] }
    OmniService::Result.build(self, params:, context: context.merge(validated))
  end

  def signature
    [-1, true]
  end
end
