# frozen_string_literal: true

RSpec.describe OmniService::Namespace do
  describe '#call' do
    context 'with successful inner component' do
      let(:author_component) { ->(params, **) { Dry::Monads::Success(author: params) } }
      let(:namespace_component) { described_class.new(:author, author_component) }

      it 'extracts namespaced params and wraps context' do
        result = namespace_component.call(
          { title: 'Hello World', author: { name: 'John', email: 'john@test.com' } },
          blog: 'tech'
        )

        expect(result).to be_a(OmniService::Result) & have_attributes(
          params: [{ title: 'Hello World', author: { name: 'John', email: 'john@test.com' } }],
          context: { blog: 'tech', author: { author: { name: 'John', email: 'john@test.com' } } },
          errors: []
        )
      end

      it 'passes through params when namespace key is missing' do
        result = namespace_component.call({ title: 'Hello World' }, blog: 'tech')

        expect(result).to be_a(OmniService::Result) & have_attributes(
          params: [{ title: 'Hello World' }],
          context: { blog: 'tech', author: { author: { title: 'Hello World' } } },
          errors: []
        )
      end

      context 'when inner component uses namespaced context' do
        let(:author_component) { ->(_, **context) { Dry::Monads::Success(received_role: context[:role]) } }

        it 'merges namespaced context with priority for inner component' do
          result = namespace_component.call(
            { author: {} },
            role: 'reader', author: { role: 'admin' }
          )

          expect(result.context).to eq({ role: 'reader', author: { role: 'admin', received_role: 'admin' } })
        end
      end

      context 'when inner returns empty context' do
        let(:author_component) { ->(_params, **) { Dry::Monads::Success({}) } }

        it 'returns empty context' do
          result = namespace_component.call({ author: {} }, blog: 'tech')

          expect(result.context).to eq({ blog: 'tech' })
        end
      end
    end

    context 'with failing inner component' do
      let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:email] }]) } }
      let(:namespace_component) { described_class.new(:author, author_component) }

      it 'prefixes error paths with namespace' do
        result = namespace_component.call({ author: { email: '' } })

        expect(result).to be_a(OmniService::Result) & have_attributes(
          errors: [have_attributes(code: :invalid, path: %i[author email])]
        )
      end

      it 'preserves outer context on failure' do
        result = namespace_component.call({ author: {} }, blog: 'tech')

        expect(result.context).to eq({ blog: 'tech' })
      end

      context 'with empty error path' do
        let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :not_found, path: [] }]) } }

        it 'prefixes with namespace only' do
          result = namespace_component.call({ author: {} })

          expect(result.errors).to match([have_attributes(code: :not_found, path: [:author])])
        end
      end

      context 'with multiple errors' do
        let(:author_component) do
          ->(_params, **) { Dry::Monads::Failure([{ code: :blank, path: [:name] }, { code: :invalid_format, path: [:email] }]) }
        end

        it 'prefixes all error paths' do
          result = namespace_component.call({ author: {} })

          expect(result.errors).to match([
            have_attributes(code: :blank, path: %i[author name]),
            have_attributes(code: :invalid_format, path: %i[author email])
          ])
        end
      end
    end

    context 'with multi-param component' do
      let(:author_component) { ->(first, second, **) { Dry::Monads::Success(first: first, second: second) } }
      let(:namespace_component) { described_class.new(:author, author_component) }

      it 'extracts namespace from each param based on signature' do
        result = namespace_component.call(
          { title: 'Hello', author: { name: 'John' } },
          { metadata: 'extra', author: { bio: 'Writer' } }
        )

        expect(result.context).to eq({
          author: { first: { name: 'John' }, second: { bio: 'Writer' } }
        })
      end

      it 'leaves params without namespace key unchanged' do
        result = namespace_component.call(
          { author: { name: 'John' } },
          { other_data: 'value' }
        )

        expect(result.context).to eq({
          author: { first: { name: 'John' }, second: { other_data: 'value' } }
        })
      end
    end

    context 'with sequential namespaces on same key' do
      let(:validate_component) { ->(_params, **) { Dry::Monads::Success(validated: true, role: 'contributor') } }
      let(:create_component) { ->(params, validated:, role:, **) { Dry::Monads::Success(author: { **params, role: role, validated: validated }) } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:author, validate_component),
          described_class.new(:author, create_component)
        )
      end

      it 'accumulates context from multiple namespace calls' do
        result = pipeline.call({ title: 'Hello', author: { name: 'John' } })

        expect(result.context).to eq({
          author: {
            validated: true,
            role: 'contributor',
            author: { name: 'John', role: 'contributor', validated: true }
          }
        })
      end
    end

    context 'with nested namespaces' do
      let(:address_component) { ->(params, **) { Dry::Monads::Success(address: params) } }
      let(:address_namespace) { described_class.new(:address, address_component) }
      let(:author_namespace) { described_class.new(:author, address_namespace) }

      it 'properly nests params extraction and context wrapping' do
        result = author_namespace.call({
          title: 'Hello',
          author: { name: 'John', address: { city: 'NYC', zip: '10001' } }
        })

        expect(result.context).to eq({
          author: { address: { address: { city: 'NYC', zip: '10001' } } }
        })
      end

      context 'with failing inner component' do
        let(:address_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:zip] }]) } }

        it 'properly nests error paths' do
          result = author_namespace.call({ author: { address: {} } })

          expect(result.errors).to match([have_attributes(code: :invalid, path: %i[author address zip])])
        end
      end
    end
  end

  describe 'shared_params: true' do
    let(:author_component) { ->(params, **) { Dry::Monads::Success(author: params) } }
    let(:namespace_component) { described_class.new(:author, author_component, shared_params: true) }

    it 'passes params through unchanged' do
      result = namespace_component.call(
        { title: 'Hello', author: { name: 'John' } },
        blog: 'tech'
      )

      expect(result.context).to eq({
        blog: 'tech',
        author: { author: { title: 'Hello', author: { name: 'John' } } }
      })
    end

    it 'still wraps context under namespace key' do
      result = namespace_component.call({ data: 'test' })

      expect(result.context).to eq({ author: { author: { data: 'test' } } })
    end

    context 'with failing inner component' do
      let(:author_component) { ->(_params, **) { Dry::Monads::Failure([{ code: :invalid, path: [:name] }]) } }

      it 'still prefixes error paths with namespace' do
        result = namespace_component.call({ data: 'test' })

        expect(result.errors).to match([have_attributes(code: :invalid, path: %i[author name])])
      end
    end

    context 'with sequential shared params namespaces' do
      let(:preorder_component) { ->(params, **) { Dry::Monads::Success(order: { type: :preorder, **params }) } }
      let(:in_stock_component) { ->(params, **) { Dry::Monads::Success(order: { type: :in_stock, **params }) } }
      let(:pipeline) do
        OmniService::Sequence.new(
          described_class.new(:preorder, preorder_component, shared_params: true),
          described_class.new(:in_stock, in_stock_component, shared_params: true)
        )
      end

      it 'both namespaces receive same params' do
        result = pipeline.call({ address: '123 Main St' })

        expect(result.context).to eq({
          preorder: { order: { type: :preorder, address: '123 Main St' } },
          in_stock: { order: { type: :in_stock, address: '123 Main St' } }
        })
      end
    end
  end

  describe '#signature' do
    context 'with context-accepting component' do
      let(:author_component) { ->(_params, **) { Dry::Monads::Success({}) } }
      let(:namespace_component) { described_class.new(:author, author_component) }

      it 'delegates to inner component' do
        expect(namespace_component.signature).to eq([1, true])
      end
    end

    context 'with context-less component' do
      let(:author_component) { ->(params) { Dry::Monads::Success(author: params) } }
      let(:namespace_component) { described_class.new(:author, author_component) }

      it 'handles components without context' do
        expect(namespace_component.signature).to eq([1, false])
      end
    end
  end
end
