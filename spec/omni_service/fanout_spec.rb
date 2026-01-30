# frozen_string_literal: true

RSpec.describe OmniService::Fanout do
  subject(:fanout) { described_class.new(component_a, component_b) }

  describe '.new' do
    context 'when fanout is empty' do
      it 'raises constraint error' do
        expect { described_class.new }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end

  describe '#call' do
    subject(:call) { fanout.call(*input_params) }

    let(:component_a) { ->(params, **) { Dry::Monads::Success(result_a: params) } }
    let(:component_b) { ->(params, **) { Dry::Monads::Success(result_b: params) } }

    context 'when two params and all signatures are 1' do
      let(:input_params) { %i[p1 p2] }

      it 'fans out the first param to all components' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :p1 },
          params: %i[p1 p1]
        )
      end
    end

    context 'when signatures differ' do
      let(:input_params) { %i[p1 p2] }
      let(:component_a) { ->(first, second, **) { Dry::Monads::Success(result_a: [first, second]) } }

      it 'fans out input params based on each signature' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2], result_b: :p1 },
          params: %i[p1 p2 p1]
        )
      end
    end

    context 'when any component has splat signature' do
      let(:input_params) { %i[p1 p2] }
      let(:component_a) { ->(*params, **) { Dry::Monads::Success(result_a: params) } }

      it 'fans out all params to splat and first param to others' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2], result_b: :p1 },
          params: %i[p1 p2 p1]
        )
      end
    end

    context 'when some components fail' do
      subject(:fanout) { described_class.new(component_a, component_b, component_c) }

      let(:input_params) { [:p1] }
      let(:component_a) { ->(_, **) { Dry::Monads::Failure(:invalid_a) } }
      let(:component_b) { ->(_, **) { Dry::Monads::Failure(:invalid_b) } }
      let(:component_c) { ->(param, **) { Dry::Monads::Success(result_c: param) } }

      it 'collects errors and preserves successful context' do
        expect(call).to be_failure & have_attributes(
          params: %i[p1 p1 p1],
          context: { result_c: :p1 },
          errors: [
            have_attributes(code: :invalid_a),
            have_attributes(code: :invalid_b)
          ]
        )
      end
    end

    context 'when components return different param counts' do
      subject(:fanout) { described_class.new(component_a, component_b, component_c) }

      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(_, **) { Dry::Monads::Success[:r1, :r2, {}] } }
      let(:component_b) { ->(**) { Dry::Monads::Success(result_b: true) } }
      let(:component_c) { ->(_, **) { Dry::Monads::Success() } }

      it 'accumulates returned params across components' do
        expect(call).to be_success & have_attributes(
          params: %i[r1 r2 p1],
          context: { result_b: true }
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { fanout.signature }

    context 'when all components have context-only signature' do
      let(:component_a) { ->(**) {} }
      let(:component_b) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when components have different signatures' do
      let(:component_a) { ->(first, second, **) {} }
      let(:component_b) { ->(first, **) {} }

      it 'returns max' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when any component has splat signature' do
      let(:component_a) { ->(first, **) {} }
      let(:component_b) { ->(*args, **) {} }

      it 'returns max of non-splat signatures' do
        expect(signature).to eq([1, true])
      end
    end

    context 'when all components have splat signature' do
      let(:component_a) { ->(*args, **) {} }
      let(:component_b) { ->(*args, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
