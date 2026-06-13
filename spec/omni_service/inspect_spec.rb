# frozen_string_literal: true

RSpec.describe OmniService::Inspect do
  subject(:inspect_output) { component.inspect }

  let(:pretty_inspect_output) { component.pretty_inspect }
  let(:component_class) do
    stub_const('TestInspectComponent', Class.new do
      extend Dry::Initializer
      include Dry::Equalizer(:name, :count, :path)
      include OmniService::Inspect.new(:name, :count, :path, hide_defaults: :path)

      param :name, OmniService::Types::Symbol
      option :count, OmniService::Types::Integer
      option :path, OmniService::Types::Callable, default: -> { OmniService::Path.new(call_methods: true) }
    end)
  end

  context 'with default value' do
    let(:component) { component_class.new(:post, count: 1) }

    it 'omits the default attribute' do
      expect(inspect_output).to eq('#<TestInspectComponent name=:post count=1>')
      expect(pretty_inspect_output).to eq(<<~INSPECT)
        #<TestInspectComponent name=:post count=1>
      INSPECT
    end
  end

  context 'with custom value' do
    let(:component) do
      component_class.new(:post, count: 1, path: OmniService::Path.new(call_methods: true, expand_arrays: true))
    end

    it 'includes the custom attribute' do
      expect(inspect_output).to eq(
        '#<TestInspectComponent name=:post count=1 path=#<OmniService::Path expand_arrays=true call_methods=true>>'
      )
      expect(pretty_inspect_output).to eq(<<~INSPECT)
        #<TestInspectComponent
         name=:post
         count=1
         path=#<OmniService::Path expand_arrays=true call_methods=true>>
      INSPECT
    end
  end
end
