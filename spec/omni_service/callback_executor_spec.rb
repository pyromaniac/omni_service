# frozen_string_literal: true

RSpec.describe OmniService::CallbackExecutor do
  describe '.executor' do
    subject(:executor) { described_class.executor }

    it 'returns the same executor in current thread' do
      expect(executor).to equal(described_class.executor)
    end

    it 'returns the same executor across ruby threads' do
      executor_from_other_thread = nil
      other_thread = Thread.new do
        executor_from_other_thread = described_class.executor
      end
      other_thread.join

      expect(executor).to equal(executor_from_other_thread)
    end
  end

  describe '.shutdown' do
    subject(:shutdown_executor) { described_class.shutdown(timeout) }

    let(:timeout) { 0.5 }

    it 'waits for queued callbacks to complete when they finish in time' do
      callback_values = Concurrent::Array.new
      described_class.executor.post { callback_values << :executed }

      expect(shutdown_executor).to be(true)
      expect(callback_values).to eq([:executed])
    end

    context 'when callback does not finish before timeout' do
      let(:timeout) { 0.001 }

      it 'returns false after forcing executor kill' do
        described_class.executor.post { sleep 2 }

        expect(shutdown_executor).to be(false)
      end
    end
  end
end
