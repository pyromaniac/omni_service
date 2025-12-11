# frozen_string_literal: true

# Scopes component execution under a namespace key.
#
# Behavior:
# - Requires namespace key in params (returns :missing error if absent)
# - Extracts params from params[namespace] (disable with shared_params: true)
# - Merges context[namespace] into component context with priority
# - Wraps returned params and context under namespace key
# - Prefixes error paths with namespace
#
# Options:
# - optional: true - skips component when namespace key is missing (no error)
# - shared_params: true - passes full params (no extraction), key not required
#
# @example Nested author creation
#   # params: { title: 'Hello', author: { name: 'John', email: 'j@test.com' } }
#   namespace(:author, create_author)
#   # Inner receives: { name: 'John', email: 'j@test.com' }
#   # Result params: { author: { name: 'John', email: 'j@test.com' } }
#   # Result context: { author: { author: <Author> } }
#   # Error paths: [:author, :email] instead of [:email]
#
# @example Shared params for multiple processors
#   parallel(
#     namespace(:cache, warm_cache, shared_params: true),
#     namespace(:search, index_search, shared_params: true)
#   )
#   # Both receive full params; results namespaced separately
#   # Namespace key not required with shared_params: true
#
# @example Optional namespace (skip if key missing)
#   # params: { title: 'Hello' }  (no :author key)
#   namespace(:author, create_author, optional: true)
#   # Component not called, returns Success with unchanged params/context
#
# @example Sequential namespace accumulation
#   sequence(
#     namespace(:author, validate_author),  # => { author: { validated: true } }
#     namespace(:author, create_author)     # => { author: { validated: true, author: <Author> } }
#   )
#
class OmniService::Namespace
  extend Dry::Initializer
  extend Forwardable

  include Dry::Monads[:result]
  include Dry::Equalizer(:namespace, :component, :shared_params, :optional)
  include OmniService::Inspect.new(:namespace, :component, :shared_params, :optional)
  include OmniService::Strict

  param :namespace, OmniService::Types::Symbol
  param :component, OmniService::Types::Interface(:call)
  option :shared_params, OmniService::Types::Bool, default: -> { false }
  option :optional, OmniService::Types::Bool, default: -> { false }

  def_delegators :component_wrapper, :signature

  def call(*params, **context)
    return skip_result(params, context) if optional && !namespace_key_present?(params)
    return missing_key_result(params, context) unless shared_params || namespace_key_present?(params)

    inner_params = prepare_params(params)
    inner_context = prepare_context(context)
    inner_result = component_wrapper.call(*inner_params, **inner_context)

    transform_result(inner_result, context:, inner_context_keys: inner_context.keys)
  end

  private

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end

  def transform_result(inner_result, context:, inner_context_keys:)
    inner_result.merge(
      params: inner_result.params.map { |param| { namespace => param } },
      context: build_merged_context(inner_result, context:, inner_context_keys:),
      errors: prefix_errors(inner_result.errors)
    )
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

  def namespace_key_present?(params)
    params.any? { |param| param.is_a?(Hash) && param.key?(namespace) }
  end

  def skip_result(params, context)
    OmniService::Result.build(self, params: params, context: context)
  end

  def missing_key_result(params, context)
    OmniService::Result.build(
      self,
      params: params,
      context: context,
      errors: [OmniService::Error.build(self, code: :missing, path: [namespace])]
    )
  end
end
