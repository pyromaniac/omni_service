# frozen_string_literal: true

RSpec.describe OmniService::Remap do
  subject(:remap_component) { described_class.new(mapping, **options) }

  let(:mapping) { { current_account: :account } }
  let(:options) { {} }

  describe '#call' do
    subject(:result) { remap_component.call(params, **context) }

    let(:params) { { title: 'Hello' } }
    let(:context) { { current_account: account, other: 'data' } }
    let(:account) { Object.new }

    it 'remaps context keys' do
      expect(result).to be_success & have_attributes(
        params: [params],
        context: { account: }
      )
    end

    context 'with multiple mappings' do
      let(:mapping) { { current_account: :account, current_user: :user } }
      let(:context) { { current_account: account, current_user: user } }
      let(:user) { Object.new }

      it 'remaps all keys' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { account:, user: }
        )
      end
    end

    context 'with path mapping' do
      let(:mapping) { { %i[profile individual] => :profile } }
      let(:context) { { profile: { individual: } } }
      let(:individual) { Object.new }

      it 'digs through nested context' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { profile: individual }
        )
      end
    end

    context 'with mixed symbol and path mappings' do
      let(:mapping) { { current_account: :account, %i[profile organization] => :profile } }
      let(:context) { { current_account: account, profile: { organization: } } }
      let(:organization) { Object.new }

      it 'remaps both symbol and path keys' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { account:, profile: organization }
        )
      end
    end

    context 'with path calling methods on objects' do
      let(:mapping) { { %i[account profile present?] => :has_profile } }
      let(:context) { { account: account } }
      let(:account) { Struct.new(:profile).new(profile) }
      let(:profile) { Object.new }

      it 'calls public methods in path chain' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { has_profile: true }
        )
      end
    end

    context 'with nil in path' do
      let(:mapping) { { %i[account profile name] => :profile_name } }
      let(:context) { { account: account } }
      let(:account) { Struct.new(:profile).new(nil) }

      it 'returns nil for the mapped key' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { profile_name: nil }
        )
      end
    end

    context 'with nested target path' do
      let(:mapping) { { email: %i[user email] } }
      let(:context) { { email: 'test@example.com' } }

      it 'sets value at nested path' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { user: { email: 'test@example.com' } }
        )
      end
    end

    context 'with multiple sources to same target' do
      let(:mapping) do
        {
          %i[first value] => :items,
          %i[second value] => :items
        }
      end
      let(:context) { { first: { value: 'a' }, second: { value: 'b' } } }

      it 'collects values into an array' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { items: %w[a b] }
        )
      end
    end

    context 'with multiple array sources to same target' do
      let(:mapping) { { first_ids: :ids, second_ids: :ids } }
      let(:context) { { first_ids: [1, 2], second_ids: [3, 4] } }

      it 'concatenates values into one array' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { ids: [1, 2, 3, 4] }
        )
      end
    end

    context 'with mixed array and scalar sources' do
      let(:mapping) { { tag_ids: :ids, featured_tag_id: :ids } }
      let(:context) { { tag_ids: [1, 2], featured_tag_id: 3 } }

      it 'concatenates all values into one array' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { ids: [1, 2, 3] }
        )
      end
    end

    context 'with array collection and some nil values' do
      let(:mapping) do
        {
          %i[first value] => :items,
          %i[second value] => :items
        }
      end
      let(:context) { { first: { value: 'a' }, second: {} } }

      it 'skips nil values in array' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { items: ['a'] }
        )
      end
    end

    context 'with array collection and all nil values' do
      let(:mapping) do
        {
          %i[first value] => :items,
          %i[second value] => :items
        }
      end
      let(:context) { { first: {}, second: {} } }

      it 'omits the key entirely' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: {}
        )
      end
    end

    context 'with expanded references' do
      let(:mapping) { { %i[comments id] => :comment_ids } }
      let(:context) { { comments: [{ id: 1 }, { id: 2 }] } }

      it 'collects expanded values' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { comment_ids: [1, 2] }
        )
      end
    end

    context 'with expanded terminal arrays' do
      let(:mapping) { { %i[groups ids] => :ids } }
      let(:context) { { groups: [{ ids: [1, 2] }, { ids: [3, 4] }] } }

      it 'concatenates terminal arrays' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { ids: [1, 2, 3, 4] }
        )
      end
    end

    context 'with custom path' do
      let(:mapping) { { source: :target } }
      let(:options) { { path: custom_path } }
      let(:custom_path) { ->(_root, source) { [OmniService::Path::Reference.new(path: source, value: 'custom', resolved: true)] } }

      it 'uses the injected path dependency' do
        expect(result).to be_success & have_attributes(
          params: [params],
          context: { target: 'custom' }
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { remap_component.signature }

    it 'consumes only context' do
      expect(signature).to eq([0, true])
    end
  end
end
