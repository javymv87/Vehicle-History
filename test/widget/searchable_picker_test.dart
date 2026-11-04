import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/l10n/app_localizations.dart';
import 'package:vehicle_history/shared/widgets/searchable_picker.dart';

/// The shared full-screen picker: "Other…" stays reachable and nothing
/// overflows, also on a screen as short as a phone in landscape with the
/// keyboard open.
void main() {
  final items = [for (var i = 1; i <= 30; i++) 'Item $i'];

  /// Pumps a page whose button opens the picker on a [size] screen and
  /// stores what it resolves to in [result].
  Future<void> open(
    WidgetTester tester,
    Size size,
    void Function(PickerResult<String>?) result,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result(
              await showSearchablePicker<String>(
                context: context,
                title: 'Pick one',
                search: (query) => [
                  for (final item in items)
                    if (item.contains(query)) item,
                ],
                labelOf: (item) => item,
                otherLabel: 'Other…',
                showAllLabel: 'Show all',
                searchAll: (query) => items,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('on a tall screen "Other…" is pinned and visible',
      (tester) async {
    await open(tester, const Size(400, 800), (_) {});
    expect(tester.takeException(), isNull);
    expect(find.text('Other…').hitTestable(), findsOneWidget);
  });

  testWidgets('on a short screen everything scrolls, without overflow',
      (tester) async {
    PickerResult<String>? picked;
    await open(tester, const Size(800, 250), (value) => picked = value);
    expect(tester.takeException(), isNull);
    // The search box and the list share the space; "Other…" is at the end.
    expect(find.text('Other…').hitTestable(), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Other…'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Other…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other…'));
    await tester.pumpAndSettle();
    expect(picked, isA<PickedOther<String>>());
  });
}
