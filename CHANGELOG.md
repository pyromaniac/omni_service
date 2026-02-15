## [Unreleased]

### Breaking

- **Context**: `Context.new` now requires `raise_on_error`, and validators must respond to `#call` and `#try`; `context()` no longer raises on invalid context, use `context!` to raise
- **Chain**: Sequence component renamed to `Chain` (use `chain(...)` or `OmniService::Chain`)
- **Component**: No longer mixes in `Dry::Monads[:result]`; include it explicitly if you rely on `Success`/`Failure` helpers
- **Namespace**: Replaced `shared_params: true` with `from: []`; new `from:` option specifies extraction path (defaults to namespace)
- **Result**: `to_monad` now returns `Success(context)` / `Failure(errors)` instead of wrapping the whole `Result`

### Changed

- **Chain**: Signature now uses the first component that consumes params (skips leading context-only components)
- **Parallel**: Signature calculation returns sum of component signatures (distribution semantics)
- **Parallel**: Refactored params accumulation into separate methods for clarity
- **Namespace**: Signature now returns `[1, true]` by default, or delegates to component when `from: []`
- **Namespace**: Now accepts array paths for deep nesting (e.g., `namespace([:user, :profile], component)`); single symbols are coerced to arrays
- **Namespace**: Context merging simplified to use `deep_merge`
- **Namespace**: Fixed params extraction when inner component has splat signature (`nil`)

### Added

- **Context**: `context!` convenience for raising on invalid context
- **Either**: New composition component that tries components in order and returns the first success; useful for fallback/recovery patterns with transaction isolation support
- **Fanout**: New composition component that fans out shared params to all components and collects all errors
- **Parallel**: `pack_params: true` option now supports merging multiple params by index position, not just first param
- **Collection**: Support for hash-based collections in addition to arrays; keys are preserved in output
- **Split**: New composition component that distributes params and fails fast on first failure or shortcut

### Fixed

- **Namespace**: Correctly handles components with splat signatures that consume all params
- **Parallel**: Proper leftover params handling in distribution mode
- **Context**: Missing optional keys no longer get written into context on success
- **Helpers**: `process_errors` now accepts arrays of errors in addition to failed monads

## [0.1.0] - 2025-11-27

- Initial release
