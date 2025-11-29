# frozen_string_literal: true

# Scopes component execution under a namespace key.
#
# Behavior:
# - Extracts params from params[namespace] (disable with shared_params: true)
# - Merges context[namespace] into component context with priority
# - Wraps returned context under namespace key
# - Prefixes error paths with namespace
#
# @example Nested author creation
#   # params: { title: 'Hello', author: { name: 'John', email: 'j@test.com' } }
#   namespace(:author, create_author)
#   # Inner receives: { name: 'John', email: 'j@test.com' }
#   # Result context: { author: { author: <Author> } }
#   # Error paths: [:author, :email] instead of [:email]
#
# @example Shared params for multiple processors
#   parallel(
#     namespace(:cache, warm_cache, shared_params: true),
#     namespace(:search, index_search, shared_params: true)
#   )
#   # Both receive full params; results namespaced separately
#
# @example Sequential namespace accumulation
#   sequence(
#     namespace(:author, validate_author),  # => { author: { validated: true } }
#     namespace(:author, create_author)     # => { author: { validated: true, author: <Author> } }
#   )
#
class OmniService::Namespace
  extend Dry::Initializer
  include Dry::Monads[:result]
  include Dry::Equalizer(:namespace, :component, :shared_params)
  include OmniService::Inspect.new(:namespace, :component, :shared_params)
  include OmniService::Strict

  param :namespace, OmniService::Types::Symbol
  param :component, OmniService::Types::Interface(:call)
  option :shared_params, OmniService::Types::Bool, default: -> { false }

  delegate :signature, to: :component_wrapper

  def call(*params, **context)
    inner_params = prepare_params(params)
    inner_context = prepare_context(context)
    inner_result = component_wrapper.call(*inner_params, **inner_context)

    transform_result(inner_result, params:, context:, inner_context_keys: inner_context.keys)
  end

  private

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end

  def transform_result(inner_result, params:, context:, inner_context_keys:)
    merged_context = build_merged_context(inner_result, context:, inner_context_keys:)

    if inner_result.success?
      inner_result.merge(params:, context: merged_context)
    else
      inner_result.merge(params:, context: merged_context, errors: prefix_errors(inner_result.errors))
    end
  end

  def build_merged_context(inner_result, context:, inner_context_keys:)
    returned_keys = inner_result.context.keys - inner_context_keys
    inner_returned_context = inner_result.context.slice(*returned_keys)

    existing_namespaced = context[namespace].is_a?(Hash) ? context[namespace] : {}
    new_namespaced = existing_namespaced.merge(inner_returned_context)

    context.except(namespace).merge(wrap_context(new_namespaced))
  end

  def prepare_params(params)
    return params if shared_params || params.empty?

    params_count = component_wrapper.signature[0]
    return params if params_count.zero?

    params.each_with_index.map { |param, index| extract_namespaced_param(param, index, params_count) }
  end

  def extract_namespaced_param(param, index, params_count)
    return param unless index < params_count && param.key?(namespace)

    param[namespace] || {}
  end

  def prepare_context(context)
    namespaced = context[namespace]
    base = context.except(namespace)

    namespaced.is_a?(Hash) ? base.merge(namespaced) : base
  end

  def wrap_context(inner_context)
    return {} if inner_context.empty?

    { namespace => inner_context }
  end

  def prefix_errors(errors)
    errors.map do |error|
      error.new(path: [namespace, *error.path])
    end
  end
end
