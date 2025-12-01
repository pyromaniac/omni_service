# frozen_string_literal: true

RSpec.describe OmniService::Async do
  let(:operation_class) do
    Class.new do
      def self.system
        @system ||= OmniService::Component.new(->(**) { Dry::Monads::Success(result: 'ok') })
      end
    end
  end

  let(:job_class) do
    Class.new do
      class << self
        attr_accessor :options, :arguments

        def set(options)
          @options = options
          self
        end

        def perform_later(*arguments)
          @arguments = arguments
          Struct.new(:provider_job_id, :job_id).new('job-123', 'uuid-456')
        end
      end
    end
  end

  before { stub_const('OperationJob', job_class) }

  describe '#call' do
    subject(:call) { async.call({ title: 'Hello' }, author: 'John') }

    let(:async) { described_class.new(operation_class, :system, job_class:) }

    it 'enqueues job with correct arguments and returns Success' do
      expect(call).to be_success(job: have_attributes(provider_job_id: 'job-123', job_id: 'uuid-456'))
      expect(job_class).to have_attributes(
        arguments: [operation_class, :system, [{ title: 'Hello' }], { author: 'John' }],
        options: {}
      )
    end

    context 'with job_options' do
      let(:async) { described_class.new(operation_class, :system, job_class:, job_options: { queue: 'high' }) }

      it 'applies job options' do
        expect(call).to be_success
        expect(job_class).to have_attributes(options: { queue: 'high' })
      end
    end
  end

  describe '#set' do
    subject(:with_options) { async.set(wait: 300, queue: 'low') }

    let(:async) { described_class.new(operation_class, :system, job_class:, job_options: { priority: 10 }) }

    it 'returns new instance with merged options preserving original' do
      expect(with_options).to be_an(described_class) &
        have_attributes(
          operation_class: operation_class,
          operation_method: :system,
          job_class: job_class,
          job_options: { priority: 10, wait: 300, queue: 'low' }
        )
      expect(with_options).not_to equal(async)
      expect(async.job_options).to eq(priority: 10)
    end

    context 'when chaining multiple set calls' do
      subject(:chained) { async.set(wait: 300).set(queue: 'critical').set(wait: 600) }

      it 'accumulates options with later values overriding' do
        expect(chained.job_options).to eq(priority: 10, wait: 600, queue: 'critical')
      end
    end

    context 'when calling after set' do
      it 'uses merged options for job' do
        expect(async.set(wait: 300, queue: 'low').call({ id: 1 })).to be_success
        expect(job_class).to have_attributes(options: { priority: 10, wait: 300, queue: 'low' })
      end
    end
  end

  describe OmniService::Async::Convenience do
    let(:convenience_operation) do
      Class.new do
        extend OmniService::Async::Convenience

        def self.system
          @system ||= OmniService::Component.new(->(**) { Dry::Monads::Success() })
        end
      end
    end

    before { stub_const('ConvenienceOperation', convenience_operation) }

    describe '#method_missing' do
      subject(:async_method) { convenience_operation.system_async }

      it 'returns memoized Async instance configured for operation' do
        expect(async_method).to be_an(OmniService::Async) &
          have_attributes(operation_class: convenience_operation, operation_method: :system)
        expect(convenience_operation.system_async).to equal(async_method)
      end

      it 'raises NoMethodError for unknown or non-async methods' do
        expect { convenience_operation.unknown_async }.to raise_error(NoMethodError)
        expect { convenience_operation.unknown }.to raise_error(NoMethodError)
      end
    end

    describe '#respond_to_missing?' do
      it 'returns true only for valid *_async methods' do
        expect(convenience_operation.respond_to?(:system_async)).to be(true)
        expect(convenience_operation.respond_to?(:unknown_async)).to be(false)
        expect(convenience_operation.respond_to?(:unknown)).to be(false)
      end
    end

    describe '.[]' do
      let(:configured_operation) do
        Class.new do
          extend OmniService::Async::Convenience[queue: 'important', priority: 5, job_class: OperationJob]

          def self.system
            @system ||= OmniService::Component.new(->(**) { Dry::Monads::Success() })
          end
        end
      end

      before { stub_const('ConfiguredOperation', configured_operation) }

      it 'configures async with default job options and class' do
        expect(configured_operation.system_async).to have_attributes(
          job_options: { queue: 'important', priority: 5 },
          job_class: OperationJob
        )
      end
    end
  end
end
