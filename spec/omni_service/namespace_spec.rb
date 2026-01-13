# frozen_string_literal: true

RSpec.describe OmniService::Namespace do
  subject(:namespace_component) { described_class.new(:author, author_component) }

  let(:author_component) { ->(params, **) { Dry::Monads::Success(received: params) } }

  describe '#call' do
    context 'when namespace key is present' do
      subject(:result) do
        namespace_component.call(
          { title: 'Hello World', author: { name: 'John', email: 'john@test.com' } },
          blog: 'tech'
        )
      end

      it 'extracts namespaced params and wraps context' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { name: 'John', email: 'john@test.com' } }],
          context: { blog: 'tech', author: { received: { name: 'John', email: 'john@test.com' } } }
        )
      end
    end

    context 'when namespace key is missing' do
      subject(:result) { namespace_component.call({ title: 'Hello World' }, blog: 'tech') }

      it 'returns failure with missing error' do
        expect(result).to be_failure & have_attributes(
          params: [{ title: 'Hello World' }],
          context: { blog: 'tech' },
          errors: [have_attributes(code: :missing, path: [:author])]
        )
      end
    end

    context 'when inner component uses namespaced context' do
      subject(:result) { namespace_component.call({ author: {} }, role: 'reader', author: { role: 'admin' }) }

      let(:author_component) { ->(_, **context) { Dry::Monads::Success(received_role: context[:role]) } }

      it 'merges namespaced context with priority for inner component' do
        expect(result).to be_success & have_attributes(
          params: [{ author: {} }],
          context: { role: 'reader', author: { role: 'admin', received_role: 'admin' } }
        )
      end
    end

    context 'when inner returns empty context' do
      subject(:result) { namespace_component.call({ author: {} }, blog: 'tech') }

      let(:author_component) { ->(_, **) { Dry::Monads::Success({}) } }

      it 'does not add namespace to context' do
        expect(result).to be_success & have_attributes(
          params: [{ author: {} }],
          context: { blog: 'tech' }
        )
      end
    end

    context 'with failing inner component' do
      let(:author_component) { ->(_, **) { Dry::Monads::Failure([{ code: :invalid, path: [:email] }]) } }

      context 'with single error' do
        subject(:result) { namespace_component.call({ author: { email: '' } }, blog: 'tech') }

        it 'prefixes error path with namespace and preserves context' do
          expect(result).to be_failure & have_attributes(
            params: [{ author: { email: '' } }],
            context: { blog: 'tech' },
            errors: [have_attributes(code: :invalid, path: %i[author email])]
          )
        end
      end

      context 'with empty error path' do
        subject(:result) { namespace_component.call({ author: {} }) }

        let(:author_component) { ->(_, **) { Dry::Monads::Failure([{ code: :not_found, path: [] }]) } }

        it 'prefixes with namespace only' do
          expect(result).to be_failure & have_attributes(
            params: [{ author: {} }],
            context: {},
            errors: [have_attributes(code: :not_found, path: [:author])]
          )
        end
      end

      context 'with multiple errors' do
        subject(:result) { namespace_component.call({ author: {} }) }

        let(:author_component) do
          ->(_, **) { Dry::Monads::Failure([{ code: :blank, path: [:name] }, { code: :invalid_format, path: [:email] }]) }
        end

        it 'prefixes all error paths' do
          expect(result).to be_failure & have_attributes(
            params: [{ author: {} }],
            context: {},
            errors: [
              have_attributes(code: :blank, path: %i[author name]),
              have_attributes(code: :invalid_format, path: %i[author email])
            ]
          )
        end
      end
    end

    context 'with multi-param component' do
      let(:author_component) { ->(first, second, **) { Dry::Monads::Success(first: first, second: second) } }

      context 'when both params have namespace key' do
        subject(:result) do
          namespace_component.call(
            { title: 'Hello', author: { name: 'John' } },
            { metadata: 'extra', author: { bio: 'Writer' } }
          )
        end

        it 'extracts namespace from each param and wraps result' do
          expect(result).to be_success & have_attributes(
            params: [{ author: { name: 'John' } }, { author: { bio: 'Writer' } }],
            context: { author: { first: { name: 'John' }, second: { bio: 'Writer' } } }
          )
        end
      end

      context 'when second param lacks namespace key' do
        subject(:result) { namespace_component.call({ author: { name: 'John' } }, { other_data: 'value' }) }

        it 'wraps all inner params including passed-through ones' do
          expect(result).to be_success & have_attributes(
            params: [{ author: { name: 'John' } }, { author: { other_data: 'value' } }],
            context: { author: { first: { name: 'John' }, second: { other_data: 'value' } } }
          )
        end
      end
    end

    context 'with sequential namespaces on same key' do
      subject(:result) { pipeline.call({ author: { name: 'John' } }) }

      let(:stage1) { ->(params, **) { Dry::Monads::Success[params.merge(param1: 1), context1: 1] } }
      let(:stage2) { ->(params, **) { Dry::Monads::Success[params.merge(param2: 2), context2: 2] } }
      let(:stage3) { ->(params, **) { Dry::Monads::Success[params.merge(param1: 3, param3: 3), context1: 3] } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:author, stage1),
          described_class.new(:author, stage2),
          described_class.new(:author, stage3)
        )
      end

      it 'deep merges context from multiple namespace calls' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { name: 'John', param1: 3, param2: 2, param3: 3 } }],
          context: { author: { context1: 3, context2: 2 } }
        )
      end
    end

    context 'with deep namespace path' do
      subject(:result) { pipeline.call({ user: { profile: { name: 'John' } } }) }

      let(:component1) { ->(params, **) { Dry::Monads::Success[params.merge(param1: 1), context1: 1] } }
      let(:component2) { ->(params, **) { Dry::Monads::Success[params.merge(param2: 2), context2: 2] } }
      let(:component3) { ->(params, **) { Dry::Monads::Success[params.merge(param3: 3), context1: 3] } }
      let(:component4) { ->(params, **) { Dry::Monads::Success[params.merge(param4: 4), context4: 4] } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(%i[user profile], component1),
          described_class.new(:user, component2),
          described_class.new(:user, described_class.new(:profile, component3)),
          described_class.new(%i[user profile], component4)
        )
      end

      it 'deep merges context and wraps params from all namespace styles' do
        expect(result).to be_success & have_attributes(
          params: [{ user: { profile: { name: 'John', param1: 1, param3: 3, param4: 4 } } }],
          context: {
            user: {
              context2: 2,
              profile: { context1: 3, context4: 4 }
            }
          }
        )
      end
    end

    context 'with sequential namespaces where first transforms params' do
      subject(:result) { pipeline.call({ nested: { name: 'John', extra: 'filtered' } }) }

      let(:filter_component) do
        # Component that returns Result with transformed params (like Params does)
        Class.new do
          def call(params, **)
            filtered = params.slice(:name)
            OmniService::Result.build(self, params: [filtered], context: filtered)
          end
        end.new
      end
      let(:receive_component) { ->(params, **) { Dry::Monads::Success(received: params) } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:nested, filter_component),
          described_class.new(:nested, receive_component)
        )
      end

      it 'passes transformed params to second namespace' do
        expect(result).to be_success & have_attributes(
          params: [{ nested: { name: 'John' } }],
          context: { nested: { name: 'John', received: { name: 'John' } } }
        )
      end
    end

    context 'when inner component returns fewer params than received' do
      subject(:result) { namespace_component.call({ author: { a: 1 } }, { author: { b: 2 } }) }

      let(:author_component) do
        # Component accepts 2 params but returns only 1
        Class.new do
          def call(first, _second, **)
            OmniService::Result.build(self, params: [first.merge(transformed: true)], context: {})
          end
        end.new
      end

      it 'wraps only what inner returns' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { a: 1, transformed: true } }]
        )
      end
    end

    context 'when inner component returns more params than received (parallel inside)' do
      subject(:result) { namespace_component.call({ author: { x: 1 }, other: 'kept' }) }

      let(:author_component) do
        # Component returns multiple params (like parallel does)
        Class.new do
          def call(_, **)
            OmniService::Result.build(self, params: [{ a: 1 }, { b: 2 }, { c: 3 }], context: {})
          end
        end.new
      end

      it 'wraps each inner param with namespace' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { a: 1 } }, { author: { b: 2 } }, { author: { c: 3 } }]
        )
      end
    end

    context 'with nested namespaces' do
      subject(:namespace_component) { described_class.new(:author, address_namespace) }

      let(:address_component) { ->(params, **) { Dry::Monads::Success(address: params) } }
      let(:address_namespace) { described_class.new(:address, address_component) }

      context 'when successful' do
        subject(:result) do
          namespace_component.call({
            title: 'Hello',
            author: { name: 'John', address: { city: 'NYC', zip: '10001' } }
          })
        end

        it 'properly nests params extraction and context wrapping' do
          expect(result).to be_success & have_attributes(
            params: [{ author: { address: { city: 'NYC', zip: '10001' } } }],
            context: { author: { address: { address: { city: 'NYC', zip: '10001' } } } }
          )
        end
      end

      context 'with failing inner component' do
        subject(:result) { namespace_component.call({ author: { address: {} } }) }

        let(:address_component) { ->(_, **) { Dry::Monads::Failure([{ code: :invalid, path: [:zip] }]) } }

        it 'properly nests error paths' do
          expect(result).to be_failure & have_attributes(
            params: [{ author: { address: {} } }],
            context: {},
            errors: [have_attributes(code: :invalid, path: %i[author address zip])]
          )
        end
      end
    end
  end

  describe 'from: []' do
    subject(:namespace_component) { described_class.new(:author, author_component, from: []) }

    context 'when successful' do
      subject(:result) { namespace_component.call({ title: 'Hello', author: { name: 'John' } }, blog: 'tech') }

      it 'passes full params and wraps result under namespace' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { title: 'Hello', author: { name: 'John' } } }],
          context: { blog: 'tech', author: { received: { title: 'Hello', author: { name: 'John' } } } }
        )
      end
    end

    context 'without namespace key in params' do
      subject(:result) { namespace_component.call({ some: 'test' }) }

      it 'still wraps result under namespace key' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { some: 'test' } }],
          context: { author: { received: { some: 'test' } } }
        )
      end
    end

    context 'with failing inner component' do
      subject(:result) { namespace_component.call({ some: 'test' }) }

      let(:author_component) { ->(_, **) { Dry::Monads::Failure([{ code: :invalid, path: [:name] }]) } }

      it 'prefixes error paths with namespace' do
        expect(result).to be_failure & have_attributes(
          params: [{ author: { some: 'test' } }],
          context: {},
          errors: [have_attributes(code: :invalid, path: %i[author name])]
        )
      end
    end

    context 'with sequential shared params namespaces' do
      subject(:result) { pipeline.call({ address: '123 Main St' }) }

      let(:preorder_component) { ->(params, **) { Dry::Monads::Success(order: { type: :preorder, **params }) } }
      let(:in_stock_component) { ->(params, **) { Dry::Monads::Success(order: { type: :in_stock, **params }) } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:preorder, preorder_component, from: []),
          described_class.new(:in_stock, in_stock_component, from: [])
        )
      end

      it 'each namespace wraps its result, sequence sees first namespace params' do
        expect(result).to be_success & have_attributes(
          params: [{ in_stock: { preorder: { address: '123 Main St' } } }],
          context: {
            preorder: { order: { type: :preorder, address: '123 Main St' } },
            in_stock: { order: { type: :in_stock, preorder: { address: '123 Main St' } } }
          }
        )
      end
    end
  end

  describe 'optional: true' do
    subject(:namespace_component) { described_class.new(:author, author_component, optional: true) }

    context 'when namespace key is present' do
      subject(:result) { namespace_component.call({ title: 'Hello', author: { name: 'John' } }, blog: 'tech') }

      it 'calls the component and wraps result' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { name: 'John' } }],
          context: { blog: 'tech', author: { received: { name: 'John' } } }
        )
      end
    end

    context 'when namespace key is missing' do
      subject(:result) { namespace_component.call({ title: 'Hello' }, blog: 'tech') }

      it 'skips the component and returns success with unchanged params and context' do
        expect(result).to be_success & have_attributes(
          params: [{ title: 'Hello' }],
          context: { blog: 'tech' }
        )
      end
    end

    context 'when params are empty' do
      subject(:result) { namespace_component.call({}, blog: 'tech') }

      it 'skips the component' do
        expect(result).to be_success & have_attributes(
          params: [{}],
          context: { blog: 'tech' }
        )
      end
    end

    context 'with from: []' do
      subject(:result) { namespace_component.call({ title: 'Hello' }, blog: 'tech') }

      let(:namespace_component) do
        described_class.new(:author, author_component, optional: true, from: [])
      end

      it 'always calls component since no from key to check' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { title: 'Hello' } }],
          context: { blog: 'tech', author: { received: { title: 'Hello' } } }
        )
      end
    end

    context 'with multi-param component' do
      let(:author_component) { ->(first, second, **) { Dry::Monads::Success(first: first, second: second) } }

      context 'when namespace key is in second param only' do
        subject(:result) { namespace_component.call({ other: 'data' }, { author: { bio: 'Writer' } }) }

        it 'calls the component and wraps all params' do
          expect(result).to be_success & have_attributes(
            params: [{ author: { other: 'data' } }, { author: { bio: 'Writer' } }],
            context: { author: { first: { other: 'data' }, second: { bio: 'Writer' } } }
          )
        end
      end

      context 'when namespace key is in neither param' do
        subject(:result) { namespace_component.call({ other: 'data' }, { more: 'info' }) }

        it 'skips the component' do
          expect(result).to be_success & have_attributes(
            params: [{ other: 'data' }, { more: 'info' }],
            context: {}
          )
        end
      end
    end

    context 'with failing inner component' do
      let(:author_component) { ->(_, **) { Dry::Monads::Failure([{ code: :invalid, path: [:email] }]) } }

      context 'when namespace key is present' do
        subject(:result) { namespace_component.call({ author: { email: '' } }, blog: 'tech') }

        it 'returns failure with prefixed errors' do
          expect(result).to be_failure & have_attributes(
            params: [{ author: { email: '' } }],
            context: { blog: 'tech' },
            errors: [have_attributes(code: :invalid, path: %i[author email])]
          )
        end
      end

      context 'when namespace key is missing' do
        subject(:result) { namespace_component.call({ title: 'Hello' }, blog: 'tech') }

        it 'skips the component and returns success' do
          expect(result).to be_success & have_attributes(
            params: [{ title: 'Hello' }],
            context: { blog: 'tech' }
          )
        end
      end
    end

    context 'with sequence containing non-optional namespace' do
      subject(:result) { pipeline.call({ author: { name: 'John' } }) }

      let(:validate_component) { ->(_, **) { Dry::Monads::Success(validated: true) } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:author, validate_component),
          described_class.new(:metadata, author_component, optional: true)
        )
      end

      it 'processes required namespace and skips optional one' do
        expect(result).to be_success & have_attributes(
          params: [{ author: { name: 'John' } }],
          context: { author: { validated: true } }
        )
      end
    end
  end

  describe '#signature' do
    subject(:signature) { namespace_component.signature }

    context 'with shared_params: false (default)' do
      it 'always returns 1 regardless of inner component' do
        expect(described_class.new(:author, ->(**) {}).signature).to eq([1, true])
        expect(described_class.new(:author, ->(first, **) {}).signature).to eq([1, true])
        expect(described_class.new(:author, ->(first, second, **) {}).signature).to eq([1, true])
        expect(described_class.new(:author, ->(first, second = nil, **) {}).signature).to eq([1, true])
        expect(described_class.new(:author, ->(*params, **) {}).signature).to eq([1, true])
      end
    end

    context 'with from: []' do
      subject(:namespace_component) { described_class.new(:author, author_component, from: []) }

      context 'when component has context-only signature' do
        let(:author_component) { ->(**) {} }

        it 'returns zero params' do
          expect(signature).to eq([0, true])
        end
      end

      context 'when component has single param' do
        let(:author_component) { ->(param, **) {} }

        it 'returns param count' do
          expect(signature).to eq([1, true])
        end
      end

      context 'when component has multiple params without context' do
        let(:author_component) { ->(first, second) {} }

        it 'returns param count with context forced true' do
          expect(signature).to eq([2, true])
        end
      end

      context 'when component has optional params' do
        let(:author_component) { ->(first, second = nil, **) {} }

        it 'returns total param count including optional' do
          expect(signature).to eq([2, true])
        end
      end

      context 'when component has splat signature' do
        let(:author_component) { ->(*params, **) {} }

        it 'returns nil for params count' do
          expect(signature).to eq([nil, true])
        end
      end

      context 'when component has required param and splat' do
        let(:author_component) { ->(first, *rest, **) {} }

        it 'returns nil for params count' do
          expect(signature).to eq([nil, true])
        end
      end
    end
  end
end
