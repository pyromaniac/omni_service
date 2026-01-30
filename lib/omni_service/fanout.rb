# frozen_string_literal: true

# Executes all components with shared input params, collecting errors from all.
# Context merges from all components; params are accumulated from each component call.
#
# @example Validate multiple fields, collect all errors with shared input
#   fanout(
#     validate_title,    # => Failure([{ path: [:title], code: :blank }])
#     validate_body,     # => Failure([{ path: [:body], code: :too_short }])
#     validate_author    # => Success(...)
#   )
#   # => Result with all errors collected
#
class OmniService::Fanout
  extend Dry::Initializer
  include Dry::Equalizer(:components)
  include OmniService::Inspect.new(:components)
  include OmniService::Strict

  param :components, OmniService::Types::Array.of(OmniService::Types::Interface(:call)).constrained(min_size: 1)

  def initialize(*args, **)
    super(args.flatten(1), **)
  end

  def call(*params, **context)
    component_wrappers.inject(OmniService::Result.build(self, context:)) do |result, component|
      break result if result.shortcut?

      component_params = params[...component.signature.first]
      component_result = component.call(*component_params, **result.context)
      result.merge(component_result, params: result.params + component_result.params)
    end
  end

  def signature
    @signature ||= begin
      param_counts = component_wrappers.map { |component| component.signature.first }
      [param_counts.compact.max, true]
    end
  end

  private

  def component_wrappers
    @component_wrappers ||= OmniService::Component.wrap(components)
  end
end
