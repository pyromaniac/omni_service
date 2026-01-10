## [Unreleased]

### Changed

- **Sequence**: Simplified signature calculation to use first component's signature directly instead of finding max across all components
- **Parallel**: Signature calculation now always returns sum of component signatures (distribution semantics)
- **Parallel**: Refactored params accumulation into separate methods for clarity
- **Namespace**: Signature now returns `[1, true]` by default, or delegates to component when `shared_params: true`
- **Namespace**: Fixed params extraction when inner component has splat signature (`nil`)

### Added

- **Parallel**: `pack_params: true` option now supports merging multiple params by index position, not just first param
- **Collection**: Support for hash-based collections in addition to arrays; keys are preserved in output

### Fixed

- **Namespace**: Correctly handles components with splat signatures that consume all params
- **Parallel**: Proper leftover params handling in distribution mode

## [0.1.0] - 2025-11-27

- Initial release
