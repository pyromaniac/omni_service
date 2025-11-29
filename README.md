# OmniService Framework

Composable business operations with railway-oriented programming.

## Quick Start

```ruby
class Posts::Create
  extend OmniService::Convenience

  option :post_repo, default: -> { PostRepository.new }

  def self.system
    @system ||= sequence(
      input,
      transaction(create, on_success: [notify])
    )
  end

  def self.input
    @input ||= parallel(
      params { required(:title).filled(:string) },
      FindOne.new(:author, repository: AuthorRepository.new, with: :author_id)
    )
  end

  def self.create
    ->(params, author:, **) { post_repo.create(params.merge(author:)) }
  end
end

result = Posts::Create.system.call({ title: 'Hello', author_id: 1 })
result.success?  # => true
result.context   # => { author: <Author>, post: <Post> }
```

## Core Concepts

### Components
Any callable returning `Success(context_hash)` or `Failure(errors)`.

```ruby
# Lambda
->(params, **ctx) { Success(post: Post.new(params)) }

# Class with #call
class ValidateTitle
  def call(params, **)
    params[:title].present? ? Success({}) : Failure([{ code: :blank, path: [:title] }])
  end
end
```

### Result
Structured output with: `context`, `params`, `errors`, `on_success`, `on_failure`.

```ruby
result.success?  # no errors?
result.failure?  # has errors?
result.context   # { post: <Post>, author: <Author> }
result.errors    # [#<Error code=:blank path=[:title]>]
result.to_monad  # Success(result) or Failure(result)
```

## Composition

### sequence
Runs components in order. Short-circuits on first failure.

```ruby
sequence(
  validate_params,  # Failure stops here
  find_author,      # Adds :author to context
  create_post       # Receives :author
)
```

### parallel
Runs all components, collects all errors.

```ruby
parallel(
  validate_title,  # => Failure([{ path: [:title], code: :blank }])
  validate_body    # => Failure([{ path: [:body], code: :too_short }])
)
# => Result with both errors collected
```

### transaction
Wraps in DB transaction with callbacks.

```ruby
transaction(
  sequence(validate, create),
  on_success: [send_email, update_cache],  # After commit
  on_failure: [log_error]                   # After rollback
)
```

### namespace
Scopes params/context under a key.

```ruby
# params: { post: { title: 'Hi' }, author: { name: 'John' } }
parallel(
  namespace(:post, validate_post),
  namespace(:author, validate_author)
)
# Errors: [:post, :title], [:author, :name]
```

### collection
Iterates over arrays.

```ruby
# params: { comments: [{ body: 'A' }, { body: '' }] }
collection(validate_comment, namespace: :comments)
# Errors: [:comments, 1, :body]
```

### optional
Swallows failures.

```ruby
sequence(
  create_user,
  optional(fetch_avatar),  # Failure won't stop pipeline
  send_email
)
```

### shortcut
Early exit on success.

```ruby
sequence(
  shortcut(find_existing),  # Found? Exit early
  create_new                 # Not found? Create
)
```

## Entity Lookup

### FindOne

```ruby
FindOne.new(:post, repository: repo)
# params: { post_id: 1 } => Success(post: <Post>)

# Options
FindOne.new(:post, repository: repo, with: :slug)           # Custom param key
FindOne.new(:post, repository: repo, by: [:author_id, :slug])  # Multi-column
FindOne.new(:post, repository: repo, nullable: true)        # Allow nil
FindOne.new(:post, repository: repo, omittable: true)       # Allow missing key
FindOne.new(:post, repository: repo, skippable: true)       # Skip not found

# Polymorphic
FindOne.new(:item, repository: { 'Post' => post_repo, 'Article' => article_repo })
# params: { item_id: 1, item_type: 'Post' }
```

### FindMany

```ruby
FindMany.new(:posts, repository: repo)
# params: { post_ids: [1, 2, 3] } => Success(posts: [...])

# Nested IDs
FindMany.new(:products, repository: repo, by: { id: [:items, :product_id] })
# params: { items: [{ product_id: 1 }, { product_id: [2, 3] }] }
```

## Error Format

```ruby
Failure(:not_found)
# => Error(code: :not_found, path: [])

Failure([{ code: :blank, path: [:title] }])
# => Error(code: :blank, path: [:title])

Failure([{ code: :too_short, path: [:body], tokens: { min: 100 } }])
# => Error with interpolation tokens for i18n
```

## Async Execution

```ruby
class Posts::Create
  extend OmniService::Convenience
  extend OmniService::Async::Convenience[queue: 'default']

  def self.system
    @system ||= sequence(...)
  end
end

Posts::Create.system_async.call(params, context)
# => Success(job_id: 'abc-123')
```

## Strict Mode

```ruby
operation.call!(params)  # Raises OmniService::OperationFailed on failure

# Or via convenience
Posts::Create.system!.call(params)
```
