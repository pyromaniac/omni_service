# frozen_string_literal: true

# Wraps operation execution in a background job (ActiveJob).
# Returns immediately with Success(job: ...) instead of operation result.
#
# @example Direct usage
#   async = OmniService::Async.new(Posts::Create, :system, job_class: PostJob)
#   async.call({ title: 'Hello' }, author: user)
#   # => Success(job: #<OperationJob:...>)
#
# @example Via Convenience module (recommended)
#   class Posts::Create
#     extend OmniService::Convenience
#     extend OmniService::Async::Convenience[queue: 'default', retry: 3]
#
#     def self.system
#       @system ||= sequence(validate_params, create_post)
#     end
#   end
#
#   Posts::Create.system_async.call({ title: 'Hello' }, author: user)
#
# @example Scheduling with ActiveJob options
#   Posts::Create.system_async.set(wait: 5.minutes).call(params)
#   Posts::Create.system_async.set(wait_until: Date.tomorrow.noon, queue: 'low').call(params)
#
class OmniService::Async
  extend Dry::Initializer
  include Dry::Equalizer(:operation_class, :operation_method, :job_class, :job_options)
  include OmniService::Inspect.new(:operation_class, :operation_method, :job_class, :job_options)
  include Dry::Monads[:result]

  # A helper module to simplify async operation creation.
  #
  # @example Basic usage
  #
  #   class MyOperation
  #     extend OmniService::Convenience
  #     extend OmniService::Async::Convenience[queue: 'important', retry: 3]
  #
  #     def self.system
  #       @system ||= sequence(...)
  #     end
  #   end
  #
  #   MyOperation.system_async.call!(...)
  #
  # @example With custom job class
  #
  #   class MyOperation
  #     extend OmniService::Convenience
  #     extend OmniService::Async::Convenience[job_class: MyCustomJob]
  #
  #     def self.system
  #       @system ||= sequence(...)
  #     end
  #   end
  #
  module Convenience
    def self.[](**job_options)
      job_class = job_options.delete(:job_class) || OperationJob

      Module.new do
        define_singleton_method(:extended) do |base|
          base.extend OmniService::Async::Convenience
          base.instance_variable_set(:@job_options, job_options)
          base.instance_variable_set(:@job_class, job_class)
        end
      end
    end

    def method_missing(name, ...)
      name_without_suffix = name.to_s.delete_suffix('_async').to_sym

      if name.to_s.end_with?('_async') && respond_to?(name_without_suffix)
        ivar_name = :"@#{name}"

        if instance_variable_defined?(ivar_name)
          instance_variable_get(ivar_name)
        else
          instance_variable_set(
            ivar_name,
            OmniService::Async.new(
              self,
              name_without_suffix,
              job_class: @job_class || OperationJob,
              job_options: @job_options || {}
            )
          )
        end
      else
        super
      end
    end

    def respond_to_missing?(name, *)
      (name.to_s.end_with?('_async') && respond_to?(name.to_s.delete_suffix('_async').to_sym)) || super
    end
  end

  param :operation_class, OmniService::Types::Class
  param :operation_method, OmniService::Types::Symbol
  option :job_class, OmniService::Types::Class, default: proc { OperationJob }
  option :job_options, OmniService::Types::Hash, default: proc { {} }

  # Returns a new Async instance with merged job options.
  #
  # @example Schedule job to run in 5 minutes
  #   Posts::Create.system_async.set(wait: 5.minutes).call(params)
  #
  # @example Schedule job at specific time with custom queue
  #   Posts::Create.system_async.set(wait_until: Date.tomorrow.noon, queue: 'low').call(params)
  #
  # @param options [Hash] ActiveJob options (wait:, wait_until:, queue:, priority:, etc.)
  # @return [OmniService::Async] new instance with merged options
  #
  def set(**options)
    self.class.new(operation_class, operation_method, job_class:, job_options: job_options.merge(options))
  end

  def call(*params, **context)
    job = job_class.set(job_options).perform_later(operation_class, operation_method, params, context)
    Success(job:)
  end
end
