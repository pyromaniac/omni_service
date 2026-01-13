# frozen_string_literal: true

require 'active_support/core_ext/hash/deep_merge'

# Scopes component execution under a namespace path.
#
# Behavior:
# - Extracts params from `from` path (defaults to namespace path)
# - Deep merges component context back under namespace path
# - Prefixes error paths with namespace
#
# Options:
# - from: path - extract params from this path (default: namespace); empty array passes full params
# - optional: true - skips component when from key is missing (no error)
#
# @example Nested author creation
#   # params: { title: 'Hello', author: { name: 'John', email: 'j@test.com' } }
#   namespace(:author, create_author)
#   # Inner receives: { name: 'John', email: 'j@test.com' }
#   # Result context: { author: { author: <Author> } }
#   # Error paths: [:author, :email] instead of [:email]
#
# @example Deep namespace
#   # params: { user: { profile: { name: 'John' } } }
#   namespace([:user, :profile], validate_profile)
#   # Inner receives: { name: 'John' }
#
# @example Full params with namespaced output
#   parallel(
#     namespace(:cache, warm_cache, from: []),
#     namespace(:search, index_search, from: [])
#   )
#   # Both receive full params; results namespaced separately
#
class OmniService::Namespace
  extend Dry::Initializer
  include Dry::Equalizer(:namespace, :component, :from, :optional)
  include OmniService::Inspect.new(:namespace, :component, :from, :optional)
  include OmniService::Strict

  param :namespace, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol)
  param :component, OmniService::Types::Interface(:call)
  option :from, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol), default: -> { namespace }
  option :optional, OmniService::Types::Bool, default: -> { false }

  def call(*params, **context)
    return skip_result(params, context) if optional && !from_key_present?(params)
    return missing_key_result(params, context) unless from.empty? || from_key_present?(params)

    base_context, namespaced_context, inner_context = prepare_contexts(context)
    inner_result = component_wrapper.call(*prepare_params(params), **inner_context)

    transform_result(inner_result, context, base_context.keys, namespaced_context)
  end

  def signature
    @signature ||= [from.empty? ? component_wrapper.signature.first : 1, true]
  end

  private

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end

  def transform_result(inner_result, original_context, base_keys, namespaced_context)
    returned_namespaced = inner_result.context.except(*base_keys)
    merged_namespaced = namespaced_context.deep_merge(returned_namespaced)

    inner_result.merge(
      params: inner_result.params.map { |param| wrap_value(param, skip_empty: false) },
      context: original_context.deep_merge(wrap_value(merged_namespaced)),
      errors: prefix_errors(inner_result.errors)
    )
  end

  def prepare_contexts(context)
    base = context.except(namespace.first)
    namespaced = context.dig(*namespace) || {}
    inner = namespaced.is_a?(Hash) ? base.merge(namespaced) : base
    [base, namespaced, inner]
  end

  def prepare_params(params)
    return params if from.empty? || params.empty?

    params_count = component_wrapper.signature[0] || params.size
    return params if params_count.zero?

    params.each_with_index.map { |param, index| extract_from_param(param, index, params_count) }
  end

  def extract_from_param(param, index, params_count)
    return param unless index < params_count && key_path_exists?(param, *from)

    param.dig(*from) || {}
  end

  def wrap_value(value, skip_empty: true)
    return {} if skip_empty && (value.nil? || (value.respond_to?(:empty?) && value.empty?))

    namespace.reverse.inject(value) { |inner, key| { key => inner } }
  end

  def prefix_errors(errors)
    errors.map { |error| error.new(path: [*namespace, *error.path]) }
  end

  def from_key_present?(params)
    from.empty? || params.any? { |param| key_path_exists?(param, *from) }
  end

  def key_path_exists?(hash, key, *rest)
    return false unless hash.is_a?(Hash) && hash.key?(key)
    return true if rest.empty?

    key_path_exists?(hash[key], *rest)
  end

  def skip_result(params, context)
    OmniService::Result.build(self, params:, context:)
  end

  def missing_key_result(params, context)
    OmniService::Result.build(
      self,
      params:,
      context:,
      errors: [OmniService::Error.build(self, code: :missing, path: from)]
    )
  end
end
