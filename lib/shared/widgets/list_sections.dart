import 'package:flutter/material.dart';

import 'section_header.dart';

/// One titled group of items of a [ListSections].
class ListSection<T> {
  /// Creates the section [title] holding [items].
  const ListSection({required this.title, required this.items});

  /// The heading of the section (for a folded one, with its count).
  final String title;

  /// The items, in the order they are listed.
  final List<T> items;
}

/// A list grouped in [sections] (`Docs/07_design_and_theming.md`,
/// "Arquetipos"): a `SectionHeader` and the rows of each non-empty
/// section, built by [row] and 4 dp apart with no divider, and at the
/// bottom the optional [folded] section, closed until tapped
/// ("Completed (3)"), with an optional [foldedIcon] before its title.
///
/// On its own it is the scrolling list of a list screen and leaves room
/// under the last row for a FAB; [embedded] makes it a plain column inside
/// the scrolling list of a detail screen (the owner's vehicles).
class ListSections<T> extends StatelessWidget {
  /// Creates the list.
  const ListSections({
    super.key,
    required this.sections,
    this.folded,
    this.foldedIcon,
    this.embedded = false,
    required this.row,
  });

  /// The sections, in order; an empty one is not shown.
  final List<ListSection<T>> sections;

  /// A section folded at the bottom; none when `null` or empty.
  final ListSection<T>? folded;

  /// Shown before the title of [folded], such as the archive icon; none
  /// when `null`.
  final Widget? foldedIcon;

  /// Whether the list is a column inside another scrolling list rather
  /// than a scrolling list itself.
  final bool embedded;

  /// Builds the row of one item.
  final Widget Function(T item) row;

  @override
  Widget build(BuildContext context) {
    final folded = this.folded;
    // No dividers: 4 dp between rows.
    Widget tile(T item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: row(item),
        );
    final children = [
      for (final section in sections)
        if (section.items.isNotEmpty) ...[
          SectionHeader(title: section.title),
          for (final item in section.items) tile(item),
        ],
      if (folded != null && folded.items.isNotEmpty)
        ExpansionTile(
          leading: foldedIcon,
          title: Text(folded.title),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [for (final item in folded.items) tile(item)],
        ),
    ];
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      // Room at the bottom so the FAB never covers the last row.
      padding: const EdgeInsets.only(bottom: 88),
      children: children,
    );
  }
}
