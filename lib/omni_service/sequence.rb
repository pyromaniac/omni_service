# frozen_string_literal: true

# Executes components sequentially, short-circuiting on first failure or shortcut.
# Context accumulates across components; each receives merged context from previous.
#
# @example Blog post creation pipeline
#   sequence(
#     validate_params,           # Failure here stops the pipeline
#     find_author,               # Adds :author to context
#     create_post,               # Receives :author, adds :post
#     notify_subscribers         # Receives :author and :post
#   )
#
# @example With shortcut for idempotency
#   sequence(
#     shortcut(find_existing_post),  # Success here exits early
#     validate_params,
#     create_post
#   )
#
class OmniService::Sequence
  extend Dry::Initializer
  include Dry::Equalizer(:components)
  include OmniService::Inspect.new(:components)
  include OmniService::Strict

  param :components, OmniService::Types::Array.of(OmniService::Types::Interface(:call))

  def initialize(*args, **)
    super(args.flatten(1), **)
  end

  def call(*params, **context)
    component_wrappers.inject(OmniService::Result.build(self, params:, context:)) do |result, component|
      break result if result.failure? || result.shortcut?

      result.merge(component.call(*result.params, **result.context))
    end
  end

  def signature
    @signature ||= begin
      param_counts = component_wrappers.map { |component| component.signature.first }
      [param_counts.all? ? param_counts.max : nil, true]
    end
  end

  private

  def component_wrappers
    @component_wrappers ||= OmniService::Component.wrap(components)
  end
end
