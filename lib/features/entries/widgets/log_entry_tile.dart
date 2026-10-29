import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/log_entry.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/calendar_date_conversion.dart';
import '../../../shared/utils/localized_labels.dart';
import '../../../shared/utils/money.dart';
import '../../settings/controllers/settings_controller.dart';
import 'log_entry_type_icon.dart';

/// One row of a vehicle's history (`Docs/03_features.md`, U6, U24): type
/// icon and label, date, km (if any), a paperclip with the number of
/// attachments (if any), the first line of the description, and the cost
/// (if any) aligned to the right of the type.
///
/// Built as a plain row rather than a `ListTile` so that, with very large
/// text, the cost wraps under the type instead of squeezing it.
class LogEntryTile extends ConsumerWidget {
  /// Creates the row for [entry], calling [onTap] when tapped.
  const LogEntryTile({
    super.key,
    required this.entry,
    required this.onTap,
    this.attachmentCount = 0,
  });

  /// The entry shown.
  final LogEntry entry;

  /// Number of live attachments of the entry; the paperclip shows when it
  /// is above 0.
  final int attachmentCount;

  /// Opens the entry detail.
  final VoidCallback onTap;

  /// The first non-blank line of [description], or `null`.
  static String? firstLine(String? description) {
    if (description == null) return null;
    for (final line in description.split('\n')) {
      if (line.trim().isNotEmpty) return line.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final units = unitFormatterOf(context, ref);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final date = entry.date.toLocalDateTime();
    final km = entry.km;
    final cost = entry.costCents;
    final summary = firstLine(entry.description);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                child: Icon(
                  entry.type.icon,
                  semanticLabel: entry.type.label(l10n),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      children: [
                        Text(
                          entry.type.label(l10n),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (cost != null)
                          Text(
                            formatEuroCents(cost, l10n.localeName),
                            style: theme.textTheme.titleMedium,
                          ),
                      ],
                    ),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          km == null
                              ? l10n.dateValue(date)
                              : l10n.entryDateAndKm(
                                  date,
                                  units.distance.format(km),
                                ),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted),
                        ),
                        if (attachmentCount > 0)
                          Semantics(
                            label: l10n.attachmentCount(attachmentCount),
                            excludeSemantics: true,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.attach_file, size: 16, color: muted),
                                Text(
                                  '$attachmentCount',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(color: muted),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (summary != null)
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
