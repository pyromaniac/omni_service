# frozen_string_literal: true

# Iterates component over arrays in namespaced params and context.
# Collects results from all iterations; errors include array index in path.
#
# Extracts arrays from params[namespace] and context[namespace].
# Iteration count is max of array lengths. Missing indices get empty values.
# Error paths are prefixed with [namespace, index, ...].
#
# @example Create multiple comments for a post
#   # params: { comments: [{ body: 'First' }, { body: '' }] }
#   # context: { comments: [{ author: user1 }, { author: user2 }] }
#   collection(create_comment, namespace: :comments)
#   # => Result(
#   #      context: { comments: [{ comment: <Comment> }, { comment: nil }] },
#   #      errors: [{ path: [:comments, 1, :body], code: :blank }]
#   #    )
#
# @example Validate nested items
#   collection(validate_line_item, namespace: :line_items)
#   # Errors: [:line_items, 0, :quantity], [:line_items, 2, :price]
#
class OmniService::Collection
  extend Dry::Initializer
  include Dry::Equalizer(:component)
  include OmniService::Inspect.new(:component)
  include OmniService::Strict

  param :component, OmniService::Types::Interface(:call)
  option :namespace, OmniService::Types::Symbol

  def call(*params, **context)
    params_collection = params.map { |param| param.symbolize_keys.fetch(namespace, default_collection(context)) }
    context_collection = context.fetch(namespace, default_collection(context))
    keys = extract_keys(params_collection, context_collection)

    results = keys.to_h do |key|
      [key, call_wrapper(params_collection, context_collection, context, key)]
    end

    compose_result(results, context)
  end

  def signature
    @signature ||= [component_wrapper.signature.first, true]
  end

  private

  def default_collection(context)
    context.fetch(namespace, []).is_a?(Hash) ? {} : []
  end

  def extract_keys(params_collection, context_collection)
    all_collections = [*params_collection, context_collection]
    if all_collections.any?(Hash)
      all_collections.select { |c| c.is_a?(Hash) }.flat_map(&:keys).uniq
    else
      (0...all_collections.map(&:size).max).to_a
    end
  end

  def call_wrapper(params_collection, context_collection, context, key)
    component_wrapper.call(
      *params_collection.map { |c| c[key] },
      **context.except(namespace),
      **(context_collection[key] || {})
    )
  end

  def compose_result(results, context)
    OmniService::Result.build(
      self,
      params: compose_params(results),
      context: context.merge(namespace => wrap_collection(results.keys, results.values.map(&:context))),
      errors: compose_errors(results),
      on_success: results.values.flat_map(&:on_success),
      on_failure: results.values.flat_map(&:on_failure)
    )
  end

  def compose_params(results)
    results.values.map(&:params).transpose.map { |values| { namespace => wrap_collection(results.keys, values) } }
  end

  def wrap_collection(keys, values)
    keys.first.is_a?(Integer) ? values : keys.zip(values).to_h
  end

  def compose_errors(results)
    results.flat_map do |key, result|
      result.errors.map { |error| error.new(path: [namespace, key, *error.path]) }
    end
  end

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end
end
