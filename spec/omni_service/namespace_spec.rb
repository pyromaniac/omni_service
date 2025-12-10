# frozen_string_literal: true

RSpec.describe OmniService::Namespace do
  subject(:namespace_component) { described_class.new(:author, author_component) }

  let(:author_component) { ->(params, **) { Dry::Monads::Success(author: params) } }

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
          params: [{ title: 'Hello World', author: { name: 'John', email: 'john@test.com' } }],
          context: { blog: 'tech', author: { author: { name: 'John', email: 'john@test.com' } } }
        )
      end
    end

    context 'when namespace key is missing' do
      subject(:result) { namespace_component.call({ title: 'Hello World' }, blog: 'tech') }

      it 'passes through params unchanged' do
        expect(result).to be_success & have_attributes(
          params: [{ title: 'Hello World' }],
          context: { blog: 'tech', author: { author: { title: 'Hello World' } } }
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

      let(:author_component) { ->(_params, **) { Dry::Monads::Success({}) } }

      it 'does not add namespace to context' do
        expect(result).to be_success & have_attributes(
          params: [{ author: {} }],
          context: { blog: 'tech' }
        )
      end
    end

    context 'with failing inner component' do
      let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:email] }]) } }

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

        let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :not_found, path: [] }]) } }

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
          ->(_params, **) { Dry::Monads::Failure([{ code: :blank, path: [:name] }, { code: :invalid_format, path: [:email] }]) }
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

        it 'extracts namespace from each param' do
          expect(result).to be_success & have_attributes(
            params: [{ title: 'Hello', author: { name: 'John' } }, { metadata: 'extra', author: { bio: 'Writer' } }],
            context: { author: { first: { name: 'John' }, second: { bio: 'Writer' } } }
          )
        end
      end

      context 'when second param lacks namespace key' do
        subject(:result) { namespace_component.call({ author: { name: 'John' } }, { other_data: 'value' }) }

        it 'leaves param without namespace key unchanged' do
          expect(result).to be_success & have_attributes(
            params: [{ author: { name: 'John' } }, { other_data: 'value' }],
            context: { author: { first: { name: 'John' }, second: { other_data: 'value' } } }
          )
        end
      end
    end

    context 'with sequential namespaces on same key' do
      subject(:result) { pipeline.call({ title: 'Hello', author: { name: 'John' } }) }

      let(:validate_component) { ->(_params, **) { Dry::Monads::Success(validated: true, role: 'contributor') } }
      let(:create_component) do
        ->(params, validated:, role:, **) { Dry::Monads::Success(author: { **params, role: role, validated: validated }) }
      end
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:author, validate_component),
          described_class.new(:author, create_component)
        )
      end

      it 'accumulates context from multiple namespace calls' do
        expect(result).to be_success & have_attributes(
          params: [{ title: 'Hello', author: { name: 'John' } }],
          context: {
            author: {
              validated: true,
              role: 'contributor',
              author: { name: 'John', role: 'contributor', validated: true }
            }
          }
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
            params: [{ title: 'Hello', author: { name: 'John', address: { city: 'NYC', zip: '10001' } } }],
            context: { author: { address: { address: { city: 'NYC', zip: '10001' } } } }
          )
        end
      end

      context 'with failing inner component' do
        subject(:result) { namespace_component.call({ author: { address: {} } }) }

        let(:address_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:zip] }]) } }

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

  describe 'shared_params: true' do
    subject(:namespace_component) { described_class.new(:author, author_component, shared_params: true) }

    context 'when successful' do
      subject(:result) { namespace_component.call({ title: 'Hello', author: { name: 'John' } }, blog: 'tech') }

      it 'passes full params and wraps context under namespace' do
        expect(result).to be_success & have_attributes(
          params: [{ title: 'Hello', author: { name: 'John' } }],
          context: { blog: 'tech', author: { author: { title: 'Hello', author: { name: 'John' } } } }
        )
      end
    end

    context 'without namespace key in params' do
      subject(:result) { namespace_component.call({ data: 'test' }) }

      it 'still wraps context under namespace key' do
        expect(result).to be_success & have_attributes(
          params: [{ data: 'test' }],
          context: { author: { author: { data: 'test' } } }
        )
      end
    end

    context 'with failing inner component' do
      subject(:result) { namespace_component.call({ data: 'test' }) }

      let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:name] }]) } }

      it 'prefixes error paths with namespace' do
        expect(result).to be_failure & have_attributes(
          params: [{ data: 'test' }],
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
          described_class.new(:preorder, preorder_component, shared_params: true),
          described_class.new(:in_stock, in_stock_component, shared_params: true)
        )
      end

      it 'both namespaces receive same params' do
        expect(result).to be_success & have_attributes(
          params: [{ address: '123 Main St' }],
          context: {
            preorder: { order: { type: :preorder, address: '123 Main St' } },
            in_stock: { order: { type: :in_stock, address: '123 Main St' } }
          }
        )
      end
    end
  end

  describe 'optional: true' do
    subject(:namespace_component) { described_class.new(:author, author_component, optional: true) }

    context 'when namespace key is present' do
      subject(:result) { namespace_component.call({ title: 'Hello', author: { name: 'John' } }, blog: 'tech') }

      it 'calls the component and processes normally' do
        expect(result).to be_success & have_attributes(
          params: [{ title: 'Hello', author: { name: 'John' } }],
          context: { blog: 'tech', author: { author: { name: 'John' } } }
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

    context 'with shared_params: true' do
      subject(:namespace_component) do
        described_class.new(:author, author_component, optional: true, shared_params: true)
      end

      context 'when namespace key is missing' do
        subject(:result) { namespace_component.call({ title: 'Hello' }, blog: 'tech') }

        it 'skips the component' do
          expect(result).to be_success & have_attributes(
            params: [{ title: 'Hello' }],
            context: { blog: 'tech' }
          )
        end
      end

      context 'when namespace key is present' do
        subject(:result) { namespace_component.call({ title: 'Hello', author: { name: 'John' } }, blog: 'tech') }

        it 'calls the component with full params' do
          expect(result).to be_success & have_attributes(
            params: [{ title: 'Hello', author: { name: 'John' } }],
            context: { blog: 'tech', author: { author: { title: 'Hello', author: { name: 'John' } } } }
          )
        end
      end
    end

    context 'with multi-param component' do
      let(:author_component) { ->(first, second, **) { Dry::Monads::Success(first: first, second: second) } }

      context 'when namespace key is in second param only' do
        subject(:result) { namespace_component.call({ other: 'data' }, { author: { bio: 'Writer' } }) }

        it 'calls the component' do
          expect(result).to be_success & have_attributes(
            params: [{ other: 'data' }, { author: { bio: 'Writer' } }],
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
      let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:email] }]) } }

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

      let(:validate_component) { ->(_params, **) { Dry::Monads::Success(validated: true) } }
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

    context 'with context-accepting component' do
      let(:author_component) { ->(_params, **) { Dry::Monads::Success({}) } }

      it 'delegates to inner component' do
        expect(signature).to eq([1, true])
      end
    end

    context 'with context-less component' do
      let(:author_component) { ->(params) { Dry::Monads::Success(author: params) } }

      it 'handles components without context' do
        expect(signature).to eq([1, false])
      end
    end
  end
end
