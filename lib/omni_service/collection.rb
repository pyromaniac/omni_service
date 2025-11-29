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
    params_array = params.map { |param| param.symbolize_keys.fetch(namespace, []) }
    context_array = context.fetch(namespace, [])
    size = [*params_array.map(&:size), context_array.size].max

    results = (0...size).map do |index|
      call_wrapper(params_array, context_array, context, index)
    end

    compose_result(results, context)
  end

  def signature
    @signature ||= [component_wrapper.signature.first, true]
  end

  private

  def call_wrapper(params_array, context_array, context, index)
    component_wrapper.call(
      *params_array.pluck(index),
      **context.except(namespace),
      **(context_array[index] || {})
    )
  end

  def compose_result(results, context)
    OmniService::Result.build(
      self,
      params: results.map(&:params).transpose.map { |param| { namespace => param } },
      context: context.merge(namespace => results.map(&:context)),
      errors: compose_errors(results),
      on_success: results.flat_map(&:on_success),
      on_failure: results.flat_map(&:on_failure)
    )
  end

  def compose_errors(results)
    results.flat_map.with_index do |result, index|
      result.errors.map { |error| error.new(path: [namespace, index, *error.path]) }
    end
  end

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end
end
