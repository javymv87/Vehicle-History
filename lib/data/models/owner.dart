import 'calendar_date.dart';
import 'copy_with_sentinel.dart';

/// A person who owns one or more vehicles.
///
/// Immutable snapshot of a live (not deleted) owner as stored on the device.
/// Created and changed only through `OwnerRepository`, which sets [id],
/// [createdAt] and [updatedAt].
class Owner {
  /// Creates an owner snapshot. Normally called by the repository only.
  const Owner({
    required this.id,
    required this.firstName,
    this.lastName,
    this.birthDate,
    this.nationality,
    this.phone,
    this.email,
    this.notes,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Device-generated UUID v4.
  final String id;

  /// First name. Required and never blank.
  final String firstName;

  /// Last name, if known.
  final String? lastName;

  /// Birth date, as a calendar day with no timezone.
  final CalendarDate? birthDate;

  /// Nationality: an ISO 3166-1 alpha-2 code (e.g. `IT`) when picked from
  /// the country list, otherwise the text the user typed.
  final String? nationality;

  /// Phone number, stored as typed (trimmed). Not validated.
  final String? phone;

  /// Email address, stored as typed (trimmed). Not validated.
  final String? email;

  /// Free notes.
  final String? notes;

  /// Photo file path, relative to the app support directory.
  final String? photoPath;

  /// When the owner was created, in UTC.
  final DateTime createdAt;

  /// When the owner was last modified, in UTC.
  final DateTime updatedAt;

  /// First name followed by the last name, if any, as shown in lists.
  String get fullName =>
      lastName == null ? firstName : '$firstName ${lastName!}';

  /// Returns a copy with the given fields replaced.
  ///
  /// Nullable fields can be cleared by passing `null` explicitly; omitting a
  /// parameter keeps the current value.
  Owner copyWith({
    String? id,
    String? firstName,
    Object? lastName = unset,
    Object? birthDate = unset,
    Object? nationality = unset,
    Object? phone = unset,
    Object? email = unset,
    Object? notes = unset,
    Object? photoPath = unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Owner(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName:
          identical(lastName, unset) ? this.lastName : lastName as String?,
      birthDate: identical(birthDate, unset)
          ? this.birthDate
          : birthDate as CalendarDate?,
      nationality: identical(nationality, unset)
          ? this.nationality
          : nationality as String?,
      phone: identical(phone, unset) ? this.phone : phone as String?,
      email: identical(email, unset) ? this.email : email as String?,
      notes: identical(notes, unset) ? this.notes : notes as String?,
      photoPath:
          identical(photoPath, unset) ? this.photoPath : photoPath as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Owner &&
      other.id == id &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.birthDate == birthDate &&
      other.nationality == nationality &&
      other.phone == phone &&
      other.email == email &&
      other.notes == notes &&
      other.photoPath == photoPath &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        firstName,
        lastName,
        birthDate,
        nationality,
        phone,
        email,
        notes,
        photoPath,
        createdAt,
        updatedAt,
      );

  // Personal data is kept out of toString so it never ends up in logs.
  @override
  String toString() =>
      'Owner(id: $id, createdAt: $createdAt, updatedAt: $updatedAt)';
}
