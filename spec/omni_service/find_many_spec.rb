# frozen_string_literal: true

RSpec.describe OmniService::FindMany do
  let(:find_many) { described_class.new(context_key, repository: repository, **options) }
  let(:context_key) { :test_simples }
  let(:repository) { TestRepository.new(TestSimple) }
  let(:options) { {} }

  describe '#call' do
    subject(:result) { find_many.call(params, **context) }

    let(:context) { {} }
    let!(:test_simple1) { TestSimple.create!(name: 'test_simple1') }
    let!(:test_simple2) { TestSimple.create!(name: 'test_simple2') }
    let!(:test_simple3) { TestSimple.create!(name: 'test_simple3') }

    context 'with default options' do
      where(:params, :context, :match_result) do
        context = [
          { test_simples: lazy { [test_simple2, test_simple3] } },
          { test_simples: [] },
          { test_simples: 42 },
          {}
        ]
        match_result = {
          { test_simple_ids: lazy { [test_simple2.id, test_simple1.id, test_simple1.id] } } => [
            be_success({}),
            be_success({}),
            lazy { be_success({ test_simples: contain_exactly(test_simple2, test_simple1) }) },
            lazy { be_success({ test_simples: contain_exactly(test_simple2, test_simple1) }) }
          ],
          { test_simple_ids: lazy { test_simple1.id } } => [
            be_success({}),
            be_success({}),
            lazy { be_success({ test_simples: [test_simple1] }) },
            lazy { be_success({ test_simples: [test_simple1] }) }
          ],
          { test_simple_ids: lazy { [0, nil, {}, [], { foo: 42 }, [:foo], test_simple1.id] } } => [
            be_success({}),
            be_success({}),
            be_failure([
              { code: :not_found, path: [:test_simple_ids, 0] },
              { code: :not_found, path: [:test_simple_ids, 1] },
              { code: :not_found, path: [:test_simple_ids, 2] },
              { code: :not_found, path: [:test_simple_ids, 3] },
              { code: :not_found, path: [:test_simple_ids, 4] },
              { code: :not_found, path: [:test_simple_ids, 5] }
            ]),
            be_failure([
              { code: :not_found, path: [:test_simple_ids, 0] },
              { code: :not_found, path: [:test_simple_ids, 1] },
              { code: :not_found, path: [:test_simple_ids, 2] },
              { code: :not_found, path: [:test_simple_ids, 3] },
              { code: :not_found, path: [:test_simple_ids, 4] },
              { code: :not_found, path: [:test_simple_ids, 5] }
            ])
          ],
          { test_simple_ids: [] } => [
            be_success({}),
            be_success({}),
            be_success({ test_simples: [] }),
            be_success({ test_simples: [] })
          ],
          {} => [
            be_success({}),
            be_success({}),
            be_failure([{ code: :missing, path: [:test_simple_ids] }]),
            be_failure([{ code: :missing, path: [:test_simple_ids] }])
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

    context 'when id nested inside of array' do
      let(:options) { { by: { id: %i[deep id] } } }

      where(:params, :match_result) do
        [
          [
            { deep: [
              [{ id: lazy { test_simple2.id } }],
              { id: lazy { [test_simple1.id, test_simple2.id, test_simple3.id] } },
              { id: [] }
            ] },
            lazy { be_success({ test_simples: contain_exactly(test_simple2, test_simple1, test_simple3) }) }
          ],
          [
            { deep: { id: lazy { [test_simple1.id, test_simple3.id] } } },
            lazy { be_success({ test_simples: contain_exactly(test_simple1, test_simple3) }) }
          ],
          [
            { deep: { id: lazy { test_simple1.id } } },
            lazy { be_success({ test_simples: [test_simple1] }) }
          ],
          [
            { deep: [{ id: nil }, [{ id: 0 }], { id: lazy { [test_simple1.id, 0, nil, { foo: 42 }, [:foo]] } }] },
            be_failure([
              { code: :not_found, path: [:deep, 0, :id] },
              { code: :not_found, path: [:deep, 1, 0, :id] },
              { code: :not_found, path: [:deep, 2, :id, 1] },
              { code: :not_found, path: [:deep, 2, :id, 2] },
              { code: :not_found, path: [:deep, 2, :id, 3] },
              { code: :not_found, path: [:deep, 2, :id, 4] }
            ])
          ],
          [
            { deep: [[], [{}, 42], {}, { id: lazy { test_simple1.id } }, 42] },
            be_failure([
              { code: :missing, path: [:deep, 1, 0, :id] },
              { code: :missing, path: [:deep, 2, :id] }
            ])
          ],
          [
            { deep: {} },
            be_failure([{ code: :missing, path: %i[deep id] }])
          ],
          [
            { deep: { id: [] } },
            be_success({ test_simples: [] })
          ],
          [
            { deep: [] },
            be_success({})
          ],
          [
            {},
            be_success({})
          ]
        ]
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when omittable' do
      let(:options) { { omittable: true } }

      where(:params, :match_result) do
        [
          [
            { test_simple_ids: lazy { [test_simple1.id, test_simple2.id] } },
            lazy { be_success({ test_simples: contain_exactly(test_simple1, test_simple2) }) }
          ],
          [
            { test_simple_ids: lazy { [test_simple1.id, 0, 0, nil, test_simple3.id] } },
            be_failure([
              { code: :not_found, path: [:test_simple_ids, 1] },
              { code: :not_found, path: [:test_simple_ids, 2] },
              { code: :not_found, path: [:test_simple_ids, 3] }
            ])
          ],
          [
            { test_simple_ids: [] },
            be_success({ test_simples: [] })
          ],
          [
            {},
            be_success({})
          ]
        ]
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with omittable id nested inside of array' do
      let(:options) { { by: { id: %i[deep id] }, omittable: true } }

      where(:params, :match_result) do
        [
          [
            { deep: [
              [{ id: lazy { test_simple2.id } }],
              { id: lazy { [test_simple1.id, test_simple3.id] } },
              { id: [] }
            ] },
            lazy { be_success({ test_simples: contain_exactly(test_simple2, test_simple1, test_simple3) }) }
          ],
          [
            { deep: { id: lazy { [test_simple1.id, test_simple3.id] } } },
            lazy { be_success({ test_simples: contain_exactly(test_simple1, test_simple3) }) }
          ],
          [
            { deep: { id: lazy { test_simple1.id } } },
            lazy { be_success({ test_simples: [test_simple1] }) }
          ],
          [
            { deep: [{ id: nil }, [{ id: 0 }], { id: lazy { [test_simple1.id, 0, nil, { foo: 42 }, [:foo]] } }] },
            be_failure([
              { code: :not_found, path: [:deep, 0, :id] },
              { code: :not_found, path: [:deep, 1, 0, :id] },
              { code: :not_found, path: [:deep, 2, :id, 1] },
              { code: :not_found, path: [:deep, 2, :id, 2] },
              { code: :not_found, path: [:deep, 2, :id, 3] },
              { code: :not_found, path: [:deep, 2, :id, 4] }
            ])
          ],
          [
            { deep: [[], [{}, 42], {}, { id: lazy { test_simple1.id } }, 42] },
            lazy { be_success({ test_simples: [test_simple1] }) }
          ],
          [
            { deep: {} },
            be_success({})
          ],
          [
            { deep: { id: [] } },
            be_success({ test_simples: [] })
          ],
          [
            { deep: [] },
            be_success({})
          ],
          [
            {},
            be_success({})
          ]
        ]
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when nullable' do
      let(:options) { { nullable: true } }

      where(:params, :match_result) do
        [
          [
            { test_simple_ids: lazy { [test_simple1.id, nil, test_simple2.id] } },
            lazy { be_success({ test_simples: contain_exactly(test_simple1, test_simple2) }) }
          ],
          [
            { test_simple_ids: lazy { [test_simple1.id, 0, 0, nil, test_simple3.id] } },
            be_failure([
              { code: :not_found, path: [:test_simple_ids, 1] },
              { code: :not_found, path: [:test_simple_ids, 2] }
            ])
          ],
          [
            { test_simple_ids: [] },
            be_success({ test_simples: [] })
          ],
          [
            {},
            be_failure([{ code: :missing, path: [:test_simple_ids] }])
          ]
        ]
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'when nullable id nested inside of array' do
      let(:options) { { by: { id: %i[deep id] }, nullable: true } }

      where(:params, :match_result) do
        [
          [
            { deep: [
              [{ id: lazy { test_simple2.id } }],
              { id: lazy { [test_simple1.id, test_simple3.id] } },
              { id: [] }
            ] },
            lazy { be_success({ test_simples: contain_exactly(test_simple2, test_simple1, test_simple3) }) }
          ],
          [
            { deep: { id: lazy { [test_simple1.id, test_simple3.id] } } },
            lazy { be_success({ test_simples: contain_exactly(test_simple1, test_simple3) }) }
          ],
          [
            { deep: { id: lazy { test_simple1.id } } },
            lazy { be_success({ test_simples: [test_simple1] }) }
          ],
          [
            { deep: [{ id: nil }, [{ id: 0 }], { id: lazy { [test_simple1.id, 0, nil, { foo: 42 }, [:foo]] } }] },
            be_failure([
              { code: :not_found, path: [:deep, 1, 0, :id] },
              { code: :not_found, path: [:deep, 2, :id, 1] },
              { code: :not_found, path: [:deep, 2, :id, 3] },
              { code: :not_found, path: [:deep, 2, :id, 4] }
            ])
          ],
          [
            { deep: [[], [{}, 42], {}, { id: lazy { test_simple1.id } }, 42] },
            be_failure([
              { code: :missing, path: [:deep, 1, 0, :id] },
              { code: :missing, path: [:deep, 2, :id] }
            ])
          ],
          [
            { deep: {} },
            be_failure([{ code: :missing, path: %i[deep id] }])
          ],
          [
            { deep: { id: [] } },
            be_success({ test_simples: [] })
          ],
          [
            { deep: [] },
            be_success({})
          ],
          [
            {},
            be_success({})
          ]
        ]
      end

      with_them do
        it { is_expected.to match_result }
      end
    end

    context 'with polymorphic setup' do
      let(:options) do
        {
          by: { id: %i[deep id] },
          type: %i[deep type],
          repository: {
            'simples_false' => TestRepository.new(TestSimple.where(flag: false)),
            'simples_true' => TestRepository.new(TestSimple.where(flag: true))
          }
        }
      end

      let!(:test_simple4) { TestSimple.create!(name: 'test_simple4', flag: true) }
      let!(:test_simple5) { TestSimple.create!(name: 'test_simple5', flag: true) }

      where(:params, :match_result) do
        [
          [
            { deep: [
              { type: 'simples_false', id: lazy { test_simple1.id } },
              { type: 'simples_true', id: lazy { test_simple4.id } }
            ] },
            lazy { be_success({ test_simples: contain_exactly(test_simple1, test_simple4) }) }
          ],
          [
            { deep: [
              { type: 'simples_true' },
              { id: lazy { test_simple2.id } },
              { type: nil, id: lazy { test_simple2.id } },
              { type: 'invalid', id: lazy { test_simple2.id } },
              { type: nil },
              { type: 'invalid' },
              { id: nil },
              {}
            ] },
            be_failure([
              { code: :missing, path: [:deep, 0, :id] },
              { code: :missing, path: [:deep, 4, :id] },
              { code: :missing, path: [:deep, 5, :id] },
              { code: :missing, path: [:deep, 7, :id] },
              { code: :missing, path: [:deep, 1, :type] },
              { code: :missing, path: [:deep, 7, :type] },
              { code: :included, path: [:deep, 2, :type], tokens: { allowed_values: %w[simples_false simples_true] } },
              { code: :included, path: [:deep, 3, :type], tokens: { allowed_values: %w[simples_false simples_true] } }
            ])
          ],
          [
            { deep: [
              { type: 'simples_false', id: lazy { test_simple1.id } },
              { type: 'simples_false', id: lazy { test_simple5.id } },
              { type: 'simples_true', id: lazy { test_simple2.id } },
              { type: 'simples_true', id: 0 },
              { type: 'simples_true', id: nil }
            ] },
            be_failure([
              { code: :not_found, path: [:deep, 1, :id] },
              { code: :not_found, path: [:deep, 2, :id] },
              { code: :not_found, path: [:deep, 3, :id] },
              { code: :not_found, path: [:deep, 4, :id] }
            ])
          ],
          [
            { deep: [] },
            be_success({})
          ]
        ]
      end

      with_them do
        it { is_expected.to match_result }
      end
    end
  end
end
