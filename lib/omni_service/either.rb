# frozen_string_literal: true

# Tries components in order, returning the first success.
# Useful for fallback/recovery patterns where you want to try alternatives.
#
# @example Cache with database fallback
#   either(
#     cache_lookup,      # try cache first
#     database_lookup,   # fallback to database
#     compute_fresh      # last resort: compute
#   )
#
# @example With transaction isolation for rollback on failure
#   transaction(
#     either(
#       transaction(risky_operation),  # if fails, rolled back
#       safe_fallback                  # runs clean
#     )
#   )
#
class OmniService::Either
  extend Dry::Initializer
  include Dry::Equalizer(:components)
  include OmniService::Inspect.new(:components)
  include OmniService::Strict

  param :components, OmniService::Types::Array.of(OmniService::Types::Interface(:call)).constrained(min_size: 1)

  def initialize(*args, **)
    super(args.flatten(1), **)
  end

  def call(*params, **context)
    last_result = nil

    component_wrappers.each do |component|
      result = component.call(*params, **context)
      return result.merge(operation: self) if result.success?

      last_result = result
    end

    last_result.merge(operation: self)
  end

  def signature
    @signature ||= compute_signature
  end

  private

  def component_wrappers
    @component_wrappers ||= OmniService::Component.wrap(components)
  end

  def compute_signature
    signatures = component_wrappers.map { |component| component.signature.first }
    return [nil, true] if signatures.include?(nil)

    [signatures.max, true]
  end
end
