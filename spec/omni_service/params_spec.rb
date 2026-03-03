# frozen_string_literal: true

RSpec.describe OmniService::Params do
  subject(:result) { params.call(input) }

  let(:params) { described_class.new(contract, optional:) }
  let(:optional) { false }
  let(:contract) do
    Class.new(Dry::Validation::Contract) do
      params do
        required(:name).filled(:string)
        required(:age).filled(:integer)
      end
    end.new
  end

  describe '.to_failure' do
    subject(:failure) { described_class.to_failure(message) }

    let(:message) { contract.call(input).errors.first }

    context 'when message responds to predicate' do
      let(:contract) do
        Class.new(Dry::Validation::Contract) do
          params do
            required(:name).filled(:string)
          end
        end.new
      end
      let(:input) { { name: '' } }

      it 'prefers predicate as error code' do
        expect(failure).to include(code: :filled?, message: 'must be filled', tokens: {})
      end
    end

    context 'when message does not respond to predicate' do
      let(:contract) do
        Class.new(Dry::Validation::Contract) do
          params do
            required(:name).filled(:string)
          end

          rule(:name) do
            key.failure(text: 'is invalid', code: :from_meta, minimum: 3) if value.length < 3
          end
        end.new
      end
      let(:input) { { name: 'ab' } }

      it 'uses meta code as fallback' do
        expect(failure).to include(code: :from_meta, message: 'is invalid', tokens: { minimum: 3 })
      end
    end

    context 'when message has no predicate and no meta code' do
      let(:contract) do
        Class.new(Dry::Validation::Contract) do
          params do
            required(:name).filled(:string)
          end

          rule(:name) do
            key.failure('is invalid') if value == 'x'
          end
        end.new
      end
      let(:input) { { name: 'x' } }

      it 'uses invalid as final fallback' do
        expect(failure).to include(code: :invalid, message: 'is invalid', tokens: {})
      end
    end
  end

  describe '#call' do
    context 'when params are valid' do
      let(:input) { { name: 'John', age: 30 } }

      it 'returns a success result with coerced params' do
        expect(result).to be_success & have_attributes(
          operation: params,
          params: [{ name: 'John', age: 30 }],
          context: {},
          errors: []
        )
      end
    end

    context 'with context passed to rules' do
      subject(:result) { params.call({ name: 'John' }, current_user: user) }

      let(:user) { 'admin' }
      let(:contract) do
        Class.new(Dry::Validation::Contract) do
          params { required(:name).filled(:string) }

          rule(:name) do |context:|
            context[:greeting] = "Hello, #{value} from #{context[:current_user]}!"
          end
        end.new
      end

      it 'passes context to rules and captures transformations' do
        expect(result).to be_success & have_attributes(
          params: [{ name: 'John' }],
          context: { current_user: 'admin', greeting: 'Hello, John from admin!' }
        )
      end
    end

    context 'when params are invalid' do
      let(:input) { { name: '', age: 'not_a_number' } }

      it 'returns a failure result with errors' do
        expect(result).to be_failure & have_attributes(
          operation: params,
          params: [{ name: '', age: 'not_a_number' }],
          errors: contain_exactly(
            have_attributes(component: params, code: :filled?, path: [:name]),
            have_attributes(component: params, code: :int?, path: [:age])
          )
        )
      end
    end

    context 'with optional: true' do
      let(:optional) { true }

      context 'when params are empty' do
        let(:input) { {} }

        it 'returns a success result with empty params' do
          expect(result).to be_success & have_attributes(
            operation: params,
            params: [{}],
            context: {},
            errors: []
          )
        end
      end

      context 'when params are provided' do
        let(:input) { { name: 'John', age: 30 } }

        it 'validates and returns a success result' do
          expect(result).to be_success & have_attributes(params: [{ name: 'John', age: 30 }])
        end
      end
    end
  end
end
