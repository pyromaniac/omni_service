# frozen_string_literal: true

# Validates and coerces params using Dry::Validation::Contract.
#
# Behavior:
# - Validates params against contract schema and rules
# - Coerces params to declared types (strings to integers, etc.)
# - Passes context to contract rules for cross-field validation
# - Rules can transform context (e.g., enrich with fetched entities)
# - Returns validation errors with code, message, path, and tokens
#
# @example Basic validation with inline contract
#   params { required(:email).filled(:string, format?: /@/) }
#
# @example With external contract class
#   class UserContract < Dry::Validation::Contract
#     params do
#       required(:name).filled(:string)
#       required(:age).filled(:integer, gt?: 0)
#     end
#   end
#   OmniService::Params.new(UserContract.new)
#
# @example Context-aware rules with transformation
#   OmniService::Params.new(Class.new(Dry::Validation::Contract) do
#     params { required(:post_id).filled(:integer) }
#
#     rule(:post_id) do |context:|
#       context[:post] = PostRepository.find(value)
#       key.failure(:not_found) unless context[:post]
#     end
#   end.new)
#   # Call: params.call({ post_id: 1 }, current_user: user)
#   # Result context: { current_user: user, post: <Post> }
#
# @example Optional params (skip validation when empty)
#   params(optional: true) { required(:query).filled(:string) }
#   # Empty params {} => success with {}
#   # Non-empty params validated normally
#
class OmniService::Params
  extend Dry::Initializer

  param :contract, OmniService::Types::Instance(Dry::Validation::Contract)
  option :optional, OmniService::Types::Bool, default: proc { false }

  def self.to_failure(message)
    {
      code: (message.predicate if message.respond_to?(:predicate)) || :invalid,
      message: message.dump,
      path: message.path,
      tokens: message.respond_to?(:meta) ? message.meta : {}
    }
  end

  def self.params(**, &)
    new(**) { params(&) }
  end

  def initialize(contract = nil, **, &)
    contract_class = Class.new(Dry::Validation::Contract, &)
    super(contract || contract_class.new, **)
  end

  def call(params = {}, **context)
    contract_result = contract.call(params, context)

    if optional && contract_result.to_h.empty?
      OmniService::Result.build(self, params: [{}])
    else
      to_operation_result(contract_result)
    end
  end

  private

  def to_operation_result(contract_result)
    OmniService::Result.build(
      self,
      params: [contract_result.to_h],
      context: contract_result.context.each.to_h,
      errors: contract_result.errors.map do |error|
        OmniService::Error.build(self, **self.class.to_failure(error))
      end
    )
  end
end
