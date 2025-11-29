# frozen_string_literal: true

# Structured validation/operation error.
#
# Attributes:
# - component: the component that produced the error
# - code: symbolic error code (e.g., :blank, :not_found, :invalid)
# - message: human-readable message (optional)
# - path: array of keys/indices to error location (e.g., [:author, :email])
# - tokens: interpolation values for message templates (e.g., { min: 5 })
#
# Components return failures that are converted to Error:
# - Failure(:code) => Error(code: :code)
# - Failure("message") => Error(message: "message")
# - Failure({ code:, path:, message:, tokens: }) => Error(...)
# - Failure([...]) => multiple Errors
#
# @example Simple error
#   Failure(:not_found)
#   # => Error(code: :not_found, path: [])
#
# @example Error with path
#   Failure([{ code: :blank, path: [:title] }])
#   # => Error(code: :blank, path: [:title])
#
# @example Error with tokens for i18n
#   Failure([{ code: :too_short, path: [:body], tokens: { min: 100 } }])
#
class OmniService::Error < Dry::Struct
  attribute :component, OmniService::Types::Interface(:call)
  attribute :message, OmniService::Types::Strict::String.optional
  attribute :code, OmniService::Types::Strict::Symbol.optional
  attribute :path, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol | OmniService::Types::Integer)
  attribute :tokens, OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Any)

  def self.process(component, failure)
    case failure
    in Array
      failure.flat_map { |error| process(component, error) }
    in OmniService::Error
      failure.new(component:)
    in String
      [build(component, message: failure)]
    in Symbol
      [build(component, code: failure)]
    in Hash
      [build(component, **failure)]
    else
      raise "Invalid failure `#{failure.inspect}` returned by `#{component.inspect}`"
    end
  end

  def self.build(component, **)
    new(message: nil, code: nil, path: [], tokens: {}, **, component:)
  end
end
