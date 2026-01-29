# frozen_string_literal: true

# Executes components with distributed params, short-circuiting on first failure or shortcut.
# Context accumulates across components; params are accumulated from executed components.
#
# @example Distribute params across components, fail fast
#   split(
#     parse_title,   # => Failure here stops
#     parse_body,    # Not executed if previous failed
#     parse_author
#   )
#
class OmniService::Split
  extend Dry::Initializer
  include Dry::Equalizer(:components)
  include OmniService::Inspect.new(:components)
  include OmniService::Strict

  param :components, OmniService::Types::Array.of(OmniService::Types::Interface(:call)).constrained(min_size: 1)

  def initialize(*args, **)
    super(args.flatten(1), **)
  end

  def call(*params, **context)
    leftovers, result = component_wrappers
      .inject([params, OmniService::Result.build(self, context:)]) do |(params_left, result), component|
        break [params_left, result] if result.failure? || result.shortcut?

        call_component(params, params_left, result, component)
      end

    params.one? ? result : result.merge(params: result.params + leftovers)
  end

  def signature
    @signature ||= begin
      param_counts = component_wrappers.map { |component| component.signature.first }
      [param_counts.all? ? param_counts.sum : nil, true]
    end
  end

  private

  def component_wrappers
    @component_wrappers ||= OmniService::Component.wrap(components)
  end

  def call_component(params, params_left, result, component)
    component_params = params_left[...component.signature.first]
    component_result = component.call(*component_params, **result.context)
    result_params = result.params + component_result.params

    [
      params.one? ? params : params_left[component_params.size..],
      result.merge(component_result, params: result_params)
    ]
  end
end
