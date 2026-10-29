import 'calendar_date.dart';
import 'mileage_reading.dart';

// Pure checks between a typed km and the odometer history
// (`Docs/04_maintenance_logic.md`, "Kilometraje"). They only decide what
// the UI asks or offers; the repositories enforce the hard rules.

/// Difference in km above the last reading from which a new reading is
/// probably a typo: the form asks for confirmation, the repository still
/// accepts it. Compared in km whatever the display unit; the dialog names
/// the friendly figure of the chosen unit (`friendlyBigOdometerJump`).
const int bigOdometerJumpKm = 50000;

/// Whether a reading of [km] is far enough above [lastKm] to ask "are you
/// sure?" before saving it.
bool isBigOdometerJump({required double km, required double lastKm}) =>
    km > lastKm + bigOdometerJumpKm;

/// The reading that makes an entry dated [entryDate] with [entryKm] look
/// like a typo (E2), or `null` when there is none.
///
/// Since the odometer never goes backwards, an entry cannot have more km
/// than a reading taken on a **later** day. The series is non-decreasing, so
/// the first reading after [entryDate] is the one with the fewest km: it is
/// returned when its km is below [entryKm]. [readings] is the vehicle's
/// series in any order. The form asks before saving; it never blocks.
MileageReading? laterReadingBelowEntryKm({
  required double? entryKm,
  required CalendarDate entryDate,
  required List<MileageReading> readings,
}) {
  if (entryKm == null) return null;
  MileageReading? firstAfter;
  for (final reading in readings) {
    if (!reading.date.isAfter(entryDate)) continue;
    if (firstAfter == null || firstAfter.isAfter(reading)) {
      firstAfter = reading;
    }
  }
  return firstAfter != null && firstAfter.km < entryKm ? firstAfter : null;
}

/// Whether saving an entry dated [entryDate] with [entryKm] should be
/// followed by the offer to update the odometer to that km (E3).
///
/// All three must hold: more km than the current odometer, dated today or
/// earlier, and not before the last reading. Exactly the conditions under
/// which a reading with the entry's day and km would be accepted.
bool shouldOfferOdometerUpdate({
  required double? entryKm,
  required CalendarDate entryDate,
  required double currentOdometerKm,
  required CalendarDate? lastReadingDate,
  required CalendarDate today,
}) =>
    entryKm != null &&
    entryKm > currentOdometerKm &&
    !entryDate.isAfter(today) &&
    (lastReadingDate == null || !entryDate.isBefore(lastReadingDate));
