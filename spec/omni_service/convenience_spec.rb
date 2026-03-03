# frozen_string_literal: true

RSpec.describe OmniService::Convenience do
  let(:operation_class) do
    Class.new do
      extend OmniService::Convenience
    end
  end

  describe '#schema' do
    subject(:result) { validator.call(input) }

    let(:input) { { name: 'John' } }
    let(:validator) do
      operation_class.schema do
        params do
          required(:name).filled(:string)
        end
      end
    end

    it 'builds a validator from contract DSL' do
      expect(result).to be_success & have_attributes(
        params: [{ name: 'John' }],
        errors: []
      )
    end
  end

  describe '#params' do
    subject(:result) { validator.call(input) }

    let(:input) { { name: 'John' } }
    let(:validator) { operation_class.params { required(:name).filled(:string) } }

    it 'builds a params shorthand validator' do
      expect(result).to be_success & have_attributes(
        params: [{ name: 'John' }],
        errors: []
      )
    end
  end
end
