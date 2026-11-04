import 'package:flutter/material.dart';

import 'app_card.dart';

/// One section of an archetype form (`Docs/07_design_and_theming.md`,
/// "Arquetipos"): an [AppCard] with its small upper-case [label] and the
/// [children] (the fields) one under the other, stretched, [gap] apart.
/// The 20 dp between sections belongs to the form.
class FormSection extends StatelessWidget {
  /// Creates the section.
  const FormSection({
    super.key,
    required this.label,
    required this.children,
    this.gap = 16,
  });

  /// What the section asks, shown small and upper case.
  final String label;

  /// The fields, in order.
  final List<Widget> children;

  /// Space between consecutive fields.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) SizedBox(height: gap),
            child,
          ],
        ],
      ),
    );
  }
}
