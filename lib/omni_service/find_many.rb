# frozen_string_literal: true

# Finds multiple entities by IDs via repository#get_many.
# Accepts array of IDs or nested structures with IDs.
# Returns deduplicated entities; reports not-found errors with array indices.
#
# Options:
# - :with - param key for IDs array (default: :"#{context_key.singularize}_ids")
# - :by - column mapping with nested paths: { id: [:comments, :id] }
# - :repository - single repo or Hash for polymorphic lookup
# - :type - path to type discriminator for polymorphic lookup
# - :within - query columns mapped to context paths
#
# Flags:
# - :nullable - skip nil values in array instead of reporting errors
# - :omittable - allow missing param key, returns Success({})
#
# @example Basic bulk lookup
#   FindMany.new(:posts, repository: post_repo)
#   # params: { post_ids: [1, 2, 3] } => Success(posts: [<Post>, <Post>, <Post>])
#
# @example Nested IDs in array of hashes
#   FindMany.new(:comments, repository: repo, by: { id: [:comments, :id] })
#   # params: { comments: [{ id: 1 }, { id: [2, 3] }] }
#   # => Success(comments: [<Comment>, <Comment>, <Comment>])
#
# @example Error reporting with indices
#   # params: { post_ids: [1, 999, 3] } where 999 doesn't exist
#   # => Failure([{ code: :not_found, path: [:post_ids, 1] }])
#
# @example Polymorphic lookup
#   FindMany.new(:attachments, repository: { 'Image' => img_repo, 'Video' => vid_repo },
#                by: { id: [:files, :id] }, type: [:files, :type])
#   # params: { files: [{ type: 'Image', id: 1 }, { type: 'Video', id: 2 }] }
#
# @example Context scope
#   FindMany.new(:posts, repository: post_repo, within: { tenant: %i[current_user account], flag: :enabled })
#   # params: { post_ids: [1, 2] }, context: { current_user: user, enabled: false }
#   # => post_repo.get_many(id: [1, 2], tenant: user.account, flag: false)
#
# @example Nullable for optional associations
#   FindMany.new(:tags, repository: repo, nullable: true)
#   # params: { tag_ids: [1, nil, 2] } => Success(tags: [<Tag>, <Tag>])
#
class OmniService::FindMany
  extend Dry::Initializer
  include Dry::Monads[:result]
  include OmniService::Inspect.new(
    :context_key, :repository, :lookup, :within, :omittable, :resolver, :context_resolver,
    hide_defaults: %i[within resolver context_resolver]
  )

  PRIMARY_KEY = :id

  Lookup = Class.new(Dry::Struct) do
    extend Forwardable

    attribute :id, OmniService::Path::Reference
    attribute :type, OmniService::Types::Nil | OmniService::Path::Reference

    def_delegators :id, :path, :value, :normalized_value

    def missing?
      id.missing? || type&.missing?
    end

    def missing_id_path
      id.path if id.missing?
    end

    def missing_type_path
      type.path if type&.missing? && (id.missing? || !id.value.nil?)
    end

    def invalid_type_path(repository)
      type.path if type && !repository.key?(type.value)
    end

    def type_value
      type.value
    end
  end

  param :context_key, OmniService::Types::Symbol
  option :repository, OmniService::Types::Interface(:get_many) |
    OmniService::Types::Hash.map(OmniService::Types::String, OmniService::Types::Interface(:get_many))
  option :type, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol), default: proc { :type }
  option :with, OmniService::Types::Symbol, default: proc { :"#{context_key.to_s.singularize}_ids" }
  option :by, OmniService::Types::Symbol |
    OmniService::Types::Array.of(OmniService::Types::Symbol) |
    OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Symbol |
      OmniService::Types::Array.of(OmniService::Types::Symbol)), optional: true
  option :within, OmniService::Types::Hash.map(
    OmniService::Types::Symbol, OmniService::Path::CoercibleNonEmptySegments
  ), default: -> { {} }
  option :omittable, OmniService::Types::Bool, default: proc { false }
  option :nullable, OmniService::Types::Bool, default: proc { false }
  option :resolver, OmniService::Types::Callable, default: -> { OmniService::Path.new(expand_arrays: true) }
  option :context_resolver, OmniService::Types::Callable, default: -> { OmniService::Path.new(call_methods: true) }

  def initialize(...)
    super

    overlapping_columns = columns & within.keys
    return if overlapping_columns.empty?

    raise ArgumentError, "Query conditions overlap lookup columns: #{overlapping_columns.inspect}"
  end

  def call(params, **context)
    return Success({}) if already_found?(context)

    references, *missing_paths = references(params)
    no_errors = missing_paths.all?(&:empty?)

    if references.values.all?(&:empty?) && no_errors
      Success({})
    elsif !no_errors
      missing_keys_result(*missing_paths)
    else
      find(references, conditions: query_conditions(context))
    end
  end

  private

  def already_found?(context)
    context[context_key].respond_to?(:to_ary)
  end

  def missing_keys_result(missing_paths, invalid_type_paths)
    if omittable || missing_paths.all?(&:empty?) && invalid_type_paths.empty?
      Success({})
    else
      Failure(
        missing_paths.map { |path| { code: :missing, path: } } +
        invalid_type_paths.map { |path| { code: :included, path:, tokens: { allowed_values: repository.keys } } }
      )
    end
  end

  def references(params)
    result = pointers.index_with do |pointer|
      missing_references, references = pointer_references(params, pointer).partition(&:missing?)

      [references, missing_paths(missing_references), invalid_type_paths(references)]
    end

    [result.transform_values(&:first), result.values.flat_map(&:second), result.values.flat_map(&:third)]
  end

  def pointer_references(params, pointer)
    id_references = resolver.call(params, pointer)
    id_references = [] if missing_nested_root?(params, pointer, id_references)

    id_references.map { |reference| build_lookup(params, reference) }
  end

  def missing_nested_root?(params, pointer, references)
    pointer.size > 1 &&
      references.one? &&
      references.first.missing? &&
      params.is_a?(Hash) &&
      !params.key?(pointer.first)
  end

  def build_lookup(params, id_reference)
    Lookup.new(id: id_reference, type: lookup_type(params, id_reference))
  end

  def lookup_type(params, id_reference)
    type_reference(params, id_reference) if polymorphic?
  end

  def type_reference(params, id_reference)
    parent_path = id_reference.path[..-2]
    return missing_type_reference(parent_path) unless parent_path.grep(Symbol) == type[..-2]

    resolver.call(params, [*parent_path, type.last]).first
  end

  def missing_type_reference(parent_path)
    OmniService::Path::Reference.new(path: [*parent_path, type.last], value: nil, resolved: false)
  end

  def missing_paths(missing_references)
    missing_id_paths = omittable ? [] : missing_references.filter_map(&:missing_id_path)
    missing_type_paths = missing_references.filter_map(&:missing_type_path)

    missing_id_paths + missing_type_paths
  end

  def invalid_type_paths(references)
    references.filter_map { |reference| reference.invalid_type_path(repository) }
  end

  def query_conditions(context)
    within.to_h do |column, path|
      reference = context_resolver.call(context, path).first
      raise KeyError, "Missing context path for #{column}: #{reference.path.inspect}" if reference.missing?

      [column, reference.value]
    end
  end

  def find(references, conditions:)
    # TODO: use all columns/pointer somehow
    pointer = pointers.first
    column = columns.first

    if polymorphic?
      type_references = references[pointer].group_by(&:type_value)
      result, not_found_paths = fetch_polymorphic(type_references, column, conditions:)
    else
      result, not_found_paths = fetch(references[pointer], column, repository, conditions:)
    end

    find_result(result, not_found_paths)
  end

  def fetch(references, column, repository, conditions:)
    ids = references.flat_map(&:normalized_value).uniq
    result = repository.get_many(column => ids, **conditions).to_a
    not_found_paths = not_found_paths(result.index_by(&column), references)
    [result, not_found_paths]
  end

  def fetch_polymorphic(type_references, column, conditions:)
    type_references
      .map { |(type, references)| fetch(references.map(&:id), column, repository[type], conditions:) }
      .transpose.map { |a| a.flatten(1) }
  end

  def not_found_paths(entities_index, references)
    references.flat_map do |reference|
      if reference.value.is_a?(Array)
        reference.value.filter_map.with_index { |v, i| [*reference.path, i] if missing_value?(entities_index, v) }
      else
        missing_value?(entities_index, reference.value) ? [reference.path] : []
      end
    end
  end

  def missing_value?(entities_index, value)
    !(entities_index.key?(value) || (nullable && value.nil?))
  end

  def find_result(entities, not_found_paths)
    if not_found_paths.empty?
      Success(context_key => entities.compact)
    else
      not_found_failure(not_found_paths)
    end
  end

  def not_found_failure(paths)
    Failure(paths.map { |path| { code: :not_found, path: } })
  end

  def lookup
    @lookup ||= columns.zip(pointers).to_h
  end

  def pointers
    @pointers ||= if by.is_a?(Hash)
      by.values
    else
      Array.wrap(by || with)
    end.map { |path| Array.wrap(path) }
  end

  def columns
    @columns ||= if by.is_a?(Hash)
      by.keys
    else
      Array.wrap(by || PRIMARY_KEY)
    end
  end

  def polymorphic?
    repository.is_a?(Hash)
  end
end
