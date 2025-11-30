# frozen_string_literal: true

RSpec.describe OmniService::Result do
  let(:operation) { ->(**) { Dry::Monads::Success() } }
  let(:other_operation) { ->(**) { Dry::Monads::Success() } }

  describe '.process' do
    subject(:process) { described_class.process(operation, monad) }

    context 'when result is already OmniService::Result' do
      let(:monad) { described_class.build(other_operation, context: { key: 'value' }) }

      it 'returns result as-is without wrapping' do
        expect(process).to equal(monad)
        expect(process.operation).to eq(other_operation)
      end
    end

    context 'when Success()' do
      let(:monad) { Dry::Monads::Success() }

      it 'builds result with empty params and context' do
        expect(process).to be_a(described_class) & have_attributes(
          operation: operation,
          params: [],
          context: {},
          errors: []
        )
      end
    end

    context 'when Success({}) empty context' do
      let(:monad) { Dry::Monads::Success({}) }

      it 'builds result with empty params and context' do
        expect(process).to be_a(described_class) & have_attributes(
          operation: operation,
          params: [],
          context: {},
          errors: []
        )
      end
    end

    context 'when Success(params, context)' do
      let(:monad) { Dry::Monads::Success[{ id: 1 }, key: 'value'] }

      it 'builds result with params and context' do
        expect(process).to have_attributes(
          params: [{ id: 1 }],
          context: { key: 'value' }
        )
      end
    end

    context 'when Success(multiple_params, context)' do
      let(:monad) { Dry::Monads::Success[{ id: 1 }, { id: 2 }, { id: 3 }, key: 'value'] }

      it 'builds result with all params collected' do
        expect(process).to have_attributes(
          params: [{ id: 1 }, { id: 2 }, { id: 3 }],
          context: { key: 'value' }
        )
      end
    end

    context 'when Success(context) hash only' do
      let(:monad) { Dry::Monads::Success(key: 'value', other: 123) }

      it 'builds result with context and empty params' do
        expect(process).to have_attributes(
          params: [],
          context: { key: 'value', other: 123 }
        )
      end
    end

    context 'when Failure with single code' do
      let(:monad) { Dry::Monads::Failure[:not_found] }

      it 'builds result with error' do
        expect(process).to have_attributes(
          params: [],
          context: {},
          errors: [have_attributes(code: :not_found, path: [])]
        )
      end
    end

    context 'when Failure with multiple errors' do
      let(:monad) { Dry::Monads::Failure[{ code: :blank, path: [:title] }, { code: :invalid, path: [:email] }] }

      it 'builds result with all errors' do
        expect(process.errors).to match([
          have_attributes(code: :blank, path: [:title]),
          have_attributes(code: :invalid, path: [:email])
        ])
      end
    end

    context 'when invalid result' do
      let(:monad) { Dry::Monads::Success('not a valid shape') }

      it 'raises with descriptive message' do
        expect { process }.to raise_error(RuntimeError, /Invalid callable result.*returned by/)
      end
    end
  end

  describe '.build' do
    subject(:result) { described_class.build(operation, context: { key: 'value' }) }

    it 'creates result with defaults and overrides' do
      expect(result).to have_attributes(
        operation: operation,
        shortcut: nil,
        params: [],
        context: { key: 'value' },
        errors: [],
        on_success: [],
        on_failure: []
      )
    end
  end

  describe '#merge' do
    let(:error) { OmniService::Error.build(operation, code: :invalid) }
    let(:result) do
      described_class.build(
        operation,
        params: [:original],
        context: { a: 1 },
        errors: [error],
        on_success: [described_class.build(operation)],
        on_failure: [described_class.build(operation)]
      )
    end

    context 'without other result' do
      subject(:merged) { result.merge(context: { b: 2 }) }

      it 'applies changes to current result' do
        expect(merged).to have_attributes(
          operation: operation,
          params: [:original],
          context: { b: 2 },
          errors: [error]
        )
      end
    end

    context 'with other result' do
      subject(:merged) { result.merge(other) }

      let(:other_error) { OmniService::Error.build(other_operation, code: :blank) }
      let(:other) do
        described_class.build(
          other_operation,
          params: [:other_params],
          context: { b: 2 },
          errors: [other_error],
          on_success: [described_class.build(other_operation)],
          on_failure: [described_class.build(other_operation)]
        )
      end

      it 'merges attributes from both results' do
        expect(merged).to have_attributes(
          operation: operation,
          params: [:other_params],
          context: { a: 1, b: 2 },
          errors: [error, other_error]
        )
        expect(merged.on_success.size).to eq(2)
        expect(merged.on_failure.size).to eq(2)
      end

      context 'when other has empty params' do
        let(:other) { described_class.build(other_operation, context: { b: 2 }) }

        it 'preserves original params' do
          expect(merged.params).to eq([:original])
        end
      end
    end

    context 'with shortcut handling' do
      subject(:merged) { result.merge(other) }

      let(:shortcut_operation) { ->(**) { Dry::Monads::Success() } }

      context 'when current has shortcut and other does not' do
        let(:result) { described_class.build(operation, shortcut: shortcut_operation) }
        let(:other) { described_class.build(other_operation) }

        it 'preserves existing shortcut' do
          expect(merged.shortcut).to eq(shortcut_operation)
        end
      end

      context 'when current has no shortcut and other does' do
        let(:result) { described_class.build(operation) }
        let(:other) { described_class.build(other_operation, shortcut: other_operation) }

        it 'uses other shortcut' do
          expect(merged.shortcut).to eq(other_operation)
        end
      end

      context 'when both have shortcuts' do
        let(:result) { described_class.build(operation, shortcut: shortcut_operation) }
        let(:other) { described_class.build(other_operation, shortcut: other_operation) }

        it 'preserves current shortcut over other' do
          expect(merged.shortcut).to eq(shortcut_operation)
        end
      end
    end
  end

  describe '#shortcut?' do
    context 'when shortcut is present' do
      subject(:shortcut) { result.shortcut? }

      let(:result) { described_class.build(operation, shortcut: operation) }

      it { is_expected.to eq(operation) }
    end

    context 'when shortcut is absent' do
      subject(:shortcut) { result.shortcut? }

      let(:result) { described_class.build(operation) }

      it { is_expected.to be_nil }
    end
  end

  describe '#success?' do
    context 'when no errors' do
      subject(:success) { result.success? }

      let(:result) { described_class.build(operation) }

      it { is_expected.to be(true) }
    end

    context 'when errors present' do
      subject(:success) { result.success? }

      let(:result) { described_class.build(operation, errors: [OmniService::Error.build(operation, code: :invalid)]) }

      it { is_expected.to be(false) }
    end
  end

  describe '#failure?' do
    context 'when no errors' do
      subject(:failure) { result.failure? }

      let(:result) { described_class.build(operation) }

      it { is_expected.to be(false) }
    end

    context 'when errors present' do
      subject(:failure) { result.failure? }

      let(:result) { described_class.build(operation, errors: [OmniService::Error.build(operation, code: :invalid)]) }

      it { is_expected.to be(true) }
    end
  end

  describe '#to_monad' do
    subject(:monad) { result.to_monad }

    context 'when success' do
      let(:result) { described_class.build(operation) }

      it 'returns Success wrapping self' do
        expect(monad).to be_a(Dry::Monads::Success)
        expect(monad.value!).to equal(result)
      end
    end

    context 'when failure' do
      let(:result) { described_class.build(operation, errors: [OmniService::Error.build(operation, code: :invalid)]) }

      it 'returns Failure wrapping self' do
        expect(monad).to be_a(Dry::Monads::Failure)
        expect(monad.failure).to equal(result)
      end
    end
  end

  describe '#deconstruct_keys' do
    subject(:deconstruct) { result.deconstruct_keys(nil) }

    let(:result) { described_class.build(operation, params: [{ id: 1 }], context: { key: 1 }, errors: []) }

    it 'returns hash for pattern matching' do
      expect(deconstruct).to eq(
        operation: operation,
        params: [{ id: 1 }],
        context: { key: 1 },
        errors: []
      )
    end

    it 'supports pattern matching syntax' do
      case result
      in operation: matched_operation, context: { key: value }
        expect(matched_operation).to eq(operation)
        expect(value).to eq(1)
      end
    end
  end
end
