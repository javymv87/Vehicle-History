/// Marker default for nullable `copyWith` parameters.
///
/// A plain `String? x` parameter cannot tell "not passed" apart from
/// "explicitly set to null". Domain models declare such parameters as
/// `Object? x = unset` and keep the current value only when they still hold
/// this marker, so callers can clear an optional field with `x: null`.
const Object unset = _Unset();

/// Type of [unset]; private so no other value can be mistaken for it.
class _Unset {
  const _Unset();
}
