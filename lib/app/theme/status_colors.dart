import 'package:flutter/material.dart';

/// Semantic colours for the three deadline states used across the app:
/// overdue, due soon and ok.
///
/// Registered as a [ThemeExtension] on both the light and the dark theme, so
/// widgets read them with `Theme.of(context).extension<StatusColors>()!` and
/// automatically get the variant matching the current brightness.
///
/// Each state has a main colour and an "on" colour for text and icons drawn
/// on top of it. Every main colour reaches at least WCAG AA (4.5:1) both
/// against its "on" colour and against the theme surfaces, so it can be used
/// either as a fill or directly as a text/icon colour.
///
/// **Colour is never the only signal.** A status must always be shown with
/// an icon **and** a text label as well as its colour, for colour-blind users
/// and because colours render differently in dark mode
/// (see `Docs/07_design_and_theming.md`).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  /// Creates a set of status colours.
  const StatusColors({
    required this.overdue,
    required this.onOverdue,
    required this.dueSoon,
    required this.onDueSoon,
    required this.ok,
    required this.onOk,
  });

  /// Status colours tuned for the light theme: dark tones on light surfaces.
  static const StatusColors light = StatusColors(
    overdue: Color(0xFFB3261E),
    onOverdue: Color(0xFFFFFFFF),
    dueSoon: Color(0xFF8A5100),
    onDueSoon: Color(0xFFFFFFFF),
    ok: Color(0xFF1B6D2F),
    onOk: Color(0xFFFFFFFF),
  );

  /// Status colours tuned for the dark theme: light tones on dark surfaces.
  static const StatusColors dark = StatusColors(
    overdue: Color(0xFFFFB4AB),
    onOverdue: Color(0xFF690005),
    dueSoon: Color(0xFFFFB95C),
    onDueSoon: Color(0xFF462A00),
    ok: Color(0xFF8BD78F),
    onOk: Color(0xFF00390F),
  );

  /// Red: a deadline that has already passed.
  final Color overdue;

  /// Text and icon colour drawn on top of [overdue].
  final Color onOverdue;

  /// Amber: a deadline that is approaching.
  final Color dueSoon;

  /// Text and icon colour drawn on top of [dueSoon].
  final Color onDueSoon;

  /// Green: nothing pending.
  final Color ok;

  /// Text and icon colour drawn on top of [ok].
  final Color onOk;

  @override
  StatusColors copyWith({
    Color? overdue,
    Color? onOverdue,
    Color? dueSoon,
    Color? onDueSoon,
    Color? ok,
    Color? onOk,
  }) {
    return StatusColors(
      overdue: overdue ?? this.overdue,
      onOverdue: onOverdue ?? this.onOverdue,
      dueSoon: dueSoon ?? this.dueSoon,
      onDueSoon: onDueSoon ?? this.onDueSoon,
      ok: ok ?? this.ok,
      onOk: onOk ?? this.onOk,
    );
  }

  @override
  StatusColors lerp(StatusColors? other, double t) {
    // Nothing to interpolate towards: keep the current colours unchanged.
    if (other == null) {
      return this;
    }
    // `Color.lerp` only returns null when both ends are null, which cannot
    // happen here because every field is non-nullable.
    return StatusColors(
      overdue: Color.lerp(overdue, other.overdue, t)!,
      onOverdue: Color.lerp(onOverdue, other.onOverdue, t)!,
      dueSoon: Color.lerp(dueSoon, other.dueSoon, t)!,
      onDueSoon: Color.lerp(onDueSoon, other.onDueSoon, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      onOk: Color.lerp(onOk, other.onOk, t)!,
    );
  }
}
