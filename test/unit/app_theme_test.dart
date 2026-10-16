import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/theme/app_theme.dart';
import 'package:vehicle_history/app/theme/status_colors.dart';

void main() {
  group('AppTheme', () {
    test('light and dark themes use Material 3 with the right brightness', () {
      expect(AppTheme.light.useMaterial3, isTrue);
      expect(AppTheme.dark.useMaterial3, isTrue);
      expect(AppTheme.light.colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark.colorScheme.brightness, Brightness.dark);
    });

    test('both colour schemes are generated from the single seed', () {
      // Regenerating each scheme from the seed must give exactly the scheme
      // the theme carries: no colour was picked by hand.
      expect(
        AppTheme.light.colorScheme,
        ColorScheme.fromSeed(
          seedColor: AppTheme.seedColor,
          brightness: Brightness.light,
        ),
      );
      expect(
        AppTheme.dark.colorScheme,
        ColorScheme.fromSeed(
          seedColor: AppTheme.seedColor,
          brightness: Brightness.dark,
        ),
      );
    });

    test('each theme carries the StatusColors for its brightness', () {
      expect(AppTheme.light.extension<StatusColors>(), StatusColors.light);
      expect(AppTheme.dark.extension<StatusColors>(), StatusColors.dark);
    });
  });

  group('StatusColors', () {
    const a = StatusColors.light;
    const b = StatusColors.dark;

    test('lerp at t = 0 returns the start colours', () {
      _expectSameColors(a.lerp(b, 0), a);
    });

    test('lerp at t = 1 returns the end colours', () {
      _expectSameColors(a.lerp(b, 1), b);
    });

    test('lerp at t = 0.5 returns the midpoint', () {
      expect(a.lerp(b, 0.5).overdue, Color.lerp(a.overdue, b.overdue, 0.5));
      expect(a.lerp(b, 0.5).onOk, Color.lerp(a.onOk, b.onOk, 0.5));
    });

    test('lerp with a null other returns the same instance', () {
      expect(a.lerp(null, 0.5), same(a));
    });

    test('copyWith replaces only the given colours', () {
      const red = Color(0xFFFF0000);
      final copy = a.copyWith(ok: red);
      expect(copy.ok, red);
      expect(copy.overdue, a.overdue);
      expect(copy.onOverdue, a.onOverdue);
      expect(copy.dueSoon, a.dueSoon);
      expect(copy.onDueSoon, a.onDueSoon);
      expect(copy.onOk, a.onOk);
    });
  });
}

/// Asserts that [actual] holds exactly the colours of [expected].
void _expectSameColors(StatusColors actual, StatusColors expected) {
  expect(actual.overdue, expected.overdue);
  expect(actual.onOverdue, expected.onOverdue);
  expect(actual.dueSoon, expected.dueSoon);
  expect(actual.onDueSoon, expected.onDueSoon);
  expect(actual.ok, expected.ok);
  expect(actual.onOk, expected.onOk);
}
