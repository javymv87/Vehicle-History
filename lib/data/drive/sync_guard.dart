import 'drive_models.dart';

/// Where the local data and the Drive copy stand against each other
/// (`Docs/05_sync_and_storage.md`, "Strada A").
enum SyncState {
  /// No Google account is linked: nothing to do.
  noAccount,

  /// The account holds no copy: the first upload, automatic since nothing
  /// can be lost.
  noCloudCopy,

  /// The Drive copy comes from a newer database schema: no download (the
  /// app could not read it) and no automatic upload (it would replace
  /// data a newer app wrote). The user is told to update the app.
  cloudTooNew,

  /// There is a copy but no last common point with it (first link, new
  /// phone, another account, after a manual import): nothing automatic,
  /// the user chooses.
  noCommonPoint,

  /// Both sides are as at the last common point.
  aligned,

  /// Only the local data changed: automatic upload, since the copy it
  /// replaces is contained in the local data.
  localChanged,

  /// Only the Drive copy changed: a download is offered, never automatic.
  cloudChanged,

  /// Both changed since the last common point: either direction loses
  /// something, the user chooses.
  diverged,
}

/// What [evaluateSync] concluded.
class SyncVerdict {
  /// Creates the verdict.
  const SyncVerdict(this.state, {this.sameContent = false});

  /// Where the two sides stand.
  final SyncState state;

  /// The state is [SyncState.aligned] only because both sides hold the same
  /// data (equal stamps and counts) although the last common point does not
  /// say so; the caller records the current state as the new common point.
  final bool sameContent;

  @override
  bool operator ==(Object other) =>
      other is SyncVerdict &&
      other.state == state &&
      other.sameContent == sameContent;

  @override
  int get hashCode => Object.hash(state, sameContent);

  @override
  String toString() => 'SyncVerdict($state, sameContent: $sameContent)';
}

/// The version guard: compares the [local] data and the latest Drive copy
/// [cloud] (`null` when there is none) with the last common point
/// [commonPoint], for the linked [account] (`null` when none) and an app
/// whose database is at [appSchemaVersion].
///
/// Pure: no clock, no I/O. Stamps and upload ids are compared as recorded
/// values, so clock skew between phones is irrelevant.
///
/// - The common point only counts when it was reached with [account].
/// - Local changed: its stamp differs from the one recorded at the point.
/// - Cloud changed: its `upload_id` differs from the recorded one; every
///   upload writes a new one.
/// - Both sides holding the same data (the same non-empty stamp and the
///   same counts) are [SyncState.aligned] with [SyncVerdict.sameContent],
///   whatever the point says: there is nothing to lose either way.
SyncVerdict evaluateSync({
  required DriveAccount? account,
  required LocalSyncState local,
  required CloudBackup? cloud,
  required SyncPoint? commonPoint,
  required int appSchemaVersion,
}) {
  if (account == null) return const SyncVerdict(SyncState.noAccount);
  if (cloud == null) return const SyncVerdict(SyncState.noCloudCopy);
  if (cloud.schemaVersion > appSchemaVersion) {
    return const SyncVerdict(SyncState.cloudTooNew);
  }

  final point = commonPoint?.account == account.email ? commonPoint : null;
  final localStamp = stampCode(local.stamp);
  final sameContent = local.stamp != null &&
      cloud.stamp == localStamp &&
      cloud.counts == local.counts;

  if (point == null) {
    return sameContent
        ? const SyncVerdict(SyncState.aligned, sameContent: true)
        : const SyncVerdict(SyncState.noCommonPoint);
  }

  final localChanged = point.localStamp != localStamp;
  final cloudChanged = point.uploadId != cloud.uploadId;
  if (!cloudChanged) {
    return SyncVerdict(
      localChanged ? SyncState.localChanged : SyncState.aligned,
    );
  }
  // The cloud copy changed. If it now holds exactly the local data (another
  // phone downloaded and uploaded it again), nothing is lost either way.
  if (sameContent) {
    return const SyncVerdict(SyncState.aligned, sameContent: true);
  }
  return SyncVerdict(
    localChanged ? SyncState.diverged : SyncState.cloudChanged,
  );
}
