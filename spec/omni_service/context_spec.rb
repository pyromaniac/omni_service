# frozen_string_literal: true

RSpec.describe OmniService::Context do
  let(:component) { described_class.new(value: OmniService::Types::String) }

  describe '#call' do
    it 'passes valid context through and ignores extra keys' do
      result = component.call(nil, value: 'test', extra: 123)

      expect(result).to be_success & have_attributes(
        context: hash_including(value: 'test', extra: 123)
      )
    end

    it 'raises with wrong type' do
      expect { component.call(nil, value: 123) }.to raise_error(Dry::Types::CoercionError)
    end
  end

  describe '#signature' do
    it 'returns splat params and context flag' do
      expect(component.signature).to eq([-1, true])
    end
  end
end
