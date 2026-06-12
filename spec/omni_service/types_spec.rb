# frozen_string_literal: true

RSpec.describe OmniService::Types do
  describe '::Callable' do
    subject(:callable_type) { described_class::Callable }

    context 'with callable object' do
      let(:value) { -> {} }

      it 'accepts the value' do
        expect(callable_type[value]).to be(value)
      end
    end

    context 'with non-callable object' do
      let(:value) { Object.new }

      it 'rejects the value' do
        expect { callable_type[value] }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end
end
