# frozen_string_literal: true

RSpec.describe OmniService::Helpers do
  subject(:processed_result) { helper_host.process_errors(result_or_errors, path_prefix:) }

  let(:helper_host) do
    Class.new do
      include Dry::Monads[:result]
      include OmniService::Helpers

      def call(*)
        nil
      end
    end.new
  end
  let(:path_prefix) { [:external] }

  context 'when result is successful' do
    let(:result_or_errors) { empty_success_result }
    let(:empty_success_result) { Dry::Monads::Success() }
    let(:context_success_result) { Dry::Monads::Success(created: true) }

    it 'returns original result for empty and context payloads' do
      expect(processed_result).to equal(empty_success_result)
      expect(helper_host.process_errors(context_success_result, path_prefix:)).to equal(context_success_result)
    end
  end

  context 'when result is failed monad' do
    let(:result_or_errors) { Dry::Monads::Failure([{ code: :invalid, path: [:email] }]) }

    it 'returns failure with prefixed paths' do
      expect(processed_result).to be_failure
      expect(processed_result.failure).to contain_exactly(
        an_instance_of(OmniService::Error) & have_attributes(
          component: helper_host,
          code: :invalid,
          path: %i[external email]
        )
      )
    end
  end

  context 'when errors are provided directly as an array' do
    let(:error_source_operation) { ->(**) { Dry::Monads::Success() } }
    let(:result_or_errors) do
      [
        { code: :blank, path: [:name] },
        OmniService::Error.build(error_source_operation, code: :not_found, path: [:author])
      ]
    end

    it 'returns failure with all errors processed and prefixed paths' do
      expect(processed_result).to be_failure
      expect(processed_result.failure).to contain_exactly(
        an_instance_of(OmniService::Error) & have_attributes(
          component: helper_host,
          code: :blank,
          path: %i[external name]
        ),
        an_instance_of(OmniService::Error) & have_attributes(
          component: helper_host,
          code: :not_found,
          path: %i[external author]
        )
      )
    end
  end

  context 'when input is OmniService::Result' do
    let(:operation) { ->(**) { Dry::Monads::Success() } }

    context 'with successful result' do
      let(:result_or_errors) { OmniService::Result.build(operation, context: { created: true }) }

      it 'returns the original result' do
        expect(processed_result).to equal(result_or_errors)
      end
    end

    context 'with failed result' do
      let(:result_or_errors) do
        OmniService::Result.build(
          operation,
          errors: [OmniService::Error.build(operation, code: :invalid, path: [:email])]
        )
      end

      it 'returns failure with processed result errors and prefixed paths' do
        expect(processed_result).to be_failure
        expect(processed_result.failure).to contain_exactly(
          an_instance_of(OmniService::Error) & have_attributes(
            component: helper_host,
            code: :invalid,
            path: %i[external email]
          )
        )
      end
    end
  end
end
