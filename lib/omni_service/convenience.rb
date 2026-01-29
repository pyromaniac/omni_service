# frozen_string_literal: true

# DSL module for building operations with composable components.
# Provides factory methods and includes common dependencies.
#
# Includes: Dry::Initializer, Dry::Monads[:result], Dry::Monads::Do, Dry::Core::Constants
#
#
# Bang methods: Appending ! to any method returns a callable that uses call!
#               e.g., MyOp.create! returns MyOp.create.method(:call!)
#
# @example Typical operation class
#   class Posts::Create
#     extend OmniService::Convenience
#
#     option :post_repo, default: -> { PostRepository.new }
#
#     def self.system
#       @system ||= sequence(
#         input,
#         transaction(create, on_success: [notify])
#       )
#     end
#
#     def self.input
#       @input ||= parallel(
#         params { required(:title).filled(:string) },
#         find_author
#       )
#     end
#
#     def self.create
#       ->(params, author:, **) { post_repo.create(params.merge(author:)) }
#     end
#   end
#
#   Posts::Create.system.call({ title: 'Hello' }, current_user:)
#   Posts::Create.system!.call({ title: 'Hello' }, current_user:)  # raises on failure
#
module OmniService::Convenience
  def self.extended(mod)
    mod.extend Dry::Initializer
    mod.include Dry::Monads[:result]
    mod.include Dry::Monads::Do.for(:call)
    mod.include Dry::Core::Constants
    mod.include OmniService::Helpers
  end

  def method_missing(name, ...)
    name_without_suffix = name.to_s.delete_suffix('!').to_sym
    if name.to_s.end_with?('!') && respond_to?(name_without_suffix)
      public_send(name_without_suffix, ...).method(:call!)
    else
      super
    end
  end

  def respond_to_missing?(name, *)
    (name.to_s.end_with?('!') && respond_to?(name.to_s.delete_suffix('!').to_sym)) || super
  end

  def noop
    ->(_, **) { Dry::Monads::Success({}) }
  end

  def sequence(...)
    OmniService::Sequence.new(...)
  end

  def parallel(...)
    OmniService::Parallel.new(...)
  end

  def fanout(...)
    OmniService::Fanout.new(...)
  end

  def split(...)
    OmniService::Split.new(...)
  end

  def either(...)
    OmniService::Either.new(...)
  end

  def collection(...)
    OmniService::Collection.new(...)
  end

  def transaction(...)
    OmniService::Transaction.new(...)
  end

  def shortcut(...)
    OmniService::Shortcut.new(...)
  end

  def optional(...)
    OmniService::Optional.new(...)
  end

  def namespace(...)
    OmniService::Namespace.new(...)
  end

  def params(**, &)
    OmniService::Params.params(**, &)
  end

  def context!(schema)
    OmniService::Context.new(schema)
  end

  def context(schema)
    OmniService::Context.new(schema, raise_on_error: false)
  end

  def component(name, from = Object, **options, &block)
    raise ArgumentError, "Please provide either a superclass or a block for #{name}" unless from || block

    klass = Class.new(from)
    klass.extend(Dry::Initializer) unless klass.include?(Dry::Initializer)
    klass.include(Dry::Monads[:result]) unless klass.is_a?(Dry::Monads[:result])
    klass.class_eval do
      options.each do |name, type|
        option name, type
      end
    end
    klass.define_method(:call, &block) if block

    const_set(name.to_s.camelize, klass)
  end

  %w[policy precondition callback].each do |kind|
    define_method kind do |prefix = nil, from: OmniService::Component, &block|
      component([prefix, kind].compact.join('_'), from:, &block)
    end
  end
end
