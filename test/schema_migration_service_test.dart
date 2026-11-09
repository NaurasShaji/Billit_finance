import 'dart:io';

import 'package:billit/services/schema_migration_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDirectory;
  late Box<dynamic> settings;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('billit_schema_test');
    Hive.init(tempDirectory.path);
    settings = await Hive.openBox<dynamic>('app_settings');
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('assigns legacy installations the baseline schema version', () async {
    await settings.put('app_name', 'Billit');

    await const SchemaMigrationService().run(settings);

    expect(settings.get(SchemaMigrationService.versionKey), 1);
    expect(settings.get('app_name'), 'Billit');
  });

  test('runs each migration once and records its version after success',
      () async {
    var migrationRuns = 0;
    final service = SchemaMigrationService(
      currentVersion: 2,
      migrations: [
        SchemaMigration(
          fromVersion: 1,
          toVersion: 2,
          apply: (box) async {
            migrationRuns++;
            await box.put('finance_schema_ready', true);
          },
        ),
      ],
    );

    await service.run(settings);
    await service.run(settings);

    expect(migrationRuns, 1);
    expect(settings.get('finance_schema_ready'), isTrue);
    expect(settings.get(SchemaMigrationService.versionKey), 2);
  });

  test('does not advance the version when a migration fails', () async {
    final service = SchemaMigrationService(
      currentVersion: 2,
      migrations: [
        SchemaMigration(
          fromVersion: 1,
          toVersion: 2,
          apply: (_) async => throw StateError('migration failed'),
        ),
      ],
    );

    await expectLater(service.run(settings), throwsA(isA<StateError>()));
    expect(settings.get(SchemaMigrationService.versionKey), 1);
  });

  test('rejects data written by a newer app version', () async {
    await settings.put(SchemaMigrationService.versionKey, 3);

    await expectLater(
      const SchemaMigrationService(currentVersion: 2).run(settings),
      throwsA(isA<StateError>()),
    );
  });

  test('fails when a required migration is missing', () async {
    await expectLater(
      const SchemaMigrationService(currentVersion: 2).run(settings),
      throwsA(isA<StateError>()),
    );
  });
}
