# frozen_string_literal: true

RSpec.describe OmniService::FindOne do
  let(:find_one) { described_class.new(context_key, repository: repository, **options) }
  let(:context_key) { :test_simple }
  let(:repository) { TestRepository.new(TestSimple) }
  let(:options) { {} }

  describe '#call' do
    subject(:result) { find_one.call(params, **context) }

    let!(:test_simple) { TestSimple.create!(name: 'test_simple') }

    context 'with default options' do
      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :missing, path: [:test_simple_id] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with simple lookup' do
      let(:options) { { by: :name } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { name: 'test_simple' } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { name: 'foobar' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:name] }]),
            be_failure([{ code: :not_found, path: [:name] }])
          ],
          { name: nil } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:name] }]),
            be_failure([{ code: :not_found, path: [:name] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:name] }]),
            be_failure([{ code: :missing, path: [:name] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with polymorphic lookup' do
      let(:repository) do
        {
          'First' => TestRepository.new(TestSimple.where(name: 'first')),
          'Second' => TestRepository.new(TestSimple.where(name: 'second'))
        }
      end

      let!(:test_simple1) { TestSimple.create!(name: 'first') }
      let!(:test_simple2) { TestSimple.create!(name: 'second') }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple1.id }, test_simple_type: 'First' } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple1 }) },
            lazy { be_success({ test_simple: test_simple1 }) }
          ],
          { test_simple_id: lazy { test_simple2.id }, test_simple_type: 'Second' } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple2 }) },
            lazy { be_success({ test_simple: test_simple2 }) }
          ],
          { test_simple_id: lazy { test_simple1.id }, test_simple_type: 'Second' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: lazy { test_simple.id }, test_simple_type: 'Third' } => [
            be_success({}),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }]),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }])
          ],
          { test_simple_id: lazy { test_simple.id }, test_simple_type: nil } => [
            be_success({}),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }]),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }])
          ],
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_type] }]),
            be_failure([{ code: :missing, path: [:test_simple_type] }])
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_type] }]),
            be_failure([{ code: :missing, path: [:test_simple_type] }])
          ],
          { test_simple_id: 0, test_simple_type: 'Second' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: 0, test_simple_type: 'Third' } => [
            be_success({}),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }]),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }])
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :missing, path: [:test_simple_id] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with polymorphic lookup and nullable' do
      let(:options) { { nullable: true } }

      let(:repository) do
        {
          'First' => TestRepository.new(TestSimple.where(name: 'first')),
          'Second' => TestRepository.new(TestSimple.where(name: 'second'))
        }
      end

      let!(:test_simple1) { TestSimple.create!(name: 'first') }
      let!(:test_simple2) { TestSimple.create!(name: 'second') }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple1.id }, test_simple_type: 'First' } => [
            be_success({}),
            be_success({}),
            lazy { be_success({ test_simple: test_simple1 }) }
          ],
          { test_simple_id: lazy { test_simple2.id }, test_simple_type: 'Second' } => [
            be_success({}),
            be_success({}),
            lazy { be_success({ test_simple: test_simple2 }) }
          ],
          { test_simple_id: lazy { test_simple1.id }, test_simple_type: 'Second' } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: lazy { test_simple.id }, test_simple_type: 'Third' } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }])
          ],
          { test_simple_id: lazy { test_simple.id }, test_simple_type: nil } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }])
          ],
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_type] }])
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_type] }])
          ],
          { test_simple_id: 0, test_simple_type: 'Second' } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: 0, test_simple_type: 'Third' } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :included, path: [:test_simple_type], tokens: { allowed_values: %w[First Second] } }])
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_success({}),
            be_success({ test_simple: nil })
          ],
          {} => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_id] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with deep lookup' do
      let(:options) { { by: { id: %i[deep id] } } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { deep: { id: lazy { test_simple.id } } } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { deep: { id: 0 } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }])
          ],
          { deep: { id: nil } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }])
          ],
          { deep: {} } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }]),
            be_failure([{ code: :missing, path: %i[deep id] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }]),
            be_failure([{ code: :missing, path: %i[deep id] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with multi-column lookup' do
      let(:options) { { by: %i[id name] } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { id: lazy { test_simple.id }, name: 'test_simple' } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { id: 0, name: 'test_simple' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }])
          ],
          { id: nil, name: 'test_simple' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }])
          ],
          { id: lazy { test_simple.id }, name: 'invalid' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }])
          ],
          { id: nil, name: nil } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }])
          ],
          { id: 0 } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :missing, path: [:name] }])
          ],
          { name: 'test_simple' } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :missing, path: [:id] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:id] }, { code: :not_found, path: [:name] }]),
            be_failure([{ code: :missing, path: [:id] }, { code: :missing, path: [:name] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with multi-column deep lookup' do
      let(:options) { { by: { id: %i[deep id], name: %i[deep name] } } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { deep: { id: lazy { test_simple.id }, name: 'test_simple' } } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { deep: { id: lazy { test_simple.id }, name: 'invalid' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: 0, name: 'test_simple' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil, name: 'test_simple' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil, name: nil } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep name] }])
          ],
          { deep: { id: 0 } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep name] }])
          ],
          { deep: { name: 'test_simple' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep id] }])
          ],
          { deep: {} } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep id] }, { code: :missing, path: %i[deep name] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep id] }, { code: :missing, path: %i[deep name] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when omittable' do
      let(:options) { { omittable: true } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_success({})
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with omittable multi-column deep lookup' do
      let(:options) { { by: { id: %i[deep id], name: %i[deep name] }, omittable: true } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { deep: { id: lazy { test_simple.id }, name: 'test_simple' } } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { deep: { id: lazy { test_simple.id }, name: 'invalid' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: 0, name: 'test_simple' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil, name: 'test_simple' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil, name: nil } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep name] }])
          ],
          { deep: { id: 0 } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep name] }])
          ],
          { deep: { name: 'test_simple' } } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_failure([{ code: :missing, path: %i[deep id] }])
          ],
          { deep: {} } => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_success({})
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }]),
            be_success({})
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when nullable' do
      let(:options) { { nullable: true } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_success({}),
            be_success({ test_simple: nil })
          ],
          {} => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_id] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with nullable multi-column deep lookup' do
      let(:options) { { by: { id: %i[deep id], name: %i[deep name] }, nullable: true } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { deep: { id: lazy { test_simple.id }, name: 'test_simple' } } => [
            be_success({}),
            lazy { be_success({}) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { deep: { id: lazy { test_simple.id }, name: 'invalid' } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: 0, name: 'test_simple' } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil, name: 'test_simple' } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: %i[deep id] }, { code: :not_found, path: %i[deep name] }])
          ],
          { deep: { id: nil, name: nil } } => [
            be_success({}),
            be_success({}),
            be_success({ test_simple: nil })
          ],
          { deep: { id: nil } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: %i[deep name] }])
          ],
          { deep: { id: 0 } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: %i[deep name] }])
          ],
          { deep: { name: 'test_simple' } } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: %i[deep id] }])
          ],
          { deep: {} } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: %i[deep id] }, { code: :missing, path: %i[deep name] }])
          ],
          {} => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: %i[deep id] }, { code: :missing, path: %i[deep name] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when omittable and nullable' do
      let(:options) { { omittable: true, nullable: true } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }])
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_success({}),
            be_success({ test_simple: nil })
          ],
          {} => [
            be_success({}),
            be_success({}),
            be_success({})
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when skippable' do
      let(:options) { { skippable: true } }

      where(:params, :context, :match_result) do
        context = [
          { test_simple: ref(:test_simple) },
          { test_simple: nil },
          {}
        ]
        match_result = {
          { test_simple_id: lazy { test_simple.id } } => [
            be_success({}),
            lazy { be_success({ test_simple: test_simple }) },
            lazy { be_success({ test_simple: test_simple }) }
          ],
          { test_simple_id: 0 } => [
            be_success({}),
            be_success({}),
            be_success({})
          ],
          { test_simple_id: nil } => [
            be_success({}),
            be_success({}),
            be_success({})
          ],
          {} => [
            be_success({}),
            be_failure([{ code: :not_found, path: [:test_simple_id] }]),
            be_failure([{ code: :missing, path: [:test_simple_id] }])
          ]
        }

        match_result.size.times.to_a.product(context.size.times.to_a).map do |i, j|
          [match_result.keys[i], context[j], match_result.values[i][j]]
        end
      end

      with_them do
        it { is_expected.to match_result }
      end
    end
  end
end
