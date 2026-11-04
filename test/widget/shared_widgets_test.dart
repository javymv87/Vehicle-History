import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/app/theme/app_theme.dart';
import 'package:vehicle_history/l10n/app_localizations.dart';
import 'package:vehicle_history/shared/widgets/action_dialog.dart';
import 'package:vehicle_history/shared/widgets/action_label.dart';
import 'package:vehicle_history/shared/widgets/app_card.dart';
import 'package:vehicle_history/shared/widgets/app_chip.dart';
import 'package:vehicle_history/shared/widgets/empty_state.dart';
import 'package:vehicle_history/shared/widgets/form_section.dart';
import 'package:vehicle_history/shared/widgets/history_line.dart';
import 'package:vehicle_history/shared/widgets/list_row.dart';
import 'package:vehicle_history/shared/widgets/list_sections.dart';
import 'package:vehicle_history/shared/widgets/section_label.dart';
import 'package:vehicle_history/shared/widgets/state_line.dart';
import 'package:vehicle_history/shared/widgets/status_card.dart';

/// Smoke tests of the shared archetype widgets (`Docs/07`, "Arquetipos"):
/// each one builds in the light and the dark theme and shows its text.
void main() {
  /// Pumps [child] on a page of the app's [theme], localised in English.
  Future<void> pump(WidgetTester tester, ThemeData theme, Widget child) =>
      tester.pumpWidget(
        MaterialApp(
          theme: theme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: child),
        ),
      );

  /// Runs [body] once per theme.
  void inBothThemes(
    String description,
    Future<void> Function(WidgetTester tester, ThemeData theme) body,
  ) {
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      testWidgets('$description ($name)', (tester) => body(tester, theme));
    }
  }

  inBothThemes('AppCard shows its label upper case, its trailing and child',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const AppCard(
        label: 'Last time',
        trailing: Text('chip'),
        child: Text('3 Nov 2026'),
      ),
    );
    expect(find.text('LAST TIME'), findsOneWidget);
    expect(find.text('chip'), findsOneWidget);
    expect(find.text('3 Nov 2026'), findsOneWidget);
  });

  inBothThemes('AppCard tinted takes the state colour from the theme',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const AppCard(tint: AppCardTint.overdue, child: Text('late')),
    );
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('late'), matching: find.byType(Container)),
    );
    final decoration = container.decoration! as BoxDecoration;
    final color = appCardTintColor(AppCardTint.overdue, theme);
    expect(decoration.color, color.withValues(alpha: 0.10));
    expect(decoration.border, isNotNull);
  });

  inBothThemes('SectionLabel is upper case with an optional trailing',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const SectionLabel('By km', trailing: Icon(Icons.info_outline)),
    );
    expect(find.text('BY KM'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  inBothThemes('StateLine shows the icon and the text in the colour',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      Column(
        children: [
          StateLine(
            icon: Icons.schedule,
            text: 'Due soon · in 12 days',
            color: theme.colorScheme.error,
          ),
          StateLine.heading(
            icon: Icons.error_outline,
            text: 'Overdue',
            color: theme.colorScheme.error,
          ),
        ],
      ),
    );
    expect(find.text('Due soon · in 12 days'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline)).size,
      20,
    );
  });

  inBothThemes('AppChip shows its label and icon in every variant',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const Row(
        children: [
          AppChip(label: 'Custom'),
          AppChip(
            label: 'Less strict',
            icon: Icons.warning_amber_outlined,
            iconLabel: 'warning',
            variant: AppChipVariant.warning,
          ),
          AppChip(label: 'Info', variant: AppChipVariant.info),
        ],
      ),
    );
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Less strict'), findsOneWidget);
    expect(find.text('Info'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
  });

  inBothThemes('ListRow shows its lines and chips and reacts to a tap',
      (tester, theme) async {
    var tapped = false;
    await pump(
      tester,
      theme,
      ListRow(
        leading: const Icon(Icons.build),
        title: 'Engine oil',
        secondLine: const Text('Overdue'),
        thirdLine: 'Fiat Punto',
        trailing: const [AppChip(label: 'Custom'), AppChip(label: 'Snoozed')],
        onTap: () => tapped = true,
      ),
    );
    expect(find.text('Engine oil'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Fiat Punto'), findsOneWidget);
    expect(find.text('Snoozed'), findsOneWidget);
    await tester.tap(find.text('Engine oil'));
    expect(tapped, isTrue);
  });

  inBothThemes('ListSections skips empty sections and folds the last one',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      ListSections<String>(
        sections: const [
          ListSection(title: 'Overdue', items: ['Oil']),
          ListSection(title: 'Due soon', items: []),
          ListSection(title: 'Up to date', items: ['Coolant', 'Brakes']),
        ],
        folded: const ListSection(title: 'Completed (1)', items: ['Tax']),
        row: (item) => ListTile(title: Text(item)),
      ),
    );
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Due soon'), findsNothing);
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Brakes'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    // Folded until tapped.
    expect(find.text('Tax'), findsNothing);
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Tax'), findsOneWidget);
  });

  inBothThemes('EmptyState shows the icon, the message and the detail',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const EmptyState(
        icon: Icons.notifications_none,
        message: 'Nothing due',
        detail: '2 reminders up to date',
      ),
    );
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    expect(find.text('Nothing due'), findsOneWidget);
    expect(find.text('2 reminders up to date'), findsOneWidget);
  });

  inBothThemes('StatusCard shows the word, the hero value and the line',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const StatusCard(
        tint: AppCardTint.ok,
        icon: Icons.check_circle_outline,
        word: 'Up to date',
        value: '90,000 km',
        line: '77,655 km left',
      ),
    );
    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('90,000 km'), findsOneWidget);
    expect(find.text('77,655 km left'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('90,000 km')).style?.fontWeight,
      FontWeight.w600,
    );
  });

  inBothThemes('StatusCard.twoAxes shows both axes with their labels',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const StatusCard.twoAxes(
        tint: AppCardTint.dueSoon,
        icon: Icons.schedule,
        word: 'Due soon',
        axes: [
          StatusAxis(label: 'By km', value: '25,000 km', remaining: '850 left'),
          StatusAxis(label: 'By date', value: '3 Nov 2026'),
        ],
      ),
    );
    expect(find.text('Due soon'), findsOneWidget);
    expect(find.text('BY KM'), findsOneWidget);
    expect(find.text('BY DATE'), findsOneWidget);
    expect(find.text('25,000 km'), findsOneWidget);
    expect(find.text('850 left'), findsOneWidget);
    expect(find.text('3 Nov 2026'), findsOneWidget);
  });

  inBothThemes('HistoryLine joins the word, the rest and the parenthetical',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      const HistoryLine(
        meaning: ActionMeaning.fulfilled,
        icon: Icons.check,
        word: 'Done',
        rest: '3 Nov 2026',
        parenthetical: 'registered 5 Nov',
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.textContaining('Done · 3 Nov 2026 (registered 5 Nov)'),
      findsOneWidget,
    );
  });

  inBothThemes('ActionDialog shows its parts and the two buttons',
      (tester, theme) async {
    var confirmed = false;
    await pump(
      tester,
      theme,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => ActionDialog(
              title: 'Postpone',
              contextLine: 'Currently due on 3 Nov 2026',
              fields: const [
                SizedBox(height: 16),
                TextField(decoration: InputDecoration(labelText: 'Until')),
              ],
              reason: const TextField(
                decoration: InputDecoration(labelText: 'Reason'),
              ),
              note: 'From A to B',
              error: 'Refused',
              confirmLabel: 'Postpone',
              onConfirm: () => confirmed = true,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Postpone'), findsNWidgets(2));
    expect(find.text('Currently due on 3 Nov 2026'), findsOneWidget);
    expect(find.text('Until'), findsOneWidget);
    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('From A to B'), findsOneWidget);
    expect(find.text('Refused'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Postpone'));
    expect(confirmed, isTrue);
  });

  inBothThemes('ActionDialog disables both buttons while busy',
      (tester, theme) async {
    await pump(
      tester,
      theme,
      ActionDialog(
        title: 'Mark done',
        fields: const [],
        confirmLabel: 'Mark done',
        onConfirm: () {},
        busy: true,
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
      isFalse,
    );
    expect(tester.widget<TextButton>(find.byType(TextButton)).enabled, isFalse);
  });

  inBothThemes('FormSection shows its label and fields', (tester, theme) async {
    await pump(
      tester,
      theme,
      const FormSection(
        label: 'Warning',
        children: [
          TextField(decoration: InputDecoration(labelText: 'Days')),
          TextField(decoration: InputDecoration(labelText: 'Distance')),
        ],
      ),
    );
    expect(find.text('WARNING'), findsOneWidget);
    expect(find.text('Days'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
  });
}
