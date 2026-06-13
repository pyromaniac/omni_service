# frozen_string_literal: true

# Routes execution to one component selected by a context value.
#
# Unlike Either, Dispatch does not try another branch when the selected branch
# fails. Branch selection is based only on the resolved selector value.
#
# @example Route by context value
#   dispatch(:role, admin: admin_flow, editor: editor_flow)
#
class OmniService::Dispatch
  extend Dry::Initializer
  include Dry::Equalizer(:selector, :branches, :code, :path)
  include OmniService::Inspect.new(:selector, :branches, :code, :path, hide_defaults: :path)
  include OmniService::Strict

  DEFAULT_ERROR_CODE = :unhandled_dispatch

  param :selector, OmniService::Path::CoercibleNonEmptySegments
  param :branches, OmniService::Types::Hash.map(
    OmniService::Types::Any,
    OmniService::Types::Callable
  ).constrained(min_size: 1)
  option :code, OmniService::Types::Symbol, default: -> { DEFAULT_ERROR_CODE }
  option :path, OmniService::Types::Callable, default: -> { OmniService::Path.new(call_methods: true) }

  def call(*params, **context)
    references = path.call(context, selector)
    raise_ambiguous_selector!(params, context, references) if references.size > 1

    component = component_for(references.first)

    if component
      component.call(*params, **context).merge(operation: self)
    else
      failure_result(params, context, references.first&.path || selector)
    end
  end

  def signature
    @signature ||= compute_signature
  end

  private

  def component_for(reference)
    return unless reference&.resolved?

    component_wrappers[reference.value]
  end

  def component_wrappers
    @component_wrappers ||= branches.transform_values { |component| OmniService::Component.wrap(component) }
  end

  def compute_signature
    signatures = component_wrappers.values.map { |component| component.signature.first }
    return [nil, true] if signatures.include?(nil)

    [signatures.max, true]
  end

  def ambiguous_selector_message(references)
    "Dispatch selector #{selector.inspect} resolved to multiple paths: #{references.map(&:path).inspect}"
  end

  def raise_ambiguous_selector!(params, context, references)
    result = OmniService::Result.build(
      self,
      params:,
      context:,
      errors: [OmniService::Error.build(self, message: ambiguous_selector_message(references), path: selector)]
    )

    raise OmniService::OperationFailed, result
  end

  def failure_result(params, context, path)
    OmniService::Result.build(
      self,
      params:,
      context:,
      errors: [OmniService::Error.build(self, code:, path:)]
    )
  end
end
