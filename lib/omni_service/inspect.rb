# frozen_string_literal: true

require 'pp'

# Module factory for custom pretty_print output.
# Generates a module that defines pretty_print showing specified attributes.
#
# @example Adding inspection to a class
#   class MyComponent
#     include OmniService::Inspect.new(:name, :options)
#     # Now `pp my_component` shows: #<MyComponent name=..., options=...>
#   end
#
class OmniService::Inspect < Module
  extend Dry::Initializer

  param :attributes, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol), reader: false
  param :value_methods, OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Symbol)
  param :hide_defaults, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol), default: -> { [] }

  def initialize(*attributes, hide_defaults: [], **value_methods)
    super(attributes.flatten(1), value_methods, hide_defaults)

    inspect_object = method(:inspect_object)
    pretty_inspect_object = method(:pretty_inspect_object)

    define_method(:inspect) do
      inspect_object.call(self)
    end

    define_method(:pretty_print) do |pp|
      pretty_inspect_object.call(self, pp)
    end
  end

  private

  def inspect_object(object)
    body = pairs_for(object).map { |name, value| "#{name}=#{value.inspect}" }.join(' ')

    body.empty? ? "#<#{object.class.name}>" : "#<#{object.class.name} #{body}>"
  end

  def pretty_inspect_object(object, pp)
    object_group_method = object.class.name ? :object_group : :object_address_group
    pp.public_send(object_group_method, object) do
      pp.seplist(pairs_for(object), -> {}) do |name, value|
        pp.breakable ' '
        pp.group(1) do
          pp.text name.to_s
          pp.text '='
          pp.pp value
        end
      end
    end
  end

  def pairs_for(object)
    @attributes.filter_map do |name|
      value = value_for(object, name)
      next if @hide_defaults.include?(name) && value == default_for(object, name)

      [name, value]
    end
  end

  def value_for(object, name)
    object.public_send(@value_methods[name] || name)
  end

  def default_for(object, name)
    definition = object.class.dry_initializer.definitions[name] if object.class.respond_to?(:dry_initializer)
    default = definition&.default

    default && object.instance_exec(&default)
  end
end
