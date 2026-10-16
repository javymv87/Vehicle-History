import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/data_providers.dart';
import '../../../data/models/owner.dart';

/// State of the owner list: every live owner, ordered by name, updated after
/// every change.
///
/// Also the source of the owner picker in the vehicle form and of the owner
/// names shown in the vehicle list.
final ownerListProvider = StreamProvider.autoDispose<List<Owner>>(
  (ref) => ref.watch(ownerRepositoryProvider).watchAll(),
);
