# frozen_string_literal: true

require 'dry/core/constants'
require 'dry/monads'
require 'dry/monads/do'
require 'dry-struct'
require 'dry-initializer'
require 'dry/types'
require 'dry/validation'
require 'active_support'
require 'concurrent-ruby'

# Framework for composable business operations with railway-oriented programming.
#
# Core concepts:
# - Components: callables returning Success/Failure monads
# - Results: structured output with context, params, and errors
# - Composition: sequence, parallel, transaction, namespace, collection
#
# @example Simple operation
#   class Posts::Create
#     extend OmniService::Convenience
#
#     option :post_repo, default: -> { PostRepository.new }
#
#     def self.system
#       @system ||= sequence(
#         validate_params,
#         transaction(create_post, on_success: [notify_subscribers])
#       )
#     end
#   end
#
#   result = Posts::Create.system.call({ title: 'Hello' }, current_user: user)
#   result.success?  # => true
#   result.context   # => { post: <Post> }
#
# @see OmniService::Convenience DSL for building operations
# @see OmniService::Result structured result object
#
module OmniService
  include Dry::Core::Constants

  Types = Dry.Types()

  class << self
    def sync_callbacks?
      !!Thread.current[:omni_service_sync_callbacks]
    end

    def with_sync_callbacks(value = true) # rubocop:disable Style/OptionalBooleanParameter
      old_value = Thread.current[:omni_service_sync_callbacks]
      Thread.current[:omni_service_sync_callbacks] = value
      yield
    ensure
      Thread.current[:omni_service_sync_callbacks] = old_value
    end
  end
end

require_relative 'omni_service/version'
require_relative 'omni_service/strict'
require_relative 'omni_service/helpers'
require_relative 'omni_service/inspect'
require_relative 'omni_service/error'
require_relative 'omni_service/result'
require_relative 'omni_service/component'
require_relative 'omni_service/context'
require_relative 'omni_service/params'
require_relative 'omni_service/sequence'
require_relative 'omni_service/parallel'
require_relative 'omni_service/collection'
require_relative 'omni_service/optional'
require_relative 'omni_service/find_one'
require_relative 'omni_service/find_many'
require_relative 'omni_service/namespace'
require_relative 'omni_service/shortcut'
require_relative 'omni_service/transaction'
require_relative 'omni_service/convenience'
require_relative 'omni_service/async'
