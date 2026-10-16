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
/// it is always visible: the list helps, it never blocks. While the search
/// box is empty, [headers] maps an item index to a section title shown above
/// that item.
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
  });

  final String title;
  final List<T> Function(String query) search;
  final String Function(T item) labelOf;
  final String otherLabel;
  final Map<int, String> headers;

  @override
  State<_SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<_SearchablePicker<T>> {
  final _query = TextEditingController();
  late List<T> _results = widget.search('');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Re-runs the search for the text now in the search box.
  void _onQueryChanged(String query) {
    setState(() => _results = widget.search(query));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final showHeaders = _query.text.trim().isEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Padding(
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
          ),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.pickerNoResults,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final tile = ListTile(
                        title: Text(widget.labelOf(item)),
                        onTap: () => Navigator.of(context).pop(Picked(item)),
                      );
                      final header = showHeaders ? widget.headers[index] : null;
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
                    },
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: ListTile(
              leading: const Icon(Icons.edit),
              title: Text(widget.otherLabel),
              onTap: () =>
                  Navigator.of(context).pop(PickedOther<T>(_query.text.trim())),
            ),
          ),
        ],
      ),
    );
  }
}
