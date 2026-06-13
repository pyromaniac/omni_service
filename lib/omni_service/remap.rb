# frozen_string_literal: true

# Context projection component.
#
# Reads values from accumulated context and writes them back under different keys.
# Multiple sources targeting the same path are collected into one flattened array.
#
# @example Alias current user
#   remap(current_user: :user)
#
# @example Read through an object path
#   remap(%i[post author] => :author)
#
# @example Collect multiple sources
#   remap(primary_tag_ids: :tag_ids, secondary_tag_ids: :tag_ids)
#
class OmniService::Remap
  extend Dry::Initializer
  include Dry::Equalizer(:mapping, :path)
  include OmniService::Inspect.new(:mapping, :path, hide_defaults: :path)
  include OmniService::Strict

  param :mapping, OmniService::Types::Hash.map(
    OmniService::Types::Symbol | OmniService::Path::NonEmptySegments,
    OmniService::Types::Symbol | OmniService::Path::NonEmptySegments
  )
  option :path, OmniService::Types::Callable, default: -> { OmniService::Path.new(call_methods: true, expand_arrays: true) }

  def call(*params, **context)
    OmniService::Result.build(self, params:, context: remapped_context(context))
  end

  def signature
    [0, true]
  end

  private

  def remapped_context(context)
    normalized_mapping.each_with_object({}) do |(source, target), remapped|
      references = path.call(context, source)
      collection = collection?(target, references)
      values = mapped_values(references, collection:)

      assign_values(remapped, target, values, collection:)
    end
  end

  def normalized_mapping
    @normalized_mapping ||= mapping.to_h do |source, target|
      [Array(source), Array(target)]
    end
  end

  def target_counts
    @target_counts ||= normalized_mapping.values.tally
  end

  def collection?(target, references)
    target_counts[target] > 1 || references.size != 1
  end

  def mapped_values(references, collection:)
    if collection
      references.flat_map(&:normalized_value).compact
    else
      [references.first.value]
    end
  end

  def assign_values(hash, target, values, collection:)
    if collection
      return hash if values.empty?

      assign_path(hash, target, [*Array.wrap(value_at(hash, target)), *values])
    else
      assign_path(hash, target, values.first)
    end
  end

  def assign_path(hash, path, value)
    *head, tail = path
    head.reduce(hash) { |current, segment| current[segment] ||= {} }[tail] = value
    hash
  end

  def value_at(hash, path)
    path.reduce(hash) do |current, segment|
      current[segment] if current.is_a?(Hash)
    end
  end
end
