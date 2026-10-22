import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_history/data/attachments/attachment_picker.dart';
import 'package:vehicle_history/data/platform/temporary_files.dart';

/// What the pickers leave behind: the names given to photos, and the cache
/// emptied at app start.
void main() {
  group('photoFileName', () {
    final takenAt = DateTime(2026, 10, 22, 12, 2, 57);

    test('names a photo like the Android camera, from the local time', () {
      expect(
        photoFileName(
          takenAt,
          0,
          'scaled_28b86238-6f14-4d45-bcfa-548820f17a831461789755231901295.jpg',
        ),
        'IMG_20261022_120257.jpg',
      );
    });

    test('numbers the following photos of the same pick from 2', () {
      expect(
        [for (var i = 0; i < 3; i++) photoFileName(takenAt, i, 'x.jpg')],
        [
          'IMG_20261022_120257.jpg',
          'IMG_20261022_120257_2.jpg',
          'IMG_20261022_120257_3.jpg',
        ],
      );
    });

    test('keeps the plugin extension, lower case, and defaults to jpg', () {
      expect(photoFileName(takenAt, 0, 'scaled_1.PNG'), endsWith('.png'));
      expect(photoFileName(takenAt, 0, 'no_extension'), endsWith('.jpg'));
      expect(photoFileName(takenAt, 0, 'trailing.'), endsWith('.jpg'));
    });
  });

  group('wipeTemporaryDirectorySafely', () {
    late Directory cache;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('vh_cache_test');
    });

    tearDown(() async {
      if (await cache.exists()) await cache.delete(recursive: true);
    });

    test('deletes every file and directory in the cache, keeping the cache',
        () async {
      await File('${cache.path}/scaled_1.jpg').writeAsBytes([1, 2]);
      final pickerDir = Directory('${cache.path}/file_picker/123')
        ..createSync(recursive: true);
      await File('${pickerDir.path}/Polizza.pdf').writeAsBytes([3]);
      Directory('${cache.path}/share/0').createSync(recursive: true);

      expect(await wipeTemporaryDirectorySafely(() async => cache), 3);
      expect(await cache.exists(), isTrue);
      expect(cache.listSync(), isEmpty);
    });

    test('a cache that cannot be found never stops the start', () async {
      expect(
        await wipeTemporaryDirectorySafely(
          () async => throw const FileSystemException('no cache'),
        ),
        isNull,
      );
    });

    test('a missing cache is nothing to do', () async {
      await cache.delete(recursive: true);
      expect(await wipeTemporaryDirectorySafely(() async => cache), 0);
    });
  });
}
