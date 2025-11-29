# frozen_string_literal: true

# Finds a single entity by ID or attributes via repository#get_one.
# Skips lookup if entity already exists in context.
#
# Options:
# - :with - param key for lookup (default: :"#{context_key}_id")
# - :by - column mapping, supports nested paths: { id: [:deep, :post_id] }
# - :repository - single repo or Hash for polymorphic lookup
# - :type - path to type discriminator for polymorphic lookup
#
# Flags:
# - :nullable - allow nil param value, returns Success(key: nil)
# - :omittable - allow missing param key, returns Success({})
# - :skippable - return Success({}) when entity not found instead of Failure
#
# @example Basic lookup
#   FindOne.new(:post, repository: post_repo)
#   # params: { post_id: 123 } => Success(post: <Post>)
#
# @example Custom lookup key
#   FindOne.new(:post, repository: post_repo, with: :slug)
#   # params: { slug: 'hello' } => get_one(id: 'hello')
#
# @example Nested param path
#   FindOne.new(:post, repository: post_repo, by: { id: [:data, :post_id] })
#   # params: { data: { post_id: 123 } } => get_one(id: 123)
#
# @example Multi-column lookup
#   FindOne.new(:post, repository: post_repo, by: [:author_id, :slug])
#   # params: { author_id: 1, slug: 'hi' } => get_one(author_id: 1, slug: 'hi')
#
# @example Polymorphic lookup
#   FindOne.new(:comment, repository: { 'Post' => post_repo, 'Article' => article_repo })
#   # params: { comment_id: 1, comment_type: 'Post' } => post_repo.get_one(id: 1)
#
# @example Nullable association (for clearing)
#   FindOne.new(:category, repository: repo, nullable: true)
#   # params: { category_id: nil } => Success(category: nil)
#
# @example Omittable for partial updates
#   FindOne.new(:category, repository: repo, omittable: true)
#   # params: {} => Success({}) - doesn't touch association
#
# @example Skippable for soft-deleted lookups
#   FindOne.new(:post, repository: repo, skippable: true)
#   # params: { post_id: 999 } (not found) => Success({})
#
class OmniService::FindOne
  extend Dry::Initializer
  include Dry::Monads[:result]
  include OmniService::Inspect.new(:context_key, :repository, :lookup, :omittable, :nullable)

  PRIMARY_KEY = :id

  param :context_key, OmniService::Types::Symbol
  option :repository, OmniService::Types::Interface(:get_one) |
    OmniService::Types::Hash.map(OmniService::Types::String, OmniService::Types::Interface(:get_one))
  option :type, OmniService::Types::Coercible::Array.of(OmniService::Types::Symbol), default: proc { :"#{context_key}_type" }
  option :with, OmniService::Types::Symbol, default: proc { :"#{context_key}_id" }
  option :by, OmniService::Types::Symbol |
    OmniService::Types::Array.of(OmniService::Types::Symbol) |
    OmniService::Types::Hash.map(OmniService::Types::Symbol, OmniService::Types::Symbol |
      OmniService::Types::Array.of(OmniService::Types::Symbol)), optional: true
  option :omittable, OmniService::Types::Bool, default: proc { false }
  option :nullable, OmniService::Types::Bool, default: proc { false }
  option :skippable, OmniService::Types::Bool, default: proc { false }

  def call(params, **context)
    return Success({}) if already_found?(context)

    missing_keys = missing_keys(params, pointers)
    return missing_keys_result(missing_keys, context) unless missing_keys.empty?

    values = values(params)
    return Success(context_key => nil) if nullable && values.all?(&:nil?)

    repository = resolve_repository(params)
    return repository_failure(params, values) unless repository

    find(values, repository:)
  end

  private

  def already_found?(context)
    nullable ? context.key?(context_key) : !context[context_key].nil?
  end

  def missing_keys(params, paths)
    paths.reject do |path|
      deep_object = path.one? ? params : params.dig(*path[..-2])
      deep_object.is_a?(Hash) && deep_object.key?(path.last)
    end
  end

  def missing_keys_result(missing_keys, context)
    if nil_in_context?(context)
      not_found_failure
    elsif omittable && missing_keys.size == pointers.size
      Success({})
    else
      missing_keys_failure(missing_keys)
    end
  end

  def nil_in_context?(context)
    !nullable && context.key?(context_key) && context[context_key].nil?
  end

  def values(params)
    pointers.map { |pointer| params.dig(*pointer) }
  end

  def resolve_repository(params)
    if repository.is_a?(Hash)
      repository[params.dig(*type)]
    else
      repository
    end
  end

  def repository_failure(params, values)
    missing_keys = missing_keys(params, [type])

    if values.all?(&:nil?)
      not_found_failure
    elsif missing_keys.empty?
      Failure([{ code: :included, path: type, tokens: { allowed_values: repository.keys } }])
    else
      missing_keys_failure(missing_keys)
    end
  end

  def find(values, repository:)
    result = repository.get_one(**columns.zip(values).to_h)

    if result.nil?
      skippable ? Success({}) : not_found_failure
    else
      Success(context_key => result)
    end
  end

  def missing_keys_failure(paths)
    Failure(paths.map { |path| { code: :missing, path: } })
  end

  def not_found_failure
    Failure(pointers.map { |pointer| { code: :not_found, path: pointer } })
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
end
