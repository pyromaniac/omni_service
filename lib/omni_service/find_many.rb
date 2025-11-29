# frozen_string_literal: true

# Finds multiple entities by IDs via repository#get_many.
# Accepts array of IDs or nested structures with IDs.
# Returns deduplicated entities; reports not-found errors with array indices.
#
# Options:
# - :with - param key for IDs array (default: :"#{context_key.singularize}_ids")
# - :by - column mapping with nested paths: { id: [:items, :product_id] }
# - :repository - single repo or Hash for polymorphic lookup
# - :type - path to type discriminator for polymorphic lookup
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
#   FindMany.new(:products, repository: repo, by: { id: [:items, :product_id] })
#   # params: { items: [{ product_id: 1 }, { product_id: [2, 3] }] }
#   # => Success(products: [<Product>, <Product>, <Product>])
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
# @example Nullable for optional associations
#   FindMany.new(:tags, repository: repo, nullable: true)
#   # params: { tag_ids: [1, nil, 2] } => Success(tags: [<Tag>, <Tag>])
#
class OmniService::FindMany
  extend Dry::Initializer
  include Dry::Core::Constants
  include Dry::Monads[:result]
  include OmniService::Inspect.new(:context_key, :repository, :lookup, :omittable)

  PRIMARY_KEY = :id

  Reference = Class.new(Dry::Struct) do
    attribute :path, OmniService::Types::Array.of(OmniService::Types::Symbol | OmniService::Types::Integer)
    attribute :value, OmniService::Types::Any

    def undefined?
      Undefined.equal?(value)
    end

    def missing_id_path
      path if undefined?
    end

    def missing_type_path; end

    def normalized_value
      Array.wrap(value)
    end
  end

  PolymorphicReference = Class.new(Dry::Struct) do
    attribute :type, Reference
    attribute :id, Reference

    delegate :path, :missing_id_path, to: :id

    def undefined?
      type.undefined? || id.undefined?
    end

    def missing_type_path
      type.missing_id_path unless id.value.nil?
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
  option :omittable, OmniService::Types::Bool, default: proc { false }
  option :nullable, OmniService::Types::Bool, default: proc { false }

  def call(params, **context)
    return Success({}) if already_found?(context)

    references, *missing_paths = references(params)
    no_errors = missing_paths.all?(&:empty?)

    if references.values.all?(&:empty?) && no_errors
      Success({})
    elsif !no_errors
      missing_keys_result(*missing_paths)
    else
      find(references)
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
      undefined_references, references = pointer_references(params, *pointer).partition(&:undefined?)

      [references, missing_paths(undefined_references), invalid_type_paths(references)]
    end

    [result.transform_values(&:first), result.values.flat_map(&:second), result.values.flat_map(&:third)]
  end

  def pointer_references(params, segment = nil, *pointer, path: [], type_reference: Undefined)
    return [id_reference(params, path, type_reference)] unless segment

    case params
    when Array
      params.flat_map.with_index do |value, index|
        pointer_references(value, segment, *pointer, path: [*path, index], type_reference:)
      end
    when Hash
      hash_pointer_references(params, segment, *pointer, path:, type_reference:)
    else
      []
    end
  end

  def hash_pointer_references(params, segment, *pointer, path:, type_reference:)
    type_reference = type_reference(params, path) if polymorphic? && path.grep(Symbol) == type[..-2]
    pointer_references(
      params.key?(segment) ? params[segment] : Undefined,
      *pointer,
      path: [*path, segment],
      type_reference:
    )
  end

  def type_reference(params, path)
    Reference.new(path: [*path, type.last], value: params.key?(type.last) ? params[type.last] : Undefined)
  end

  def id_reference(params, path, type_reference)
    id_reference = Reference.new(path:, value: params)
    polymorphic? ? PolymorphicReference.new(type: type_reference, id: id_reference) : id_reference
  end

  def missing_paths(undefined_references)
    missing_id_paths = omittable ? [] : undefined_references.filter_map(&:missing_id_path)
    missing_type_paths = undefined_references.filter_map(&:missing_type_path)

    missing_id_paths + missing_type_paths
  end

  def invalid_type_paths(references)
    if polymorphic?
      references.filter_map { |reference| reference.type.path unless repository.key?(reference.type.value) }
    else
      []
    end
  end

  def find(references)
    # TODO: use all columns/pointer somehow
    pointer = pointers.first
    column = columns.first

    if polymorphic?
      type_references = references[pointer].group_by { |reference| reference.type.value }
      result, not_found_paths = fetch_polymorphic(type_references, column)
    else
      result, not_found_paths = fetch(references[pointer], column, repository)
    end

    find_result(result, not_found_paths)
  end

  def fetch(references, column, repository)
    ids = references.flat_map(&:normalized_value).uniq
    result = repository.get_many(column => ids).to_a
    not_found_paths = not_found_paths(result.index_by(&column), references)
    [result, not_found_paths]
  end

  def fetch_polymorphic(type_references, column)
    type_references
      .map { |(type, references)| fetch(references.map(&:id), column, repository[type]) }
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
