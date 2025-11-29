# frozen_string_literal: true

# Executes all components, collecting errors from all instead of short-circuiting.
# Useful for validation where you want to report all issues at once.
# Context merges from all components; params can be distributed or packed.
#
# @example Validate multiple fields, collect all errors
#   parallel(
#     validate_title,    # => Failure([{ path: [:title], code: :blank }])
#     validate_body,     # => Failure([{ path: [:body], code: :too_short }])
#     validate_author    # => Success(...)
#   )
#   # => Result with all errors collected
#
# @example Pack params from multiple sources into single hash
#   parallel(
#     parse_post_params,     # => Success({ title: 'Hi' }, ...)
#     parse_metadata_params, # => Success({ tags: [...] }, ...)
#     pack_params: true
#   )
#   # => Result(params: [{ title: 'Hi', tags: [...] }])
#
class OmniService::Parallel
  extend Dry::Initializer
  include Dry::Equalizer(:components)
  include OmniService::Inspect.new(:components)
  include OmniService::Strict

  param :components, OmniService::Types::Array.of(OmniService::Types::Interface(:call))
  option :pack_params, OmniService::Types::Bool, default: proc { false }

  def initialize(*args, **)
    super(args.flatten(1), **)
  end

  def call(*params, **context) # rubocop:disable Metrics/AbcSize
    leftovers, result = component_wrappers
      .inject([params, OmniService::Result.build(self, context:)]) do |(params_left, result), component|
        break [params_left, result] if result.shortcut?

        component_params = params_left[...component.signature.first]
        component_result = component.call(*component_params, **result.context)
        result_params = if pack_params
          [(result.params.first || {}).merge(component_result.params.first)]
        else
          result.params + component_result.params
        end

        [
          params.one? ? params : params_left[component_params.size..],
          result.merge(component_result, params: result_params)
        ]
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
end
