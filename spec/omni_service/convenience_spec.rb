# frozen_string_literal: true

RSpec.describe OmniService::Convenience do
  let(:operation_class) do
    Class.new do
      extend OmniService::Convenience
    end
  end

  describe '#schema' do
    subject(:result) { validator.call(input) }

    let(:input) { { name: 'John' } }
    let(:validator) do
      operation_class.schema do
        params do
          required(:name).filled(:string)
        end
      end
    end

    it 'builds a validator from contract DSL' do
      expect(result).to be_success & have_attributes(
        params: [{ name: 'John' }],
        errors: []
      )
    end
  end

  describe '#params' do
    subject(:result) { validator.call(input) }

    let(:input) { { name: 'John' } }
    let(:validator) { operation_class.params { required(:name).filled(:string) } }

    it 'builds a params shorthand validator' do
      expect(result).to be_success & have_attributes(
        params: [{ name: 'John' }],
        errors: []
      )
    end
  end

  describe '#assert' do
    subject(:assert_component) { operation_class.assert(:authorized, code: :unauthorized) }

    it 'builds an assert component' do
      expect(assert_component).to be_a(OmniService::Assert) & have_attributes(
        predicate: [:authorized],
        code: :unauthorized
      )
    end
  end

  describe '#refute' do
    subject(:refute_component) { operation_class.refute(:archived, code: :already_archived) }

    it 'builds a refute component' do
      expect(refute_component).to be_a(OmniService::Refute) & have_attributes(
        predicate: [:archived],
        code: :already_archived
      )
    end
  end

  describe '#remap' do
    subject(:remap_component) { operation_class.remap(current_account: :account) }

    it 'builds a remap component' do
      expect(remap_component).to be_a(OmniService::Remap) & have_attributes(
        mapping: { current_account: :account }
      )
    end
  end

  describe '#dispatch' do
    subject(:dispatch_component) { operation_class.dispatch(:role, admin: admin_flow) }

    let(:admin_flow) { ->(_, **) { Dry::Monads::Success(selected: :admin) } }

    it 'builds a dispatch component' do
      expect(dispatch_component).to be_a(OmniService::Dispatch) & have_attributes(
        selector: [:role],
        branches: { admin: admin_flow },
        code: :unhandled_dispatch
      )
    end

    context 'with custom code' do
      subject(:dispatch_component) { operation_class.dispatch(:role, :unknown_role, admin: admin_flow) }

      it 'passes the code to dispatch' do
        expect(dispatch_component).to be_a(OmniService::Dispatch) & have_attributes(
          selector: [:role],
          branches: { admin: admin_flow },
          code: :unknown_role
        )
      end
    end

    context 'with nil code' do
      subject(:dispatch_component) { operation_class.dispatch(:role, nil, admin: admin_flow) }

      it 'uses the default code' do
        expect(dispatch_component).to be_a(OmniService::Dispatch) & have_attributes(
          selector: [:role],
          branches: { admin: admin_flow },
          code: :unhandled_dispatch
        )
      end
    end
  end
end
