# frozen_string_literal: true

RSpec.describe OmniService::FindMany do
  subject(:find_many) { described_class.new(context_key, repository: repository, **options) }

  let(:context_key) { :test_simples }
  let(:repository) { TestRepository.new(TestSimple) }
  let(:options) { {} }

  describe '#initialize' do
    context 'with overlapping scope columns' do
      let(:options) { { within: { id: :allowed_ids } } }

      it 'rejects the overlapping scope' do
        expect { find_many }.to raise_error(ArgumentError, 'Query conditions overlap lookup columns: [:id]')
      end
    end
  end

  describe '#call' do
    subject(:result) { find_many.call(params, **context) }

    let(:context) { {} }
    let!(:test_simple1) { TestSimple.create!(name: 'test_simple1') }
    let!(:test_simple2) { TestSimple.create!(name: 'test_simple2') }
    let!(:test_simple3) { TestSimple.create!(name: 'test_simple3') }

    context 'with context scopes' do
      let(:options) { { within: { tenant: %i[current_user account], flag: :enabled } } }
      let(:params) { { test_simple_ids: [test_simple1.id, test_simple2.id], tenant: other_tenant, enabled: true } }
      let(:context) { { current_user: current_user, enabled: false } }
      let(:current_user) { Struct.new(:account).new(tenant) }
      let(:tenant) { TestTenant.create!(name: 'tenant') }
      let(:other_tenant) { TestTenant.create!(name: 'other') }
      let!(:test_simple1) { TestSimple.create!(name: 'test_simple1', tenant: tenant) }
      let!(:test_simple2) { TestSimple.create!(name: 'test_simple2', tenant: tenant) }
      let!(:test_simple3) { TestSimple.create!(name: 'test_simple3', tenant: other_tenant) }

      it 'queries with context association and flag' do
        expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
      end

      context 'with a custom params resolver' do
        let(:options) { super().merge(resolver: custom_resolver) }
        let(:params) { { lookup: super() } }
        let(:params_path) { OmniService::Path.new(expand_arrays: true) }
        let(:custom_resolver) { ->(root, path) { params_path.call(root.fetch(:lookup), path) } }

        it 'calls the resolver with two arguments' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
        end
      end

      context 'with a custom context resolver' do
        let(:options) { super().merge(context_resolver: custom_resolver) }
        let(:context) { { caller: super() } }
        let(:context_path) { OmniService::Path.new(call_methods: true) }
        let(:custom_resolver) { ->(root, path) { context_path.call(root.fetch(:caller), path) } }

        it 'calls the resolver with two arguments' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
        end
      end

      context 'with changing context' do
        let(:other_user) { Struct.new(:account).new(other_tenant) }

        it 'resolves scopes for each call' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
          expect(find_many.call(params, **context, current_user: other_user)).to be_failure([
            { code: :not_found, path: [:test_simple_ids, 0] },
            { code: :not_found, path: [:test_simple_ids, 1] }
          ])
        end
      end

      context 'with an ID from another tenant' do
        let(:params) { { test_simple_ids: [test_simple1.id, test_simple3.id] } }

        it 'reports the foreign ID with its index' do
          expect(result).to be_failure([{ code: :not_found, path: [:test_simple_ids, 1] }])
        end
      end

      context 'with a different flag' do
        let(:context) { { current_user: current_user, enabled: true } }

        it 'applies every scope column' do
          expect(result).to be_failure([
            { code: :not_found, path: [:test_simple_ids, 0] },
            { code: :not_found, path: [:test_simple_ids, 1] }
          ])
        end
      end

      context 'with a tenant ID path' do
        let(:options) { { within: { tenant_id: %i[current_user account id] } } }

        it 'queries with the association ID' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
        end
      end

      context 'with an indexed context path' do
        let(:options) { { within: { tenant: [:users, 0, :account] } } }
        let(:context) { { users: [current_user] } }

        it 'reads the indexed account' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
        end
      end

      context 'with an array scope value' do
        let(:options) { { within: { tenant_id: :allowed_tenant_ids } } }
        let(:params) { { test_simple_ids: [test_simple1.id, test_simple2.id, test_simple3.id] } }
        let(:context) { { allowed_tenant_ids: [tenant.id, other_tenant.id] } }

        it 'passes the entire array to the query' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2, test_simple3))
        end

        context 'with an empty scope array' do
          let(:context) { { allowed_tenant_ids: [] } }

          it 'reports every ID as not found' do
            expect(result).to be_failure([
              { code: :not_found, path: [:test_simple_ids, 0] },
              { code: :not_found, path: [:test_simple_ids, 1] },
              { code: :not_found, path: [:test_simple_ids, 2] }
            ])
          end
        end
      end

      context 'with a nil scope value' do
        let(:options) { { within: { tenant: %i[current_user account] } } }
        let(:context) { { current_user: Struct.new(:account).new(nil) } }

        it 'keeps nil in the query' do
          expect(result).to be_failure([
            { code: :not_found, path: [:test_simple_ids, 0] },
            { code: :not_found, path: [:test_simple_ids, 1] }
          ])
        end
      end

      context 'without the context root' do
        let(:context) { { enabled: false } }

        it 'raises for the missing context path' do
          expect { result }.to raise_error(KeyError, 'Missing context path for tenant: [:current_user, :account]')
        end
      end

      context 'with an unindexed array path' do
        let(:options) { { within: { tenant: %i[users account] } } }
        let(:context) { { users: [current_user] } }

        it 'rejects array expansion in scopes' do
          expect { result }.to raise_error(KeyError, 'Missing context path for tenant: [:users, :account]')
        end
      end

      context 'with loaded entities' do
        let(:context) { { test_simples: [test_simple1] } }

        it 'keeps the existing context shortcut' do
          expect(result).to be_success({})
        end
      end

      context 'with omittable params' do
        let(:options) { { within: { tenant: %i[current_user account] }, omittable: true } }
        let(:params) { {} }
        let(:context) { {} }

        it 'skips lookup before resolving scopes' do
          expect(result).to be_success({})
        end
      end

      context 'with polymorphic repositories' do
        let(:options) do
          { within: { tenant: %i[current_user account] }, by: { id: %i[items id] }, type: %i[items type] }
        end
        let(:repository) do
          {
            'First' => TestRepository.new(TestSimple.where(name: 'test_simple1')),
            'Second' => TestRepository.new(TestSimple.where(name: %w[test_simple2 test_simple3]))
          }
        end
        let(:params) { { items: [{ id: test_simple1.id, type: 'First' }, { id: test_simple2.id, type: 'Second' }] } }
        let(:context) { { current_user: current_user, items: [{ type: 'invalid' }] } }

        it 'selects each repository from params' do
          expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
        end

        context 'with a custom params resolver' do
          let(:options) { super().merge(resolver: custom_resolver) }
          let(:params) { { lookup: super() } }
          let(:params_path) { OmniService::Path.new(expand_arrays: true) }
          let(:custom_resolver) { ->(root, path) { params_path.call(root.fetch(:lookup), path) } }

          it 'resolves indexed types with two args' do
            expect(result).to be_success(test_simples: contain_exactly(test_simple1, test_simple2))
          end
        end

        context 'with an ID from another tenant' do
          let(:params) { { items: [{ id: test_simple1.id, type: 'First' }, { id: test_simple3.id, type: 'Second' }] } }

          it 'scopes every selected repository' do
            expect(result).to be_failure([{ code: :not_found, path: [:items, 1, :id] }])
          end
        end
      end
    end

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
