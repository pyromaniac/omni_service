# frozen_string_literal: true

RSpec.describe OmniService::Transaction do
  subject(:transaction) { described_class.new(component, on_success: on_success, on_failure: on_failure) }

  let(:test_simple_repository) { TestRepository.new(TestSimple) }
  let(:on_success) { [->(_, **) { test_simple_repository.create(name: 'on_success') }] }
  let(:on_failure) { [->(_, **) { test_simple_repository.create(name: 'on_failure') }] }

  describe '#call' do
    subject(:result) { transaction.call({}) }

    context 'when the component returns Success' do
      let(:component) { ->(_, **) { test_simple_repository.create(name: 'component') } }

      it 'returns a result' do
        expect { result }.to change { TestSimple.order(:id).pluck(:name) }.from([]).to(%w[component on_success])
        expect(result).to be_a(OmniService::Result) & have_attributes(
          operation: transaction,
          shortcut: nil,
          params: [{}],
          context: { test_simple: have_attributes(name: 'component') },
          errors: [],
          on_success: [an_instance_of(OmniService::Result) & have_attributes(
            operation: on_success.first,
            shortcut: nil,
            params: [{}],
            context: { test_simple: have_attributes(name: 'on_success') },
            errors: [],
            on_success: [],
            on_failure: []
          )],
          on_failure: []
        )
      end

      context 'when the on_success callback fails' do
        let(:on_success) do
          [
            ->(_, **) { test_simple_repository.create(name: 'on_success1') },
            lambda { |_, **|
              test_simple_repository.create(name: 'on_success2')
              Dry::Monads::Failure(:invalid)
            },
            ->(_, **) { test_simple_repository.create(name: 'on_success3') }
          ]
        end

        it 'returns a result' do
          expect { result }.to change { TestSimple.order(:id).pluck(:name) }
            .from([]).to(%w[component on_success3 on_success2 on_success1])
          expect(result).to be_a(OmniService::Result) & have_attributes(
            operation: transaction,
            shortcut: nil,
            params: [{}],
            context: { test_simple: have_attributes(name: 'component') },
            errors: [],
            on_success: [
              an_instance_of(OmniService::Result) & have_attributes(
                operation: on_success.first,
                shortcut: nil,
                params: [{}],
                context: { test_simple: have_attributes(name: 'on_success1') },
                errors: [],
                on_success: [],
                on_failure: []
              ),
              an_instance_of(OmniService::Result) & have_attributes(
                operation: on_success.second,
                shortcut: nil,
                params: [{}],
                context: { test_simple: have_attributes(name: 'component') },
                errors: [have_attributes(message: nil, code: :invalid, path: [], tokens: {})],
                on_success: [],
                on_failure: []
              ),
              an_instance_of(OmniService::Result) & have_attributes(
                operation: on_success.third,
                shortcut: nil,
                params: [{}],
                context: { test_simple: have_attributes(name: 'on_success3') },
                errors: [],
                on_success: [],
                on_failure: []
              )
            ],
            on_failure: []
          )
        end
      end

      context 'when the on_success callback raises an exception' do
        let(:on_success) do
          [
            ->(_, **) { test_simple_repository.create(name: 'on_success1') },
            lambda { |_, **|
              test_simple_repository.create(name: 'on_success2')
              raise 'on_success failed'
            },
            ->(_, **) { test_simple_repository.create(name: 'on_success3') }
          ]
        end

        it 'returns a result' do
          expect { result }
            .to change { TestSimple.order(:id).pluck(:name) }
            .from([]).to(%w[component on_success3 on_success2 on_success1])
            .and raise_error('on_success failed')
        end
      end

      context 'with nested transactions' do
        let(:component) do
          described_class.new(
            nested_component,
            on_success: nested_on_success,
            on_failure: nested_on_failure
          )
        end
        let(:nested_component) { ->(_, **) { test_simple_repository.create(name: 'nested_component') } }
        let(:nested_on_success) { [->(_, **) { test_simple_repository.create(name: 'nested_on_success') }] }
        let(:nested_on_failure) { [->(_, **) { test_simple_repository.create(name: 'nested_on_failure') }] }

        it 'returns a result' do
          expect { result }.to change { TestSimple.order(:id).pluck(:name) }.from([])
            .to(%w[nested_component nested_on_success on_success])
          expect(result).to be_a(OmniService::Result) & have_attributes(
            operation: transaction,
            shortcut: nil,
            params: [{}],
            context: { test_simple: have_attributes(name: 'nested_component') },
            errors: [],
            on_success: [
              an_instance_of(OmniService::Result) & have_attributes(
                operation: nested_on_success.first,
                shortcut: nil,
                params: [{}],
                context: { test_simple: have_attributes(name: 'nested_on_success') },
                errors: [],
                on_success: [],
                on_failure: []
              ),
              an_instance_of(OmniService::Result) & have_attributes(
                operation: on_success.first,
                shortcut: nil,
                params: [{}],
                context: { test_simple: have_attributes(name: 'on_success') },
                errors: [],
                on_success: [],
                on_failure: []
              )
            ],
            on_failure: []
          )
        end
      end
    end

    context 'when the component returns Failure' do
      let(:component) do
        lambda { |_, **|
          test_simple_repository.create(name: 'component')
          Dry::Monads::Failure(:invalid)
        }
      end

      it 'returns a result' do
        expect { result }.to change { TestSimple.order(:id).pluck(:name) }.from([]).to(%w[on_failure])
        expect(result).to be_a(OmniService::Result) & have_attributes(
          operation: transaction,
          shortcut: nil,
          params: [{}],
          context: {},
          errors: [have_attributes(message: nil, code: :invalid, path: [], tokens: {})],
          on_success: [],
          on_failure: [an_instance_of(OmniService::Result) & have_attributes(
            operation: on_failure.first,
            shortcut: nil,
            params: [
              {},
              an_instance_of(OmniService::Result) & have_attributes(
                operation: transaction,
                shortcut: nil,
                params: [{}],
                context: {},
                errors: [have_attributes(message: nil, code: :invalid, path: [], tokens: {})],
                on_success: [],
                on_failure: []
              )
            ],
            context: { test_simple: have_attributes(name: 'on_failure') },
            errors: [],
            on_success: [],
            on_failure: []
          )]
        )
      end

      context 'when callback has single positional arg' do
        let(:on_failure) do
          [lambda { |failed_result|
            Dry::Monads::Success(received_error_codes: failed_result.errors.map(&:code))
          }]
        end

        it 'passes only failed result for compatibility' do
          expect(result.on_failure).to match([an_instance_of(OmniService::Result) & have_attributes(
            params: [an_instance_of(OmniService::Result)],
            context: { received_error_codes: [:invalid] }
          )])
        end
      end

      context 'when callback has multiple positional args' do
        let(:on_failure) do
          [lambda { |original_params, failed_result, **original_context|
            Dry::Monads::Success(
              original_params:,
              failed_error_codes: failed_result.errors.map(&:code),
              original_context:
            )
          }]
        end

        it 'passes params, failed result, and context' do
          expect(result.on_failure).to match([an_instance_of(OmniService::Result) & have_attributes(
            params: [
              {},
              an_instance_of(OmniService::Result) & have_attributes(errors: [have_attributes(code: :invalid)])
            ],
            context: {
              original_params: {},
              failed_error_codes: [:invalid],
              original_context: {}
            }
          )])
        end
      end
    end

    context 'with async callbacks' do
      around { |example| OmniService.with_sync_callbacks(false) { example.run } }

      let(:component) { ->(_, **) { Dry::Monads::Success(value: 'component') } }
      let(:callback_values) { Concurrent::Array.new }
      let(:on_success) do
        [lambda { |_, **|
          callback_values << 'executed'
          Dry::Monads::Success(callback: true)
        }]
      end
      let(:on_failure) { [] }

      it 'executes callbacks in background after result returns' do
        expect(callback_values).to be_empty
        expect(result.on_success).to match([an_instance_of(Concurrent::Promises::Future)])
        result.on_success.each(&:wait)
        expect(callback_values).to eq(['executed'])
      end

      context 'when callback raises an exception' do
        let(:on_success) { [->(**) { raise 'async failure' }] }

        it 'does not propagate exception to main thread' do
          expect(result).to be_success
          expect(result.on_success).to match([an_instance_of(Concurrent::Promises::Future)])
          result.on_success.each(&:wait)
          expect(result.on_success).to match([be_rejected])
        end
      end

      context 'with nested transaction in callback' do
        let(:nested_transaction) do
          described_class.new(
            ->(_, **) { Dry::Monads::Success(nested: true) },
            on_success: [->(_, **) { Dry::Monads::Success(nested_callback: true) }]
          )
        end
        let(:on_success) { [->(**) { nested_transaction.call({}) }] }

        it 'propagates async mode to nested transaction' do
          expect(result.on_success).to match([an_instance_of(Concurrent::Promises::Future)])

          resolved_results = result.on_success.map(&:value)
          expect(resolved_results).to match([
            have_attributes(on_success: [an_instance_of(Concurrent::Promises::Future)])
          ])
        end
      end

      context 'with global callback executor' do
        let(:callback_executor_ids) { Concurrent::Array.new }
        let(:nested_callback_executor_ids) { Concurrent::Array.new }
        let(:nested_transaction) do
          described_class.new(
            ->(_, **) { Dry::Monads::Success(nested: true) },
            on_success: [lambda { |_, **|
              nested_callback_executor_ids << OmniService::CallbackExecutor.executor.object_id
              Dry::Monads::Success(nested_callback: true)
            }]
          )
        end
        let(:on_success) do
          [lambda { |_, **|
            callback_executor_ids << OmniService::CallbackExecutor.executor.object_id
            nested_transaction.call({})
          }]
        end

        it 'reuses one callback executor in nested callbacks' do
          expect(result.on_success).to match([an_instance_of(Concurrent::Promises::Future)])

          nested_result = result.on_success.first.value
          nested_result.on_success.each(&:wait)

          expect(callback_executor_ids).to eq(nested_callback_executor_ids)
        end
      end

      context 'with nested transactions as component' do
        let(:component) do
          described_class.new(
            nested_component,
            on_success: nested_on_success,
            on_failure: nested_on_failure
          )
        end
        let(:nested_component) { ->(_, **) { Dry::Monads::Success(name: 'nested_component') } }
        let(:nested_on_success) { [->(_, **) { Dry::Monads::Success(name: 'nested_on_success') }] }
        let(:nested_on_failure) { [->(_, **) { Dry::Monads::Success(name: 'nested_on_failure') }] }
        let(:on_success) { [->(_, **) { Dry::Monads::Success(name: 'on_success') }] }

        it 'flattens on_success callbacks as futures' do
          expect(result).to be_success
          expect(result.on_success).to match([
            an_instance_of(Concurrent::Promises::Future),
            an_instance_of(Concurrent::Promises::Future)
          ])

          resolved_results = result.on_success.map(&:value)

          expect(resolved_results).to match([
            an_instance_of(OmniService::Result) & have_attributes(
              operation: nested_on_success.first,
              context: { name: 'nested_on_success' }
            ),
            an_instance_of(OmniService::Result) & have_attributes(
              operation: on_success.first,
              context: { name: 'on_success' }
            )
          ])
        end
      end

      context 'when nested transaction fails' do
        let(:component) do
          described_class.new(
            nested_component,
            on_success: nested_on_success,
            on_failure: nested_on_failure
          )
        end
        let(:nested_component) { ->(_, **) { Dry::Monads::Failure(:nested_failed) } }
        let(:nested_on_success) { [->(_, **) { Dry::Monads::Success(name: 'nested_on_success') }] }
        let(:nested_on_failure) { [->(_, **) { Dry::Monads::Success(name: 'nested_on_failure') }] }

        it 'collects on_failure callbacks synchronously' do
          expect(result).to be_failure
          expect(result.on_success).to eq([])
          expect(result.on_failure).to match([an_instance_of(OmniService::Result)])
        end
      end
    end
  end

  describe '#signature' do
    subject(:signature) { transaction.signature }

    let(:on_success) { [] }
    let(:on_failure) { [] }

    context 'when component has context-only signature' do
      let(:component) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when component has single param' do
      let(:component) { ->(param, **) {} }

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
