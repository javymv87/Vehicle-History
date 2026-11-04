import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What the user chose in a [showSearchablePicker].
sealed class PickerResult<T> {
  /// Base constructor for the two outcomes.
  const PickerResult();
}

/// The user picked [value] from the list.
final class Picked<T> extends PickerResult<T> {
  /// Creates the outcome for [value].
  const Picked(this.value);

  /// The picked item.
  final T value;
}

/// The user chose the "Other…" option, to type a value that is not listed.
final class PickedOther<T> extends PickerResult<T> {
  /// Creates the outcome; [query] is what was in the search box, so the
  /// caller can offer it as the starting text.
  const PickedOther(this.query);

  /// The search text at the moment "Other…" was tapped (may be empty).
  final String query;
}

/// Opens a full-screen, searchable list and resolves to what the user chose,
/// or `null` when they closed it.
///
/// [search] returns the items matching a query, already in display order.
/// [otherLabel] is the last option ("Other make…"), pinned at the bottom so
/// it is always visible: the list helps, it never blocks. When the screen
/// is too short for that (landscape with the keyboard open), everything
/// scrolls as one list ending with it, so nothing overflows. While the search
/// box is empty, [headers] maps an item index to a section title shown above
/// that item. With [sectionOf] instead, a section title is shown above every
/// item whose section differs from the previous one's, while searching too.
///
/// With [showAllLabel] and [searchAll], a switch under the search box swaps
/// [search] (the items that apply) for [searchAll] (every item): the list
/// helps, it never hides an item for good.
///
/// It is a full-screen dialog rather than a route: it is a transient choice
/// inside a form, with nothing to deep-link to.
Future<PickerResult<T>?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required List<T> Function(String query) search,
  required String Function(T item) labelOf,
  required String otherLabel,
  Map<int, String> headers = const {},
  String Function(T item)? sectionOf,
  String? showAllLabel,
  List<T> Function(String query)? searchAll,
}) {
  return showDialog<PickerResult<T>>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: _SearchablePicker<T>(
        title: title,
        search: search,
        labelOf: labelOf,
        otherLabel: otherLabel,
        headers: headers,
        sectionOf: sectionOf,
        showAllLabel: showAllLabel,
        searchAll: searchAll,
      ),
    ),
  );
}

/// The content of the full-screen picker: search box, results, "Other…".
class _SearchablePicker<T> extends StatefulWidget {
  const _SearchablePicker({
    required this.title,
    required this.search,
    required this.labelOf,
    required this.otherLabel,
    required this.headers,
    required this.sectionOf,
    required this.showAllLabel,
    required this.searchAll,
  });

  final String title;
  final List<T> Function(String query) search;
  final String Function(T item) labelOf;
  final String otherLabel;
  final Map<int, String> headers;
  final String Function(T item)? sectionOf;
  final String? showAllLabel;
  final List<T> Function(String query)? searchAll;

  @override
  State<_SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<_SearchablePicker<T>> {
  /// Below this height for the body, the search box, the switch, the
  /// results and "Other…" scroll as one list instead of pinning "Other…".
  static const double _compactHeight = 320;

  final _query = TextEditingController();

  /// Whether the "show all" switch is on.
  bool _showAll = false;

  late List<T> _results = _run('');

  /// The items matching [query], from every item when "show all" is on.
  List<T> _run(String query) =>
      (_showAll ? widget.searchAll ?? widget.search : widget.search)(query);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Re-runs the search for the text now in the search box.
  void _onQueryChanged(String query) {
    setState(() => _results = _run(query));
  }

  /// The row of the result at [index], with its section title above it when
  /// a new section starts there.
  Widget _row(BuildContext context, int index) {
    final theme = Theme.of(context);
    final item = _results[index];
    final sectionOf = widget.sectionOf;
    final tile = ListTile(
      title: Text(widget.labelOf(item)),
      onTap: () => Navigator.of(context).pop(Picked(item)),
    );
    final String? header;
    if (sectionOf != null) {
      final section = sectionOf(item);
      header = index == 0 || sectionOf(_results[index - 1]) != section
          ? section
          : null;
    } else {
      header = _query.text.trim().isEmpty ? widget.headers[index] : null;
    }
    if (header == null) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            header,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        tile,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showAllLabel = widget.showAllLabel;
    final search = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: _query,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n.pickerSearchHint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
        ),
        onChanged: _onQueryChanged,
      ),
    );
    final showAll = showAllLabel != null && widget.searchAll != null
        ? SwitchListTile(
            title: Text(showAllLabel),
            value: _showAll,
            onChanged: (value) {
              _showAll = value;
              _onQueryChanged(_query.text);
            },
          )
        : null;
    final noResults = Padding(
      padding: const EdgeInsets.all(24),
      child: Text(l10n.pickerNoResults, textAlign: TextAlign.center),
    );
    final other = SafeArea(
      top: false,
      child: ListTile(
        leading: const Icon(Icons.edit),
        title: Text(widget.otherLabel),
        onTap: () =>
            Navigator.of(context).pop(PickedOther<T>(_query.text.trim())),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(widget.title),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Too short for the fixed parts plus a few rows (a phone in
          // landscape with the keyboard open): everything scrolls together,
          // "Other…" at the end, so nothing overflows.
          if (constraints.maxHeight < _compactHeight) {
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: search),
                if (showAll != null) SliverToBoxAdapter(child: showAll),
                if (_results.isEmpty)
                  SliverToBoxAdapter(child: noResults)
                else
                  SliverList.builder(
                    itemCount: _results.length,
                    itemBuilder: _row,
                  ),
                const SliverToBoxAdapter(child: Divider(height: 1)),
                SliverToBoxAdapter(child: other),
              ],
            );
          }
          return Column(
            children: [
              search,
              if (showAll != null) showAll,
              Expanded(
                child: _results.isEmpty
                    ? Center(child: noResults)
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: _row,
                      ),
              ),
              const Divider(height: 1),
              other,
            ],
          );
        },
      ),
    );
  }
}
