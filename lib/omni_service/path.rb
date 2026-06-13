# frozen_string_literal: true

# Projects a root object through a path into one or more references.
#
# The component using the path decides how to interpret missing references,
# falsey values, and expanded arrays.
#
# @example Read a hash path
#   path = OmniService::Path.new
#   path.call({ post: { author_id: 1 } }, %i[post author_id])
#   # => [Reference(path: [:post, :author_id], value: 1, resolved: true)]
#
# @example Preserve resolved nil values
#   path.call({ post: { author_id: nil } }, %i[post author_id])
#   # => [Reference(path: [:post, :author_id], value: nil, resolved: true)]
#
# @example Report a missing hash key
#   path.call({ post: {} }, %i[post author_id])
#   # => [Reference(path: [:post, :author_id], value: nil, resolved: false)]
#
# @example Read an indexed array element
#   path.call({ comments: [{ id: 1 }] }, [:comments, 0, :id])
#   # => [Reference(path: [:comments, 0, :id], value: 1, resolved: true)]
#
# @example Expand arrays while preserving source paths
#   path = OmniService::Path.new(expand_arrays: true)
#   path.call({ comments: [{ id: 1 }, { id: 2 }] }, %i[comments id])
#   # => [
#   #      Reference(path: [:comments, 0, :id], value: 1, resolved: true),
#   #      Reference(path: [:comments, 1, :id], value: 2, resolved: true)
#   #    ]
#
# @example Keep terminal arrays as one value
#   path.call({ comment_ids: [1, 2] }, [:comment_ids])
#   # => [Reference(path: [:comment_ids], value: [1, 2], resolved: true)]
#
# @example Traverse object methods
#   path = OmniService::Path.new(call_methods: true)
#   path.call({ post: post }, %i[post published?])
#   # => [Reference(path: [:post, :published?], value: true, resolved: true)]
class OmniService::Path
  extend Dry::Initializer
  include Dry::Equalizer(:expand_arrays, :call_methods)

  Segment = OmniService::Types::Symbol | OmniService::Types::Integer
  Segments = OmniService::Types::Array.of(Segment)
  NonEmptySegments = Segments.constrained(min_size: 1)
  CoercibleSegments = OmniService::Types::Coercible::Array.of(Segment)
  CoercibleNonEmptySegments = CoercibleSegments.constrained(min_size: 1)

  Reference = Class.new(Dry::Struct) do
    attribute :path, OmniService::Path::Segments
    attribute :value, OmniService::Types::Any
    attribute :resolved, OmniService::Types::Bool

    def resolved?
      resolved
    end

    def unresolved?
      !resolved
    end

    alias_method :missing?, :unresolved?

    def normalized_value
      Array.wrap(value)
    end
  end

  option :expand_arrays, OmniService::Types::Bool, default: -> { false }
  option :call_methods, OmniService::Types::Bool, default: -> { false }

  def call(root, path, expand_arrays: self.expand_arrays, call_methods: self.call_methods)
    references(root, Array(path), expand_arrays:, call_methods:, current_path: [])
  end

  private

  def references(current, remaining_path, expand_arrays:, call_methods:, current_path:)
    return [reference(current_path, current)] if remaining_path.empty?

    segment, *tail = remaining_path

    case current
    when Hash
      hash_references(current, segment, tail, expand_arrays:, call_methods:, current_path:)
    when Array
      array_references(current, remaining_path, expand_arrays:, call_methods:, current_path:)
    else
      object_references(current, remaining_path, expand_arrays:, call_methods:, current_path:)
    end
  end

  def hash_references(current, segment, tail, expand_arrays:, call_methods:, current_path:)
    full_path = [*current_path, segment, *tail]
    return [missing_reference(full_path)] unless current.key?(segment)

    references(current[segment], tail, expand_arrays:, call_methods:, current_path: [*current_path, segment])
  end

  def array_references(current, remaining_path, expand_arrays:, call_methods:, current_path:)
    segment, *tail = remaining_path

    if segment.is_a?(Integer)
      return array_index_references(current, segment, tail, expand_arrays:, call_methods:, current_path:)
    end

    if expand_arrays
      current.flat_map.with_index do |value, index|
        references(value, remaining_path, expand_arrays:, call_methods:, current_path: [*current_path, index])
      end
    elsif call_methods && method_segment?(segment) && current.respond_to?(segment)
      references(
        current.public_send(segment),
        tail,
        expand_arrays:,
        call_methods:,
        current_path: [*current_path, segment]
      )
    else
      [missing_reference([*current_path, segment, *tail])]
    end
  end

  def array_index_references(current, segment, tail, expand_arrays:, call_methods:, current_path:)
    full_path = [*current_path, segment, *tail]
    return [missing_reference(full_path)] unless segment >= 0 && segment < current.size

    references(current[segment], tail, expand_arrays:, call_methods:, current_path: [*current_path, segment])
  end

  def object_references(current, remaining_path, expand_arrays:, call_methods:, current_path:)
    segment, *tail = remaining_path

    return [] if expand_arrays && !call_methods

    if call_methods && method_segment?(segment) && current.respond_to?(segment)
      references(
        current.public_send(segment),
        tail,
        expand_arrays:,
        call_methods:,
        current_path: [*current_path, segment]
      )
    else
      [missing_reference([*current_path, *remaining_path])]
    end
  end

  def reference(path, value)
    Reference.new(path:, value:, resolved: true)
  end

  def missing_reference(path)
    Reference.new(path:, value: nil, resolved: false)
  end

  def method_segment?(segment)
    segment.is_a?(Symbol)
  end
end
