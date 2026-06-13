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
class OmniService::Assert
  extend Dry::Initializer
  include Dry::Equalizer(:predicate, :code, :path)
  include OmniService::Inspect.new(:predicate, :code, :path, hide_defaults: :path)
  include OmniService::Strict

  param :predicate, OmniService::Path::CoercibleNonEmptySegments
  option :code, OmniService::Types::Symbol
  option :path, OmniService::Types::Callable, default: -> { OmniService::Path.new(call_methods: true, expand_arrays: true) }

  def call(*params, **context)
    failed_references = path.call(context, predicate).reject { |reference| reference.resolved? && reference.value }

    if failed_references.empty?
      OmniService::Result.build(self, params:, context:)
    else
      OmniService::Result.build(
        self,
        params:,
        context:,
        errors: failed_references.map { |reference| OmniService::Error.build(self, code:, path: reference.path) }
      )
    end
  end

  def signature
    [0, true]
  end
end
