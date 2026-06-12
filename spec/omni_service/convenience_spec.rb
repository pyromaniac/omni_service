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

  describe '#assert' do
    subject(:assert_component) { operation_class.assert(:authorized, code: :unauthorized) }

    it 'builds an assert component' do
      expect(assert_component).to be_a(OmniService::Assert) & have_attributes(
        predicate: [:authorized],
        code: :unauthorized
      )
    end
  end

  describe '#refute' do
    subject(:refute_component) { operation_class.refute(:archived, code: :already_archived) }

    it 'builds a refute component' do
      expect(refute_component).to be_a(OmniService::Refute) & have_attributes(
        predicate: [:archived],
        code: :already_archived
      )
    end
  end

  describe '#remap' do
    subject(:remap_component) { operation_class.remap(current_account: :account) }

    it 'builds a remap component' do
      expect(remap_component).to be_a(OmniService::Remap) & have_attributes(
        mapping: { current_account: :account }
      )
    end
  end
end
