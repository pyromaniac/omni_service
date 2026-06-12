# frozen_string_literal: true

RSpec.describe OmniService::Path do
  subject(:path_component) { described_class.new(**options) }

  let(:options) { {} }

  describe '#call' do
    subject(:references) { path_component.call(root, path) }

    let(:root) { { user: { id: 1 } } }
    let(:path) { %i[user id] }

    context 'with resolved hash path' do
      it 'returns a resolved reference' do
        expect(references).to contain_exactly(
          have_attributes(path: %i[user id], value: 1, resolved?: true, unresolved?: false, missing?: false)
        )
      end
    end

    context 'with resolved nil value' do
      let(:root) { { user: { id: nil } } }

      it 'keeps resolution separate from value' do
        expect(references).to contain_exactly(
          have_attributes(path: %i[user id], value: nil, resolved?: true, unresolved?: false, missing?: false)
        )
      end
    end

    context 'with missing hash path' do
      let(:root) { { user: {} } }

      it 'returns a missing reference with full path' do
        expect(references).to contain_exactly(
          have_attributes(path: %i[user id], value: nil, resolved?: false, unresolved?: true, missing?: true)
        )
      end
    end

    context 'with array index' do
      let(:root) { { items: [{ id: 1 }] } }
      let(:path) { [:items, 0, :id] }

      it 'reads the indexed item' do
        expect(references).to contain_exactly(
          have_attributes(path: [:items, 0, :id], value: 1, resolved?: true)
        )
      end
    end

    context 'with expanded arrays' do
      let(:options) { { expand_arrays: true } }
      let(:root) { { items: [{ id: 1 }, { id: 2 }] } }
      let(:path) { %i[items id] }

      it 'returns references for each item' do
        expect(references).to contain_exactly(
          have_attributes(path: [:items, 0, :id], value: 1, resolved?: true),
          have_attributes(path: [:items, 1, :id], value: 2, resolved?: true)
        )
      end
    end

    context 'with terminal array value' do
      let(:options) { { expand_arrays: true } }
      let(:root) { { ids: [1, 2] } }
      let(:path) { [:ids] }

      it 'keeps the terminal array as a single value' do
        expect(references).to contain_exactly(
          have_attributes(path: [:ids], value: [1, 2], resolved?: true, normalized_value: [1, 2])
        )
      end
    end

    context 'with object traversal' do
      let(:options) { { call_methods: true } }
      let(:root) { { user: user } }
      let(:path) { %i[user active?] }
      let(:user) { user_class.new(active: true) }
      let(:user_class) do
        Struct.new(:active, keyword_init: true) do
          def active?
            active
          end
        end
      end

      it 'sends method segments to objects' do
        expect(references).to contain_exactly(
          have_attributes(path: %i[user active?], value: true, resolved?: true)
        )
      end
    end

    context 'with array method traversal' do
      let(:options) { { call_methods: true } }
      let(:root) { { items: [] } }
      let(:path) { %i[items empty?] }

      it 'sends method segments to arrays' do
        expect(references).to contain_exactly(
          have_attributes(path: %i[items empty?], value: true, resolved?: true)
        )
      end
    end
  end
end
