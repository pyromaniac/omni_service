# frozen_string_literal: true

RSpec.describe OmniService::Context do
  subject(:context) { described_class.new(schema, raise_on_error:) }

  let(:schema) { { value: OmniService::Types::String } }
  let(:raise_on_error) { false }

  describe '#call' do
    subject(:result) { context.call(*params, **input) }

    let(:params) { [] }
    let(:input) { { value: 'test' } }

    context 'when context is valid' do
      it 'returns success with coerced context' do
        expect(result).to be_success & have_attributes(
          operation: context,
          params: [],
          context: { value: 'test' },
          errors: []
        )
      end

      context 'with extra keys' do
        let(:input) { { value: 'test', extra: 123 } }

        it 'preserves extra keys in context' do
          expect(result).to be_success & have_attributes(
            context: { value: 'test', extra: 123 }
          )
        end
      end

      context 'with params' do
        let(:params) { %w[param1 param2] }

        it 'passes params through unchanged' do
          expect(result).to be_success & have_attributes(
            params: %w[param1 param2]
          )
        end
      end
    end

    context 'when context is invalid' do
      let(:input) { { value: 123 } }

      context 'with raise_on_error: false' do
        it 'returns failure with errors' do
          expect(result).to be_failure & have_attributes(
            operation: context,
            params: [],
            context: { value: 123 },
            errors: [have_attributes(component: context, path: [])]
          )
        end
      end

      context 'with raise_on_error: true' do
        let(:raise_on_error) { true }

        it 'raises OperationFailed' do
          expect { result }.to raise_error(OmniService::OperationFailed) do |error|
            expect(error.operation_result).to be_failure & have_attributes(
              operation: context,
              errors: [have_attributes(component: context, path: [])]
            )
          end
        end
      end
    end

    context 'with multiple schema keys' do
      let(:schema) do
        {
          name: OmniService::Types::String,
          count: OmniService::Types::Coercible::Integer
        }
      end
      let(:input) { { name: 'test', count: '42' } }

      it 'coerces all values' do
        expect(result).to be_success & have_attributes(
          context: { name: 'test', count: 42 }
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { context.signature }

    it 'returns zero params and context flag' do
      expect(signature).to eq([0, true])
    end
  end
end
