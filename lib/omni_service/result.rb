# frozen_string_literal: true

# Structured result of component execution.
#
# Attributes:
# - operation: the component that produced this result
# - shortcut: component that triggered early exit (if any)
# - params: array of transformed params
# - context: accumulated key-value pairs from all components
# - errors: array of OmniService::Error
# - on_success: results from transaction success callbacks
# - on_failure: results from transaction failure callbacks
#
# Components return Success/Failure monads which are converted to Result:
# - Success(key: value) => Result(context: { key: value })
# - Success(params, key: value) => Result(params: [params], context: { key: value })
# - Failure(:code) => Result(errors: [Error(code: :code)])
# - Failure([{ code:, path:, message: }]) => Result(errors: [...])
#
# @example Checking result
#   result = operation.call(params, **context)
#   result.success?  # => true/false
#   result.failure?  # => true/false
#   result.context   # => { post: <Post>, author: <Author> }
#   result.errors    # => [#<Error code=:blank path=[:title]>]
#
# @example Converting to monad
#   result.to_monad  # => Success(result) or Failure(result)
#
class OmniService::Result
  extend Dry::Initializer
  include Dry::Monads[:result]
  include Dry::Equalizer(:operation, :params, :context, :errors, :on_success, :on_failure)
  include OmniService::Inspect.new(:operation, :params, :context, :errors, :on_success, :on_failure)

  option :operation, type: OmniService::Types::Interface(:call)
  option :shortcut, type: OmniService::Types::Interface(:call).optional, default: proc {}
  option :params, type: OmniService::Types::Array
  option :context, type: OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Any)
  option :errors, type: OmniService::Types::Array.of(OmniService::Error)
  option :on_success, type: OmniService::Types::Array.of(
    OmniService::Types::Instance(OmniService::Result) | OmniService::Types::Instance(Concurrent::Promises::Future)
  ), default: proc { [] }
  option :on_failure, type: OmniService::Types::Array.of(OmniService::Types::Instance(OmniService::Result)), default: proc { [] }

  def self.process(component, result)
    case result
    in OmniService::Result
      result
    in Success(params, *other_params, Hash => context) if context.keys.all?(Symbol)
      OmniService::Result.build(component, params: [params, *other_params], context:)
    in Success(Hash => context) if context.keys.all?(Symbol)
      OmniService::Result.build(component, context:)
    in Failure[*failures]
      OmniService::Result.build(component, errors: OmniService::Error.process(component, failures))
    else
      raise "Invalid callable result `#{result.inspect}` returned by `#{component.inspect}`"
    end
  end

  def self.build(operation, **)
    new(operation:, params: [], context: {}, errors: [], **)
  end

  def merge(other = nil, **changes)
    if other
      self.class.new(
        operation:,
        shortcut: shortcut || other.shortcut,
        **merged_attributes(other),
        **changes
      )
    else
      self.class.new(**self.class.dry_initializer.attributes(self), **changes)
    end
  end

  alias shortcut? shortcut

  def success?
    errors.empty?
  end

  def failure?
    !success?
  end

  def to_monad
    success? ? Success(self) : Failure(self)
  end

  def deconstruct_keys(_)
    { operation:, params:, context:, errors: }
  end

  private

  def merged_attributes(other)
    {
      params: other.params.empty? ? params : other.params,
      context: context.merge(other.context),
      errors: errors + other.errors,
      on_success: on_success + other.on_success,
      on_failure: on_failure + other.on_failure
    }
  end
end
