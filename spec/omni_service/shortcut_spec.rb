# frozen_string_literal: true

RSpec.describe OmniService::Shortcut do
  subject(:shortcut) { described_class.new(component) }

  let(:component) { ->(param, **) { Dry::Monads::Success(result: param) } }

  describe '#signature' do
    subject(:signature) { shortcut.signature }

    context 'when component has context-only signature' do
      let(:component) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when component has single param' do
      let(:component) { ->(param, **) {} }

      it 'returns param count' do
        expect(signature).to eq([1, true])
      end
    end

    context 'when component has multiple params without context' do
      let(:component) { ->(first, second) {} }

      it 'returns param count with context forced true' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when component has optional params' do
      let(:component) { ->(first, second = nil, **) {} }

      it 'returns total param count including optional' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when component has splat signature' do
      let(:component) { ->(*params, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end

    context 'when component has required param and splat' do
      let(:component) { ->(first, *rest, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
