import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/models/audit_entry.dart';
import 'package:vehicle_history/data/repositories/repository_exceptions.dart';
import 'package:vehicle_history/l10n/app_localizations.dart';
import 'package:vehicle_history/shared/utils/action_result.dart';
import 'package:vehicle_history/shared/utils/localized_labels.dart';

void main() {
  group('actionErrorOf', () {
    test('maps every repository exception', () {
      expect(
        actionErrorOf(const DuplicatePlateException('AB123CD')),
        ActionError.duplicatePlate,
      );
      expect(
        actionErrorOf(const OwnerHasVehiclesException('o', 2)),
        ActionError.ownerHasVehicles,
      );
      expect(
        actionErrorOf(
          const EntityNotFoundException(AuditEntityType.owner, 'o'),
        ),
        ActionError.ownerNotFound,
      );
      expect(
        actionErrorOf(
          const EntityNotFoundException(AuditEntityType.vehicle, 'v'),
        ),
        ActionError.vehicleNotFound,
      );
      expect(
        actionErrorOf(
          const EntityNotFoundException(AuditEntityType.logEntry, 'e'),
        ),
        ActionError.entryNotFound,
      );
      expect(
        actionErrorOf(const InvalidFieldException('plate', 'blank')),
        ActionError.invalidInput,
      );
      expect(actionErrorOf(Exception('disk full')), ActionError.unexpected);
    });
  });

  group('runAction', () {
    test('wraps the value of a successful action', () async {
      final result = await runAction(() async => 42);
      expect(result, isA<ActionSuccess<int>>());
      expect((result as ActionSuccess<int>).value, 42);
    });

    test('turns an exception into a failure', () async {
      final result = await runAction<int>(
        () async => throw const DuplicatePlateException('AB123CD'),
      );
      expect(
        result,
        isA<ActionFailure<int>>()
            .having((f) => f.error, 'error', ActionError.duplicatePlate),
      );
    });

    test('rethrows an Error, which is a programming mistake', () async {
      await expectLater(
        runAction<int>(() async => throw StateError('bug')),
        throwsStateError,
      );
    });
  });

  group('localised messages', () {
    for (final languageCode in ['en', 'es', 'it']) {
      test('every error has a non-empty, distinct message in $languageCode',
          () {
        final l10n = lookupAppLocalizations(Locale(languageCode));
        final messages = {
          for (final error in ActionError.values) error.message(l10n),
        };
        expect(messages, hasLength(ActionError.values.length));
        expect(messages.every((m) => m.trim().isNotEmpty), isTrue);
      });
    }

    test('the duplicate plate message is translated', () {
      expect(
        ActionError.duplicatePlate.message(
          lookupAppLocalizations(const Locale('es')),
        ),
        'Otro vehículo ya tiene esta matrícula',
      );
      expect(
        ActionError.duplicatePlate.message(
          lookupAppLocalizations(const Locale('it')),
        ),
        'Un altro veicolo ha già questa targa',
      );
    });
  });
}
