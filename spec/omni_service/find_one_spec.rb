# frozen_string_literal: true

RSpec.describe OmniService::FindOne do
  subject(:find_one) { described_class.new(context_key, repository: repository, **options) }

  let(:context_key) { :test_simple }
  let(:repository) { TestRepository.new(TestSimple) }
  let(:options) { {} }

  describe '#initialize' do
    context 'with overlapping scope columns' do
      let(:options) { { within: { id: :allowed_id } } }

      it 'rejects the overlapping scope' do
        expect { find_one }.to raise_error(ArgumentError, 'Query conditions overlap lookup columns: [:id]')
      end
    end

    context 'with overlapping custom columns' do
      let(:options) { { by: :name, within: { name: :allowed_name } } }

      it 'rejects the overlapping scope' do
        expect { find_one }.to raise_error(ArgumentError, 'Query conditions overlap lookup columns: [:name]')
      end
    end
  end

  describe '#call' do
    subject(:result) { find_one.call(params, **context) }

    let!(:test_simple) { TestSimple.create!(name: 'test_simple') }

    context 'with context scopes' do
      let(:options) { { within: { tenant: %i[current_user account], flag: :enabled } } }
      let(:params) { { test_simple_id: test_simple.id, tenant: other_tenant, enabled: true } }
      let(:context) { { current_user: current_user, enabled: false } }
      let(:current_user) { Struct.new(:account).new(tenant) }
      let(:tenant) { TestTenant.create!(name: 'tenant') }
      let(:other_tenant) { TestTenant.create!(name: 'other') }
      let!(:test_simple) { TestSimple.create!(name: 'test_simple', tenant: tenant) }

      it 'queries with context association and flag' do
        expect(result).to be_success(test_simple: test_simple)
      end

      context 'with a custom params resolver' do
        let(:options) { super().merge(resolver: custom_resolver) }
        let(:params) { { lookup: super() } }
        let(:params_path) { OmniService::Path.new }
        let(:custom_resolver) { ->(root, path) { params_path.call(root.fetch(:lookup), path) } }

        it 'calls the resolver with two arguments' do
          expect(result).to be_success(test_simple: test_simple)
        end
      end

      context 'with a custom context resolver' do
        let(:options) { super().merge(context_resolver: custom_resolver) }
        let(:context) { { caller: super() } }
        let(:context_path) { OmniService::Path.new(call_methods: true) }
        let(:custom_resolver) { ->(root, path) { context_path.call(root.fetch(:caller), path) } }

        it 'calls the resolver with two arguments' do
          expect(result).to be_success(test_simple: test_simple)
        end
      end

      context 'with changing context' do
        let(:other_user) { Struct.new(:account).new(other_tenant) }

        it 'resolves scopes for each call' do
          expect(result).to be_success(test_simple: test_simple)
          expect(find_one.call(params, **context, current_user: other_user)).to be_failure([
            { code: :not_found, path: [:test_simple_id] }
          ])
        end
      end

      context 'with another tenant' do
        let(:current_user) { Struct.new(:account).new(other_tenant) }

        it 'reports the ID as not found' do
          expect(result).to be_failure([{ code: :not_found, path: [:test_simple_id] }])
        end
      end

      context 'with a different flag' do
        let(:context) { { current_user: current_user, enabled: true } }

        it 'applies every scope column' do
          expect(result).to be_failure([{ code: :not_found, path: [:test_simple_id] }])
        end
      end

      context 'with a tenant ID path' do
        let(:options) { { within: { tenant_id: %i[current_user account id] } } }

        it 'queries with the association ID' do
          expect(result).to be_success(test_simple: test_simple)
        end
      end

      context 'with an indexed context path' do
        let(:options) { { within: { tenant: [:users, 0, :account] } } }
        let(:context) { { users: [current_user] } }

        it 'reads the indexed account' do
          expect(result).to be_success(test_simple: test_simple)
        end
      end

      context 'with a nil scope value' do
        let(:context) { { current_user: current_user, expected_name: nil } }
        let(:options) { { within: { tenant: %i[current_user account], name: :expected_name } } }
        let!(:test_simple) { TestSimple.create!(tenant: tenant) }

        it 'keeps nil in the query' do
          expect(result).to be_success(test_simple: test_simple)
        end

        context 'with a named entity' do
          let!(:test_simple) { TestSimple.create!(name: 'test_simple', tenant: tenant) }

          it 'restricts the query to nil values' do
            expect(result).to be_failure([{ code: :not_found, path: [:test_simple_id] }])
          end
        end
      end

      context 'without the context root' do
        let(:context) { { enabled: false } }

        it 'raises for the missing context path' do
          expect { result }.to raise_error(KeyError, 'Missing context path for tenant: [:current_user, :account]')
        end
      end

      context 'without the account method' do
        let(:context) { { current_user: Object.new, enabled: false } }

        it 'raises for the missing context path' do
          expect { result }.to raise_error(KeyError, 'Missing context path for tenant: [:current_user, :account]')
        end
      end

      context 'with a nil intermediate value' do
        let(:context) { { current_user: nil, enabled: false } }

        it 'raises for the missing context path' do
          expect { result }.to raise_error(KeyError, 'Missing context path for tenant: [:current_user, :account]')
        end
      end

      context 'with a loaded entity' do
        let(:context) { { test_simple: test_simple } }

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

      context 'with nullable params' do
        let(:options) { { within: { tenant: %i[current_user account] }, nullable: true } }
        let(:params) { { test_simple_id: nil } }
        let(:context) { {} }

        it 'clears the entity before resolving scopes' do
          expect(result).to be_success(test_simple: nil)
        end
      end

      context 'with polymorphic repositories' do
        let(:repository) do
          {
            'First' => TestRepository.new(TestSimple.where(name: 'test_simple')),
            'Second' => TestRepository.new(TestSimple.where(name: 'second'))
          }
        end
        let(:params) { { test_simple_id: test_simple.id, test_simple_type: 'First' } }
        let(:context) { { current_user: current_user, enabled: false, test_simple_type: 'Second' } }

        it 'selects the repository from params' do
          expect(result).to be_success(test_simple: test_simple)
        end

        context 'with another tenant' do
          let(:current_user) { Struct.new(:account).new(other_tenant) }

          it 'scopes the selected repository' do
            expect(result).to be_failure([{ code: :not_found, path: [:test_simple_id] }])
          end
        end
      end
    end

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
