import 'calendar_date.dart';

// Pure checks between a typed km and the odometer history
// (`Docs/04_maintenance_logic.md`, "Kilometraje"). They only decide what
// the UI asks or offers; the repositories enforce the hard rules.

/// Difference in km above the last reading from which a new reading is
/// probably a typo: the form asks for confirmation, the repository still
/// accepts it.
const int bigOdometerJumpKm = 50000;

/// Whether a reading of [km] is far enough above [lastKm] to ask "are you
/// sure?" before saving it.
bool isBigOdometerJump({required int km, required int lastKm}) =>
    km > lastKm + bigOdometerJumpKm;

/// Whether an entry dated [entryDate] with [entryKm] looks like a typo: it
/// happened before the last reading ([lastReadingDate]) but has more km
/// than the current odometer ([currentOdometerKm]). Since the odometer never
/// goes backwards, the form asks before saving it (E2); it never blocks.
bool isPastEntryAboveOdometer({
  required int? entryKm,
  required CalendarDate entryDate,
  required int currentOdometerKm,
  required CalendarDate? lastReadingDate,
}) =>
    entryKm != null &&
    lastReadingDate != null &&
    entryDate.isBefore(lastReadingDate) &&
    entryKm > currentOdometerKm;

/// Whether saving an entry dated [entryDate] with [entryKm] should be
/// followed by the offer to update the odometer to that km (E3).
///
/// All three must hold: more km than the current odometer, dated today or
/// earlier, and not before the last reading. Exactly the conditions under
/// which a reading with the entry's day and km would be accepted.
bool shouldOfferOdometerUpdate({
  required int? entryKm,
  required CalendarDate entryDate,
  required int currentOdometerKm,
  required CalendarDate? lastReadingDate,
  required CalendarDate today,
}) =>
    entryKm != null &&
    entryKm > currentOdometerKm &&
    !entryDate.isAfter(today) &&
    (lastReadingDate == null || !entryDate.isBefore(lastReadingDate));
