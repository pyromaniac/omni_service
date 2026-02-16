# frozen_string_literal: true

RSpec.describe OmniService do
  describe '::VERSION' do
    subject(:version) { described_class::VERSION }

    it 'has a version number' do
      expect(version).not_to be_nil
    end
  end
end
