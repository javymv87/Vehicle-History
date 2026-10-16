import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme/status_colors.dart';

/// **Temporary** home page, used only to check the theme and the
/// localisation by eye in light and dark mode.
///
/// It shows the localised app title and one sample of each deadline status.
/// It will be replaced by the real home screen when routing and the vehicles
/// feature are introduced; do not build on it.
class PlaceholderHomePage extends StatelessWidget {
  /// Creates the placeholder home page.
  const PlaceholderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = Theme.of(context).extension<StatusColors>()!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusSample(
            icon: Icons.error,
            label: l10n.statusOverdue,
            color: status.overdue,
            onColor: status.onOverdue,
          ),
          _StatusSample(
            icon: Icons.schedule,
            label: l10n.statusDueSoon,
            color: status.dueSoon,
            onColor: status.onDueSoon,
          ),
          _StatusSample(
            icon: Icons.check_circle,
            label: l10n.statusOk,
            color: status.ok,
            onColor: status.onOk,
          ),
        ],
      ),
    );
  }
}

/// One status sample: the status colour used both on the surface (icon and
/// text) and as a fill (chip), always paired with an icon and a label.
class _StatusSample extends StatelessWidget {
  const _StatusSample({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      trailing: Chip(
        avatar: Icon(icon, color: onColor),
        label: Text(label, style: TextStyle(color: onColor)),
        backgroundColor: color,
        side: BorderSide.none,
      ),
    );
  }
}
