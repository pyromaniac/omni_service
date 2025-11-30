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

  describe '.params' do
    subject(:params) { described_class.params { required(:name).filled(:string) } }

    it 'creates a validator with inline contract' do
      expect(params.call({ name: 'John' })).to be_success
      expect(params.call({ name: '' })).to be_failure
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
