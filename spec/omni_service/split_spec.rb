# frozen_string_literal: true

RSpec.describe OmniService::Split do
  subject(:split) { described_class.new(component_a, component_b) }

  describe '.new' do
    context 'when split is empty' do
      it 'raises constraint error' do
        expect { described_class.new }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end

  describe '#call' do
    subject(:call) { split.call(*input_params) }

    let(:component_a) { ->(params, **) { Dry::Monads::Success(result_a: params) } }
    let(:component_b) { ->(params, **) { Dry::Monads::Success(result_b: params) } }

    context 'when two params and all signatures are 1' do
      let(:input_params) { %i[p1 p2] }

      it 'distributes sequentially' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :p2 },
          params: %i[p1 p2]
        )
      end
    end

    context 'when some components fail' do
      let(:input_params) { %i[p1 p2] }
      let(:execution_log) { [] }
      let(:component_a) do
        lambda do |param, **|
          execution_log << [:a, param]
          Dry::Monads::Failure(:invalid_a)
        end
      end
      let(:component_b) do
        lambda do |param, **|
          execution_log << [:b, param]
          Dry::Monads::Failure(:invalid_b)
        end
      end

      it 'fails fast and does not run later components' do
        expect(call).to be_failure & have_attributes(
          params: %i[p1 p2],
          errors: [have_attributes(code: :invalid_a)]
        )
        expect(execution_log).to eq([%i[a p1]])
      end
    end

    context 'when components produce params' do
      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(_, **) { Dry::Monads::Success[:x, :y, {}] } }
      let(:component_b) { ->(_, **) { Dry::Monads::Success[:z, {}] } }

      it 'accumulates returned params and preserves leftovers' do
        expect(call).to be_success & have_attributes(
          params: %i[x y z p3]
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { split.signature }

    context 'when all components have context-only signature' do
      let(:component_a) { ->(**) {} }
      let(:component_b) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when all components have same signature' do
      let(:component_a) { ->(param, **) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns sum' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when components have different signatures' do
      let(:component_a) { ->(first) {} }
      let(:component_b) { ->(first, second) {} }

      it 'returns sum' do
        expect(signature).to eq([3, true])
      end
    end

    context 'when any component has splat signature' do
      let(:component_a) { ->(first, **) {} }
      let(:component_b) { ->(*args, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
