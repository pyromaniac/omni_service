# frozen_string_literal: true

# Wraps any callable (lambda, proc, object responding to #call) and normalizes its execution.
# Detects callable signature to properly dispatch params and context.
#
# Supported signatures:
#   - `(**context)` - receives only context
#   - `(params)` - receives only first param
#   - `(params, **context)` - receives first param and context
#   - `(p1, p2, ..., **context)` - receives multiple params and context
#
# @example Lambda with params and context
#   component = OmniService::Component.new(->(params, **ctx) { Success(post: params) })
#   component.call({ title: 'Hello' }, author: current_user)
#   # => Result(context: { author: current_user, post: { title: 'Hello' } })
#
# @example Context-only callable
#   component = OmniService::Component.new(->(**ctx) { Success(greeted: ctx[:user].name) })
#   component.call({}, user: User.new(name: 'John'))
#   # => Result(context: { user: ..., greeted: 'John' })
#
class OmniService::Component
  extend Dry::Initializer
  include Dry::Equalizer(:callable)
  include OmniService::Inspect.new(:callable)
  include OmniService::Strict

  MONADS_DO_WRAPPER_SIGNATURES = [
    [%i[rest *], %i[block &]],
    [%i[rest], %i[block &]], # Ruby 3.0, 3.1
    [%i[rest *], %i[keyrest **], %i[block &]],
    [%i[rest], %i[keyrest], %i[block &]] # Ruby 3.0, 3.1
  ].freeze
  DEFAULT_NAMES_MAP = { rest: '*', keyrest: '**' }.freeze # Ruby 3.0, 3.1

  param :callable, OmniService::Types::Interface(:call)

  def self.wrap(value)
    if value.is_a?(Array)
      value.map { |item| wrap(item) }
    elsif value.respond_to?(:signature)
      value
    else
      new(value)
    end
  end

  def call(*params, **context)
    callable_result = case signature
    in [0, true]
      callable.call(**context)
    in [n, false]
      callable.call(*params[...n])
    in [n, true]
      callable.call(*params[...n], **context)
    end

    OmniService::Result.build(callable, params:, context:).merge(OmniService::Result.process(callable, callable_result))
  end

  def signature
    @signature ||= [
      call_args(%i[rest]).empty? ? call_args(%i[req opt]).size : nil,
      !call_args(%i[key keyreq keyrest]).empty?
    ]
  end

  private

  def call_args(types)
    call_method = callable.respond_to?(:parameters) ? callable : callable.method(:call)
    # calling super_method here because `OmniService::Convenience`
    # calls `include Dry::Monads::Do.for(:call)` which creates
    # a delegator method around the original one.
    call_method = call_method.super_method if MONADS_DO_WRAPPER_SIGNATURES.include?(call_method.parameters)
    call_method.parameters.filter_map do |(type, name)|
      name || DEFAULT_NAMES_MAP[type] if types.include?(type)
    end
  end
end
