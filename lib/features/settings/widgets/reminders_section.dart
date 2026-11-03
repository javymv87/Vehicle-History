import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/reminder_status.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/action_result.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/widgets/feedback.dart';
import '../../../shared/widgets/section_header.dart';
import '../controllers/settings_controller.dart';

/// The "Reminders" section of the Settings page (`Docs/08_recordatorios.md`):
/// the global lead, "Warn N days before" and "Warn N km before", each
/// opening a dialog for a whole number. The distance is typed and shown in
/// the chosen unit and stored in km; a reminder can override either.
class RemindersSection extends ConsumerWidget {
  /// Creates the section.
  const RemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final units = unitFormatterOf(context, ref);
    // Not read yet, or unreadable: both count as the defaults.
    final lead = ref.watch(reminderLeadProvider).value ?? const ReminderLead();
    final controller = ref.read(settingsControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    /// Shows the error of a failed write; a success needs no message.
    Future<void> run(Future<ActionResult<void>> action) async {
      if (await action case ActionFailure(:final error)) {
        showErrorSnackBar(messenger, error.message(l10n));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: l10n.settingsReminders),
        ListTile(
          key: const ValueKey('reminder-lead-days'),
          leading: const Icon(Icons.event_outlined),
          title: Text(l10n.settingsReminderLeadDays(lead.days)),
          onTap: () async {
            final days = await _askWholeNumber(
              context,
              title: l10n.settingsReminderLeadDaysTitle,
              initial: lead.days,
              suffix: l10n.unitDaysSuffix,
            );
            if (days != null && days != lead.days) {
              await run(controller.setReminderLeadDays(days));
            }
          },
        ),
        ListTile(
          key: const ValueKey('reminder-lead-km'),
          leading: const Icon(Icons.speed_outlined),
          title: Text(
            l10n.settingsReminderLeadDistance(units.distance.format(lead.km)),
          ),
          onTap: () async {
            final shown = await _askWholeNumber(
              context,
              title: l10n.settingsReminderLeadDistanceTitle,
              initial: units.distance.toDisplay(lead.km).round(),
              suffix: units.distance.symbol,
            );
            if (shown == null) return;
            // Re-typing the shown value keeps the stored one exactly.
            final km = units.distance.parse('$shown', sameAs: lead.km);
            if (km != null && km != lead.km) {
              await run(controller.setReminderLeadKm(km));
            }
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Text(
            l10n.settingsReminderLeadHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Asks for a whole number of at least 0, starting from [initial], with
/// [suffix] after the field. Resolves to the number, or `null` when
/// cancelled.
Future<int?> _askWholeNumber(
  BuildContext context, {
  required String title,
  required int initial,
  required String suffix,
}) =>
    showDialog<int>(
      context: context,
      builder: (context) =>
          _WholeNumberDialog(title: title, initial: initial, suffix: suffix),
    );

/// The dialog of [_askWholeNumber].
class _WholeNumberDialog extends StatefulWidget {
  const _WholeNumberDialog({
    required this.title,
    required this.initial,
    required this.suffix,
  });

  final String title;
  final int initial;
  final String suffix;

  @override
  State<_WholeNumberDialog> createState() => _WholeNumberDialogState();
}

class _WholeNumberDialogState extends State<_WholeNumberDialog> {
  late final _text = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The typed number, or `null` when blank.
  int? get _value => int.tryParse(_text.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('whole-number-field'),
        controller: _text,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          suffixText: widget.suffix,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) {
          if (_value != null) Navigator.of(context).pop(_value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        ListenableBuilder(
          listenable: _text,
          builder: (context, _) => TextButton(
            onPressed:
                _value == null ? null : () => Navigator.of(context).pop(_value),
            child: Text(l10n.actionOk),
          ),
        ),
      ],
    );
  }
}
