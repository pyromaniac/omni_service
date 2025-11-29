# frozen_string_literal: true

# Validates params against a Dry::Validation::Contract.
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
