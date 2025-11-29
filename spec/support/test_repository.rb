# frozen_string_literal: true

class TestRepository
  include Dry::Monads[:result]
  include Dry::Core::Constants
  include OmniService::Inspect.new(:klass)
  extend Dry::Initializer

  ACTIVE_RECORD_BASE_ERROR = :base

  param :scope, type: OmniService::Types::Interface(:find_by, :where, :new)

  def get_one(id = Undefined, **attributes)
    if Undefined.equal?(id)
      scope.find_by(**attributes)
    else
      scope.find_by(id: id)
    end
  end

  def get_many(**attributes)
    scope.where(**attributes)
  end

  def create(record = nil, **attributes)
    assert_record!(record)

    record ||= scope.new(**attributes)
    record_to_monad(record.tap(&:save))
  end

  private

  def assert_record!(record)
    raise ArgumentError, "Invalid record, expected `#{klass}`, got `#{record.class}`" if record && !record.is_a?(klass)
  end

  def klass
    @klass ||= scope.respond_to?(:klass) ? scope.klass : scope
  end

  def context_key
    @context_key ||= klass.model_name.element.to_sym
  end

  def record_to_monad(record)
    if record.valid?
      Success(context_key => record)
    else
      Failure(failures(record.errors))
    end
  end

  def failures(errors)
    errors.flat_map do |error|
      path = error_path(error)
      failure = { path: path, message: error.message }
      failure[:code] = error.type if error.type != error.message
      failure
    end
  end

  def error_path(error)
    if error.attribute == ACTIVE_RECORD_BASE_ERROR
      []
    else
      error.attribute.to_s.split('.').map do |segment|
        segment.match?(/\A\d+\z/) ? segment.to_i : segment.to_sym
      end
    end
  end
end
