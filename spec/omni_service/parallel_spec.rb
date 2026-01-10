# frozen_string_literal: true

RSpec.describe OmniService::Parallel do
  subject(:parallel) { described_class.new(component_a, component_b, pack_params:) }

  describe '.new' do
    context 'when parallel is empty' do
      it 'raises constraint error' do
        expect { described_class.new }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end

  describe '#call' do
    subject(:call) { parallel.call(*input_params) }

    let(:pack_params) { false }
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

    context 'when single param and all signatures are 1' do
      let(:input_params) { [:p1] }
      let(:component_b) { ->(param, **) { Dry::Monads::Success[:y, result_b: param] } }

      it 'fans out the input param to all components' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :p1 },
          params: %i[p1 y]
        )
      end
    end

    context 'when five params and all signatures are 2' do
      let(:input_params) { %i[p1 p2 p3 p4 p5] }
      let(:component_a) { ->(first, second, **) { Dry::Monads::Success(result_a: [first, second]) } }
      let(:component_b) { ->(first, second, **) { Dry::Monads::Success(result_b: [first, second]) } }

      it 'distributes sequentially with leftover' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2], result_b: %i[p3 p4] },
          params: %i[p1 p2 p3 p4 p5]
        )
      end
    end

    context 'when two params with all nil signatures' do
      let(:input_params) { %i[p1 p2] }
      let(:component_a) { ->(*params, **) { Dry::Monads::Success(result_a: params) } }
      let(:component_b) { ->(*params, **) { Dry::Monads::Success[:y, result_b: params] } }

      it 'first splat consumes all, second gets nothing' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2], result_b: [] },
          params: %i[p1 p2 y]
        )
      end
    end

    context 'with multiple params' do
      let(:input_params) { %i[p1 p2 p3] }

      it 'distributes params and preserves leftovers' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :p2 },
          params: %i[p1 p2 p3]
        )
      end
    end

    context 'when component produces more than consumes' do
      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(param, **) { Dry::Monads::Success[:x, :y, result_a: param] } }

      it 'inserts produced params in place of consumed' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :p2 },
          params: %i[x y p2 p3]
        )
      end
    end

    context 'when component produces fewer than consumes' do
      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(first, second, **) { Dry::Monads::Success[:x, result_a: [first, second]] } }

      it 'inserts produced params in place of consumed' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2], result_b: :p3 },
          params: %i[x p3]
        )
      end
    end

    context 'when first component has nil signature' do
      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(*params, **) { Dry::Monads::Success[:x, result_a: params] } }
      let(:component_b) { ->(param = nil, **) { Dry::Monads::Success[:y, result_b: param] } }

      it 'first consumes all, second gets nothing' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2 p3], result_b: nil },
          params: %i[x y]
        )
      end
    end

    context 'with noop component' do
      subject(:parallel) do
        described_class.new(component_a, noop, component_b)
      end

      let(:noop) { ->(_, **) { Dry::Monads::Success({}) } }
      let(:input_params) { %i[p1 p2 p3] }

      it 'noop consumes one param and produces nothing' do
        expect(call).to be_success & have_attributes(
          params: %i[p1 p2 p3],
          context: { result_a: :p1, result_b: :p3 }
        )
      end
    end

    context 'with pack_params' do
      let(:pack_params) { true }
      let(:input_params) { [] }
      let(:component_a) { ->(**) { Dry::Monads::Success[{ a: 1 }, { a: 2 }, {}] } }
      let(:component_b) { ->(**) { Dry::Monads::Success[{ b: 1 }, {}] } }

      it 'merges params by index' do
        expect(call).to be_success & have_attributes(
          params: [{ a: 1, b: 1 }, { a: 2 }]
        )
      end
    end

    context 'with pack_params and non-hash output' do
      let(:pack_params) { true }
      let(:input_params) { [] }
      let(:component_a) { ->(**) { Dry::Monads::Success[{ a: 1 }, {}] } }
      let(:component_b) { ->(**) { Dry::Monads::Success[123, {}] } }

      it 'raises an error' do
        expect { call }.to raise_error(TypeError)
      end
    end

    context 'with pack_params and multiple components' do
      subject(:parallel) do
        described_class.new(component_a, component_b, component_c, component_d, pack_params: true)
      end

      let(:input_params) { [] }
      let(:component_a) { ->(**) { Dry::Monads::Success[{ a: 1 }, result_a: true] } }
      let(:component_b) { ->(**) { Dry::Monads::Success[{}, result_b: true] } }
      let(:component_c) { ->(**) { Dry::Monads::Success[{ c: 3 }, result_c: true] } }
      let(:component_d) { ->(**) { Dry::Monads::Success[{}, result_d: true] } }

      it 'merges all components preserving empty hashes' do
        expect(call).to be_success & have_attributes(
          params: [{ a: 1, c: 3 }],
          context: { result_a: true, result_b: true, result_c: true, result_d: true }
        )
      end
    end

    context 'with namespace component and single param' do
      subject(:parallel) { described_class.new(component_a, namespace_component) }

      let(:input_params) { [{ email: 'test@example.com', address: { city: 'NYC' } }] }
      let(:component_a) { ->(params, **) { Dry::Monads::Success(validated_email: params[:email]) } }
      let(:namespace_component) { OmniService::Namespace.new(:address, address_component) }
      let(:address_component) { ->(params, **) { Dry::Monads::Success(validated_city: params[:city]) } }

      it 'fans out single param to both components' do
        expect(parallel.call(*input_params)).to be_success & have_attributes(
          context: { validated_email: 'test@example.com', address: { validated_city: 'NYC' } }
        )
      end
    end

    context 'with namespace component and multiple params' do
      subject(:parallel) { described_class.new(component_a, namespace_component) }

      let(:input_params) { [{ email: 'test@example.com' }, { address: { city: 'NYC' } }] }
      let(:component_a) { ->(params, **) { Dry::Monads::Success(validated_email: params[:email]) } }
      let(:namespace_component) { OmniService::Namespace.new(:address, address_component) }
      let(:address_component) { ->(params, **) { Dry::Monads::Success(validated_city: params[:city]) } }

      it 'distributes params to each component' do
        expect(parallel.call(*input_params)).to be_success & have_attributes(
          context: { validated_email: 'test@example.com', address: { validated_city: 'NYC' } }
        )
      end
    end

    context 'with multiple namespaces and pack_params' do
      subject(:parallel) do
        described_class.new(
          OmniService::Namespace.new(:billing, billing_processor),
          OmniService::Namespace.new(:shipping, shipping_processor),
          pack_params: true
        )
      end

      let(:input_params) { [{ billing: { card: '4111' }, shipping: { address: '123 Main St' } }] }
      let(:billing_processor) { ->(params, **) { Dry::Monads::Success[params.merge(processed: true), {}] } }
      let(:shipping_processor) { ->(params, **) { Dry::Monads::Success[params.merge(processed: true), {}] } }

      it 'fans out and merges params from both namespaces' do
        expect(parallel.call(*input_params)).to be_success & have_attributes(
          params: [{
            billing: { card: '4111', processed: true },
            shipping: { address: '123 Main St', processed: true }
          }],
          context: {}
        )
      end
    end

    context 'when some components fail' do
      subject(:parallel) { described_class.new(component_a, component_b, component_c) }

      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(_, **) { Dry::Monads::Failure(:invalid_a) } }
      let(:component_b) { ->(param, **) { Dry::Monads::Success[:x, result_b: param] } }
      let(:component_c) { ->(_, **) { Dry::Monads::Failure(:invalid_c) } }

      it 'collects errors and preserves successful params/context' do
        expect(call).to be_failure & have_attributes(
          params: %i[p1 x p3],
          context: { result_b: :p2 },
          errors: [
            have_attributes(code: :invalid_a),
            have_attributes(code: :invalid_c)
          ]
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { parallel.signature }

    let(:pack_params) { false }

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

    context 'when components have optional params' do
      let(:component_a) { ->(first, second = nil, **) {} }
      let(:component_b) { ->(first, **) {} }

      it 'returns sum including optional' do
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

    context 'when any component has required param and splat' do
      let(:component_a) { ->(first, **) {} }
      let(:component_b) { ->(first, *rest, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
