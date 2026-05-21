# frozen_string_literal: true

RSpec.describe OmniService::Error do
  subject(:error) { described_class.build(component, **attributes) }

  let(:component) { ->(**) { Dry::Monads::Success() } }
  let(:attributes) { {} }

  describe '#to_hash' do
    subject(:to_hash) { error.to_hash }

    context 'with code and path' do
      let(:attributes) { { code: :invalid, path: [:name] } }

      it 'returns public error fields' do
        expect(to_hash).to eq(code: :invalid, path: [:name])
      end
    end

    context 'with message and path' do
      let(:attributes) { { message: 'Something failed', path: [] } }

      it 'returns public error fields' do
        expect(to_hash).to eq(message: 'Something failed', path: [])
      end
    end

    context 'with empty message' do
      let(:attributes) { { message: '', path: [:base] } }

      it 'omits the message' do
        expect(to_hash).to eq(path: [:base])
      end
    end

    context 'with tokens' do
      let(:attributes) { { code: :too_short, path: [:body], tokens: { min: 100 } } }

      it 'returns interpolation tokens' do
        expect(to_hash).to eq(code: :too_short, path: [:body], tokens: { min: 100 })
      end
    end

    context 'without code message or tokens' do
      it 'returns the path' do
        expect(to_hash).to eq(path: [])
      end
    end
  end

  describe '#to_h' do
    subject(:to_h) { error.to_h }

    let(:attributes) { { code: :invalid, path: [:name] } }

    it 'matches to_hash' do
      expect(to_h).to eq(error.to_hash)
    end
  end
end
