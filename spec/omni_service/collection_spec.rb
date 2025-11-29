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
    it 'returns a result' do
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
end
