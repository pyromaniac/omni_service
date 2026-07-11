# frozen_string_literal: true

# Context predicate precondition that succeeds when the predicate resolves truthy.
#
# Traverses hashes by key, expands arrays, and calls methods on objects.
#
# @example Assert an entity state
#   assert(%i[post published?], code: :not_published)
#
# @example Assert the first comment
#   assert([:comments, 0, :valid?], code: :first_comment_invalid)
#
# @example Associate failure with a params path
#   assert(%i[post published?], code: :not_published, path: :publish)
#
class OmniService::Assert
  extend Dry::Initializer
  include Dry::Equalizer(:predicate, :code, :path, :resolver)
  include OmniService::Inspect.new(:predicate, :code, :path, :resolver, hide_defaults: :resolver)
  include OmniService::Strict

  param :predicate, OmniService::Path::CoercibleNonEmptySegments
  option :code, OmniService::Types::Symbol
  option :path, OmniService::Path::CoercibleSegments, default: -> { [] }
  option :resolver, OmniService::Types::Callable,
    default: -> { OmniService::Path.new(call_methods: true, expand_arrays: true) }

  def call(*params, **context)
    failed = resolver.call(context, predicate).any? { |reference| !reference.resolved? || !reference.value }

    if failed
      OmniService::Result.build(
        self,
        params:,
        context:,
        errors: [OmniService::Error.build(self, code:, path:)]
      )
    else
      OmniService::Result.build(self, params:, context:)
    end
  end

  def signature
    [0, true]
  end
end
