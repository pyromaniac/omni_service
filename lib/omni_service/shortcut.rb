# frozen_string_literal: true

# Enables early pipeline exit on success. Used for idempotency and guard clauses.
#
# On success: marks result with shortcut flag, causing Sequence to exit immediately.
# On failure: returns empty success, allowing pipeline to continue.
#
# @example Idempotent post creation
#   sequence(
#     shortcut(find_existing_post),  # Found? Exit with existing post
#     validate_params,                # Not found? Continue creation
#     create_post
#   )
#
# @example Guard clause
#   sequence(
#     shortcut(check_already_subscribed),  # Already subscribed? Done
#     validate_subscription,
#     create_subscription
#   )
#
class OmniService::Shortcut
  extend Dry::Initializer
  include Dry::Equalizer(:component)
  include OmniService::Inspect.new(:component)
  include OmniService::Strict

  param :component, OmniService::Types::Interface(:call)

  def call(*params, **context)
    result = component_wrapper.call(*params, **context)

    if result.success?
      result.merge(shortcut: component)
    else
      OmniService::Result.build(self, params:, context:)
    end
  end

  def signature
    @signature ||= [component_wrapper.signature.first, true]
  end

  private

  def component_wrapper
    @component_wrapper ||= OmniService::Component.wrap(component)
  end
end
