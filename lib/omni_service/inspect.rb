# frozen_string_literal: true

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

  def initialize(*attributes, **kwargs)
    super(attributes.flatten(1), kwargs)

    define_pretty_print(@attributes, @value_methods)
  end

  private

  def define_pretty_print(attributes, value_methods)
    define_method(:pretty_print) do |pp|
      object_group_method = self.class.name ? :object_group : :object_address_group
      pp.public_send(object_group_method, self) do
        pp.seplist(attributes, -> { pp.text ',' }) do |name|
          pp.breakable ' '
          pp.group(1) do
            pp.text name.to_s
            pp.text '='
            pp.pp __send__(value_methods[name] || name)
          end
        end
      end
    end
  end
end
