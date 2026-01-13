# frozen_string_literal: true

RSpec.describe OmniService::Sequence do
  subject(:sequence) { described_class.new(component_a, component_b) }

  let(:component_a) { ->(param, **) { Dry::Monads::Success(result_a: param) } }
  let(:component_b) { ->(param, **) { Dry::Monads::Success(result_b: param) } }

  describe '.new' do
    context 'when sequence is empty' do
      it 'raises constraint error' do
        expect { described_class.new }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end

  describe '#call' do
    subject(:call) { sequence.call(*input_params) }

    let(:input_params) { [:p1] }

    context 'when components produce no params' do
      it 'passes through input params to next component' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :p1 },
          params: [:p1]
        )
      end
    end

    context 'when component transforms params' do
      let(:component_a) { ->(param, **) { Dry::Monads::Success[:transformed, result_a: param] } }

      it 'chains transformed params to next component' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: :transformed },
          params: [:transformed]
        )
      end
    end

    context 'when component expands params' do
      let(:input_params) { [:p1] }
      let(:component_a) { ->(param, **) { Dry::Monads::Success[:x, :y, result_a: param] } }
      let(:component_b) { ->(first, second, **) { Dry::Monads::Success(result_b: [first, second]) } }

      it 'passes expanded params to next component' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1, result_b: %i[x y] },
          params: %i[x y]
        )
      end
    end

    context 'when component reduces params' do
      let(:input_params) { %i[p1 p2] }
      let(:component_a) { ->(first, second, **) { Dry::Monads::Success[:combined, result_a: [first, second]] } }

      it 'passes reduced params to next component' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2], result_b: :combined },
          params: [:combined]
        )
      end
    end

    context 'when first component fails' do
      let(:component_a) { ->(**) { Dry::Monads::Failure(:invalid) } }

      it 'short-circuits and does not call subsequent components' do
        expect(call).to be_failure & have_attributes(
          context: {},
          params: [:p1],
          errors: [have_attributes(code: :invalid)]
        )
      end
    end

    context 'when component has nil signature' do
      let(:input_params) { %i[p1 p2 p3] }
      let(:component_a) { ->(*params, **) { Dry::Monads::Success[:x, result_a: params] } }

      it 'consumes all params' do
        expect(call).to be_success & have_attributes(
          context: { result_a: %i[p1 p2 p3], result_b: :x },
          params: [:x]
        )
      end
    end

    context 'with context accumulation' do
      let(:component_a) { ->(_, **) { Dry::Monads::Success(key_a: 1) } }
      let(:component_b) { ->(_, key_a:, **) { Dry::Monads::Success(key_b: key_a + 1) } }

      it 'accumulates context across components' do
        expect(call).to be_success & have_attributes(
          context: { key_a: 1, key_b: 2 },
          params: [:p1]
        )
      end
    end

    context 'with shortcut component' do
      subject(:sequence) do
        described_class.new(
          OmniService::Shortcut.new(cache_lookup),
          expensive_computation
        )
      end

      let(:cache_lookup) do
        lambda do |params, **|
          if params[:cached]
            Dry::Monads::Success(from_cache: true)
          else
            Dry::Monads::Failure(:not_cached)
          end
        end
      end
      let(:expensive_computation) { ->(_, **) { Dry::Monads::Success(computed: true) } }

      it 'shortcuts when inner component succeeds' do
        result = sequence.call({ cached: true })

        expect(result).to be_success & have_attributes(context: { from_cache: true })
        expect(result.shortcut).to be_truthy
      end

      it 'continues when inner component fails' do
        result = sequence.call({ cached: false })

        expect(result).to be_success & have_attributes(context: { computed: true })
        expect(result.shortcut).to be_nil
      end
    end
  end

  describe '#signature' do
    subject(:signature) { sequence.signature }

    context 'when first component has context-only signature' do
      let(:component_a) { ->(**) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns first non-zero signature' do
        expect(signature).to eq([1, true])
      end
    end

    context 'when all components have context-only signature' do
      let(:component_a) { ->(**) {} }
      let(:component_b) { ->(**) {} }

      it 'returns first component signature (zero params)' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when first component has single param' do
      let(:component_a) { ->(param, **) {} }
      let(:component_b) { ->(first, second) {} }

      it 'returns param count' do
        expect(signature).to eq([1, true])
      end
    end

    context 'when first component has multiple params without context' do
      let(:component_a) { ->(first, second) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns param count with context forced true' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when first component has optional params' do
      let(:component_a) { ->(first, second = nil, **) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns total param count including optional' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when first component has splat signature' do
      let(:component_a) { ->(*args, **) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end

    context 'when first component has required param and splat' do
      let(:component_a) { ->(first, *rest, **) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
