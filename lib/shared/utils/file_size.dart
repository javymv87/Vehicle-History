import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

/// Formats a file size of [bytes] for the user, in the language of [l10n]:
/// `850 B`, `12 KB`, `3,4 MB`, `1,2 GB` (1 KB = 1024 B).
///
/// Below 10 units one decimal is shown, above none; the number goes
/// through `intl`, so the decimal separator follows the locale.
String formatFileSize(int bytes, AppLocalizations l10n) {
  const unit = 1024;
  if (bytes < unit) {
    final format = NumberFormat.decimalPattern(l10n.localeName);
    return l10n.sizeBytes(format.format(bytes < 0 ? 0 : bytes));
  }
  final units = [
    l10n.sizeKilobytes,
    l10n.sizeMegabytes,
    l10n.sizeGigabytes,
  ];
  var value = bytes / unit;
  var index = 0;
  while (value >= unit && index < units.length - 1) {
    value /= unit;
    index++;
  }
  final format = NumberFormat.decimalPattern(l10n.localeName)
    ..maximumFractionDigits = value < 10 ? 1 : 0
    ..minimumFractionDigits = 0;
  return units[index](format.format(value));
}
