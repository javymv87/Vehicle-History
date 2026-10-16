/// Text matching shared by the catalogue and country searches.
///
/// The user types on a phone keyboard, often without accents and in any
/// case, so "dobl" must find "Doblò" and "turquia" must find "Turquía".
library;

/// Plain-letter replacements for the accented Latin letters that occur in
/// make, model and country names in the app languages.
const Map<String, String> _folds = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
  'ă': 'a', 'ą': 'a', 'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd',
  'đ': 'd', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e',
  'ę': 'e', 'ě': 'e', 'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
  'ī': 'i', 'į': 'i', 'ı': 'i', 'ł': 'l', 'ľ': 'l', 'ñ': 'n', 'ń': 'n',
  'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ō': 'o', 'ő': 'o', 'œ': 'oe', 'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's',
  'ș': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't', 'ț': 't', 'ù': 'u', 'ú': 'u',
  'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ý': 'y',
  'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z',
};

/// Lower-cases [text] and replaces accented letters with plain ones, so two
/// spellings that differ only in case or accents compare equal.
String foldForSearch(String text) {
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final char in lower.split('')) {
    buffer.write(_folds[char] ?? char);
  }
  return buffer.toString();
}

/// The [items] whose [nameOf] contains [query] anywhere, ignoring case and
/// accents, in their original order.
///
/// A blank query matches everything.
List<T> searchByName<T>(
  Iterable<T> items,
  String Function(T item) nameOf,
  String query,
) {
  final needle = foldForSearch(query.trim());
  if (needle.isEmpty) return List.of(items);
  return [
    for (final item in items)
      if (foldForSearch(nameOf(item)).contains(needle)) item,
  ];
}
