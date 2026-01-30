# frozen_string_literal: true

# Swallows component failures, returning empty success instead.
# Useful for non-critical operations that shouldn't block the pipeline.
#
# On success: returns component result unchanged.
# On failure: returns Success({}) with empty context, discarding errors.
#
# @example Optional profile enrichment
#   chain(
#     create_user,
#     optional(fetch_avatar_from_gravatar),  # Failure won't stop pipeline
#     send_welcome_email
#   )
#
# @example Optional cache warming
#   chain(
#     update_post,
#     optional(warm_cache)  # Cache failure is acceptable
#   )
#
class OmniService::Optional
  extend Dry::Initializer
  include Dry::Equalizer(:component)
  include OmniService::Inspect.new(:component)
  include OmniService::Strict

  param :component, OmniService::Types::Interface(:call)

  def call(*params, **context)
    result = component_wrapper.call(*params, **context)

    if result.success?
      result
    else
      OmniService::Result.build(self, params: result.params, context: {})
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
