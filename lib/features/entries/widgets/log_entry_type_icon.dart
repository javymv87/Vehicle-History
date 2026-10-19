import 'package:flutter/material.dart';

import '../../../data/models/log_entry_type.dart';

/// Icon of a [LogEntryType], shared by the type chips, the filters, the
/// history rows and the detail, so a type always looks the same.
extension LogEntryTypeIcon on LogEntryType {
  /// The Material icon of this entry type.
  IconData get icon => switch (this) {
        LogEntryType.maintenance => Icons.build,
        LogEntryType.repair => Icons.car_repair,
        LogEntryType.legalDue => Icons.gavel,
        LogEntryType.refuel => Icons.local_gas_station,
        LogEntryType.expense => Icons.receipt_long,
        LogEntryType.measuredCheck => Icons.straighten,
        LogEntryType.genericCheck => Icons.fact_check,
        LogEntryType.note => Icons.sticky_note_2,
      };
}
