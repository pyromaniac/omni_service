# frozen_string_literal: true

RSpec.describe OmniService::Either do
  subject(:either) { described_class.new(component_a, component_b) }

  let(:component_a) { ->(_, **) { Dry::Monads::Failure(:a_failed) } }
  let(:component_b) { ->(params, **) { Dry::Monads::Success(result_b: params) } }

  describe '.new' do
    context 'when either is empty' do
      it 'raises constraint error' do
        expect { described_class.new }.to raise_error(Dry::Types::ConstraintError)
      end
    end
  end

  describe '#call' do
    subject(:call) { either.call(*input_params) }

    let(:input_params) { [:p1] }

    context 'when first component succeeds' do
      let(:component_a) { ->(params, **) { Dry::Monads::Success(result_a: params) } }

      it 'returns first success without trying others' do
        expect(call).to be_success & have_attributes(
          context: { result_a: :p1 },
          params: [:p1]
        )
      end
    end

    context 'when first fails and second succeeds' do
      it 'returns second success' do
        expect(call).to be_success & have_attributes(
          context: { result_b: :p1 },
          params: [:p1]
        )
      end
    end

    context 'when all components fail' do
      let(:component_b) { ->(_, **) { Dry::Monads::Failure(:b_failed) } }

      it 'returns last failure' do
        expect(call).to be_failure & have_attributes(
          errors: [have_attributes(code: :b_failed)]
        )
      end
    end

    context 'with three components' do
      subject(:either) { described_class.new(component_a, component_b, component_c) }

      let(:component_a) { ->(_, **) { Dry::Monads::Failure(:a_failed) } }
      let(:component_b) { ->(_, **) { Dry::Monads::Failure(:b_failed) } }
      let(:component_c) { ->(params, **) { Dry::Monads::Success(result_c: params) } }

      it 'tries until success' do
        expect(call).to be_success & have_attributes(
          context: { result_c: :p1 }
        )
      end
    end

    context 'when component produces params' do
      let(:component_a) { ->(_, **) { Dry::Monads::Failure(:a_failed) } }
      let(:component_b) { ->(_, **) { Dry::Monads::Success[:new_param, result_b: true] } }

      it 'returns produced params' do
        expect(call).to be_success & have_attributes(
          params: [:new_param],
          context: { result_b: true }
        )
      end
    end

    context 'with context passed through' do
      let(:input_params) { [:p1] }
      let(:component_a) { ->(_, key:, **) { Dry::Monads::Failure(:"needs_#{key}") } }
      let(:component_b) { ->(params, key:, **) { Dry::Monads::Success(result: params, key:) } }

      it 'passes context to all components' do
        result = either.call(:p1, key: 'value')

        expect(result).to be_success & have_attributes(
          context: { result: :p1, key: 'value' }
        )
      end
    end

    context 'with transaction rollback' do
      subject(:pipeline) do
        OmniService::Transaction.new(
          described_class.new(
            OmniService::Transaction.new(risky_operation),
            safe_fallback
          )
        )
      end

      let(:test_simple_repository) { TestRepository.new(TestSimple) }

      let(:risky_operation) do
        lambda do |_, **|
          test_simple_repository.create(name: 'risky_record')
          Dry::Monads::Failure(:risky_failed)
        end
      end

      let(:safe_fallback) do
        lambda do |_, **|
          test_simple_repository.create(name: 'safe_record')
          Dry::Monads::Success(created: 'safe')
        end
      end

      it 'rolls back failed branch and commits successful branch' do
        expect { pipeline.call({}) }
          .to change { TestSimple.pluck(:name) }
          .from([])
          .to(['safe_record'])

        expect(pipeline.call({})).to be_success & have_attributes(
          context: { created: 'safe' }
        )
      end

      context 'when first branch succeeds' do
        let(:risky_operation) do
          lambda do |_, **|
            test_simple_repository.create(name: 'risky_record')
            Dry::Monads::Success(created: 'risky')
          end
        end

        it 'commits first branch without trying fallback' do
          expect { pipeline.call({}) }
            .to change { TestSimple.pluck(:name) }
            .from([])
            .to(['risky_record'])
        end
      end

      context 'when all branches fail' do
        let(:safe_fallback) do
          lambda do |_, **|
            test_simple_repository.create(name: 'safe_record')
            Dry::Monads::Failure(:safe_failed)
          end
        end

        it 'rolls back everything' do
          expect { pipeline.call({}) }.not_to(change { TestSimple.count })
        end
      end
    end
  end

  describe '#signature' do
    subject(:signature) { either.signature }

    context 'when all components have context-only signature' do
      let(:component_a) { ->(**) {} }
      let(:component_b) { ->(**) {} }

      it 'returns zero params' do
        expect(signature).to eq([0, true])
      end
    end

    context 'when all components have same signature' do
      let(:component_a) { ->(param, **) {} }
      let(:component_b) { ->(param, **) {} }

      it 'returns max' do
        expect(signature).to eq([1, true])
      end
    end

    context 'when components have different signatures' do
      let(:component_a) { ->(first) {} }
      let(:component_b) { ->(first, second) {} }

      it 'returns max' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when components have optional params' do
      let(:component_a) { ->(first, second = nil, **) {} }
      let(:component_b) { ->(first, **) {} }

      it 'returns max including optional' do
        expect(signature).to eq([2, true])
      end
    end

    context 'when any component has splat signature' do
      let(:component_a) { ->(first, **) {} }
      let(:component_b) { ->(*args, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end

    context 'when any component has required param and splat' do
      let(:component_a) { ->(first, **) {} }
      let(:component_b) { ->(first, *rest, **) {} }

      it 'returns nil for params count' do
        expect(signature).to eq([nil, true])
      end
    end
  end
end
