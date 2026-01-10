# frozen_string_literal: true

RSpec.describe OmniService::Collection do
  let(:component) do
    lambda do |params, **context|
      OmniService::Result.build(
        -> {},
        params: [params.transform_values(&:to_s)],
        context: context.merge(d: context[:b].to_i + context[:c]),
        errors: params.key?(:a) ? [] : [OmniService::Error.build(-> {}, code: :missing, path: [:a])]
      )
    end
  end
  let(:collection) { described_class.new(component, namespace: :foo) }

  describe '#call' do
    context 'with array collection' do
      it 'iterates with indices' do
        expect(collection.call({ foo: [{ a: 1 }, {}, { a: 3 }] }, foo: [{ b: 4 }, { b: 5 }], c: 6))
          .to be_a(OmniService::Result) & have_attributes(
            operation: collection,
            params: [{ foo: [{ a: '1' }, {}, { a: '3' }] }],
            context: { foo: [{ c: 6, b: 4, d: 10 }, { c: 6, b: 5, d: 11 }, { c: 6, d: 6 }], c: 6 },
            errors: [
              have_attributes(code: :missing, path: [:foo, 1, :a])
            ]
          )
      end
    end

    context 'with hash collection' do
      it 'iterates with keys' do
        expect(collection.call({ foo: { x: { a: 1 }, y: {}, z: { a: 3 } } }, foo: { x: { b: 4 }, y: { b: 5 } }, c: 6))
          .to be_a(OmniService::Result) & have_attributes(
            operation: collection,
            params: [{ foo: { x: { a: '1' }, y: {}, z: { a: '3' } } }],
            context: { foo: { x: { c: 6, b: 4, d: 10 }, y: { c: 6, b: 5, d: 11 }, z: { c: 6, d: 6 } }, c: 6 },
            errors: [
              have_attributes(code: :missing, path: %i[foo y a])
            ]
          )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { collection.signature }

    context 'when component has context-only signature' do
      let(:component) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when component has single param' do
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
