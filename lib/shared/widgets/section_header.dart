import 'package:flutter/material.dart';

/// The heading of a section inside a detail page, such as "Attachments",
/// with an optional action button at its end (at least 48 dp tall).
class SectionHeader extends StatelessWidget {
  /// Creates the header [title], with the button [actionLabel] calling
  /// [onAction] when both are given.
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  /// The section title.
  final String title;

  /// Label of the action button; no button when `null`.
  final String? actionLabel;

  /// Called when the action button is tapped.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (label != null)
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(label),
            ),
        ],
      ),
    );
  }
}
