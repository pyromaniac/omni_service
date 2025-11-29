# frozen_string_literal: true

RSpec::Matchers.define :be_success do |expected = Dry::Core::Undefined|
  if Dry::Core::Undefined.equal?(expected) # default be_success behavior
    match(&:success?)
    failure_message { |actual| "expected `#{actual.inspect}.success?` to be truthy, got false" }
  else # match success monad value
    diffable

    match(notify_expectation_failures: true) do |actual|
      expect(actual).to be_a(Dry::Monads::Success)
      @actual = actual.value!
      values_match?(expected, @actual)
    end

    failure_message { |actual| "expected #{actual.inspect} to be a Success(#{expected.inspect})" }
    description { "be Success(#{expected.inspect})" }
  end
end

RSpec::Matchers.define :be_failure do |expected = Dry::Core::Undefined|
  if Dry::Core::Undefined.equal?(expected) # default be_failure behavior
    match(&:failure?)
    failure_message { |actual| "expected `#{actual.inspect}.failure?` to be truthy, got false" }
  else # match failure monad value
    diffable

    match(notify_expectation_failures: true) do |actual|
      expect(actual).to be_a(Dry::Monads::Failure)
      @actual = actual.failure
      values_match?(expected, @actual)
    end

    failure_message { |actual| "expected #{actual.inspect} to be a Failure(#{expected.inspect})" }
    description { "be Failure(#{expected.inspect})" }
  end
end
