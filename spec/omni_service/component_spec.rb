# frozen_string_literal: true

RSpec.describe OmniService::Component do
  let(:component) { described_class.new(callable) }

  describe '.wrap' do
    let(:callable) { -> {} }

    specify do
      expect(described_class.wrap(component)).to equal(component)
      expect(described_class.wrap([component])).to eq([component])
      expect(described_class.wrap(callable)).to eq(described_class.new(callable))
      expect(described_class.wrap([callable])).to eq([described_class.new(callable)])
    end
  end

  describe '.call' do
    context 'when the callable signature is `(params, **context)`' do
      let(:callable) { ->(_params, **_context) { Dry::Monads::Success[:new_params, new_key: 43] } }

      it 'returns a result' do
        expect(component.call(:old_params, old_key: 42)).to be_a(OmniService::Result) & have_attributes(
          operation: callable,
          shortcut: nil,
          params: [:new_params],
          context: { old_key: 42, new_key: 43 },
          errors: [],
          on_success: [],
          on_failure: []
        )
      end
    end

    context 'when the callable signature is `(params)`' do
      let(:callable) { ->(params) { Dry::Monads::Success(params: params) } }

      it 'returns a result' do
        expect(component.call('old_params', old_key: 42)).to be_a(OmniService::Result) & have_attributes(
          operation: callable,
          shortcut: nil,
          params: ['old_params'],
          context: { old_key: 42, params: 'old_params' },
          errors: [],
          on_success: [],
          on_failure: []
        )
      end
    end

    context 'when the callable signature is `(**context)`' do
      let(:callable) { ->(**) { Dry::Monads::Failure(:invalid) } }

      it 'returns a result' do
        expect(component.call('old_params', new_key: 43)).to be_a(OmniService::Result) & have_attributes(
          operation: callable,
          shortcut: nil,
          params: ['old_params'],
          context: { new_key: 43 },
          errors: [have_attributes(message: nil, code: :invalid, path: [], tokens: {})],
          on_success: [],
          on_failure: []
        )
      end
    end

    context 'with invalid callable signatures' do
      let(:callable) { ->(params1, params2) {} }

      it 'raises an error' do
        expect { component.call(:params) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '#signature' do
    subject(:signature) { component.signature }

    context 'with context-only callable' do
      let(:callable) { ->(**) {} }

      it 'returns zero params with context' do
        expect(signature).to eq([0, true])
      end
    end

    context 'with single param callable' do
      let(:callable) { ->(param, **) {} }

      it 'returns param count with context' do
        expect(signature).to eq([1, true])
      end
    end

    context 'with multiple params callable' do
      let(:callable) { ->(first, second) {} }

      it 'returns param count without context' do
        expect(signature).to eq([2, false])
      end
    end

    context 'with optional params callable' do
      let(:callable) { ->(first, second = nil, **) {} }

      it 'returns total param count including optional' do
        expect(signature).to eq([2, true])
      end
    end

    context 'with splat params callable' do
      let(:callable) { ->(*params, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end

    context 'with required param and splat callable' do
      let(:callable) { ->(first, *rest, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
