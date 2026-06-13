# frozen_string_literal: true

RSpec.describe OmniService::Dispatch do
  subject(:dispatch) { described_class.new(selector, branches, **options) }

  let(:selector) { :role }
  let(:branches) { { admin: admin_flow, editor: editor_flow } }
  let(:options) { {} }
  let(:admin_flow) { ->(params, **) { Dry::Monads::Success[params, selected: :admin] } }
  let(:editor_flow) { ->(params, **) { Dry::Monads::Success[params, selected: :editor] } }

  describe '.new' do
    context 'when branches are empty' do
      let(:branches) { {} }

      it 'raises constraint error' do
        expect { dispatch }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end

  describe '#call' do
    subject(:call) { dispatch.call(params, **context) }

    let(:params) { { title: 'Hello' } }
    let(:context) { { role: :admin } }

    context 'when selector matches a branch' do
      it 'runs the selected branch' do
        expect(call).to be_success & have_attributes(
          params: [params],
          context: { role: :admin, selected: :admin }
        )
      end
    end

    context 'when selector matches another branch' do
      let(:context) { { role: :editor } }

      it 'runs only that branch' do
        expect(call).to be_success & have_attributes(
          params: [params],
          context: { role: :editor, selected: :editor }
        )
      end
    end

    context 'when selected branch fails' do
      let(:admin_flow) { ->(_, **) { Dry::Monads::Failure(:admin_failed) } }

      it 'returns the selected branch failure' do
        expect(call).to be_failure & have_attributes(
          errors: [have_attributes(code: :admin_failed)]
        )
      end
    end

    context 'when selector does not match' do
      let(:context) { { role: :guest } }

      it 'returns an unhandled dispatch failure' do
        expect(call).to be_failure & have_attributes(
          params: [params],
          context: { role: :guest },
          errors: [have_attributes(code: :unhandled_dispatch, path: [:role])]
        )
      end
    end

    context 'when selector is missing' do
      let(:context) { {} }

      it 'returns an unhandled dispatch failure' do
        expect(call).to be_failure & have_attributes(
          params: [params],
          context: {},
          errors: [have_attributes(code: :unhandled_dispatch, path: [:role])]
        )
      end
    end

    context 'with nested selector path' do
      let(:selector) { %i[event type] }
      let(:context) { { event: { type: :admin } } }

      it 'resolves the selector through context' do
        expect(call).to be_success & have_attributes(
          params: [params],
          context: { event: { type: :admin }, selected: :admin }
        )
      end
    end

    context 'with selector path calling methods' do
      let(:selector) { %i[current_user role] }
      let(:context) { { current_user: user } }
      let(:user) { Struct.new(:role).new(:admin) }

      it 'calls public methods in selector path' do
        expect(call).to be_success & have_attributes(
          params: [params],
          context: { current_user: user, selected: :admin }
        )
      end
    end

    context 'with custom error code' do
      let(:options) { { code: :unknown_role } }
      let(:context) { { role: :guest } }

      it 'uses the configured code' do
        expect(call).to be_failure & have_attributes(
          errors: [have_attributes(code: :unknown_role, path: [:role])]
        )
      end
    end

    context 'with ambiguous selector references' do
      let(:selector) { %i[roles name] }
      let(:options) { { path: OmniService::Path.new(expand_arrays: true) } }
      let(:context) { { roles: [{ name: :admin }, { name: :editor }] } }

      it 'raises operation failure' do
        expect { call }.to raise_error(OmniService::OperationFailed) do |error|
          expect(error.operation_result).to be_failure & have_attributes(
            operation: dispatch,
            params: [params],
            context: { roles: [{ name: :admin }, { name: :editor }] },
            errors: [
              have_attributes(
                message: 'Dispatch selector [:roles, :name] resolved to multiple paths: ' \
                  '[[:roles, 0, :name], [:roles, 1, :name]]',
                path: %i[roles name]
              )
            ]
          )
        end
      end
    end
  end

  describe '#signature' do
    subject(:signature) { dispatch.signature }

    context 'when all branches have context-only signature' do
      let(:admin_flow) { ->(**) {} }
      let(:editor_flow) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when branches have different signatures' do
      let(:admin_flow) { ->(first, **) { Dry::Monads::Success(first) } }
      let(:editor_flow) { ->(first, second, **) { Dry::Monads::Success(first, second) } }

      it 'returns max' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when any branch has splat signature' do
      let(:admin_flow) { ->(*args, **) { Dry::Monads::Success(*args) } }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
