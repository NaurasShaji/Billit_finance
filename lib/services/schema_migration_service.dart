import 'package:hive/hive.dart';

typedef SchemaMigrationCallback = Future<void> Function(Box<dynamic> settings);

class SchemaMigration {
  final int fromVersion;
  final int toVersion;
  final SchemaMigrationCallback apply;

  const SchemaMigration({
    required this.fromVersion,
    required this.toVersion,
    required this.apply,
  });
}

/// Runs ordered, retry-safe application schema migrations.
///
/// Version 1 is the baseline for installations that predate schema versioning.
/// Migrations must be additive/idempotent because Hive does not provide a
/// transaction spanning multiple boxes.
class SchemaMigrationService {
  static const String versionKey = 'schema_version';
  static const int legacyBaselineVersion = 1;

  final int currentVersion;
  final List<SchemaMigration> migrations;

  const SchemaMigrationService({
    this.currentVersion = legacyBaselineVersion,
    this.migrations = const [],
  });

  Future<void> run(Box<dynamic> settings) async {
    if (currentVersion < legacyBaselineVersion) {
      throw StateError('Schema version cannot be below the legacy baseline.');
    }

    var version = settings.get(versionKey);
    if (version == null) {
      version = legacyBaselineVersion;
      await settings.put(versionKey, version);
    }

    if (version is! int || version < legacyBaselineVersion) {
      throw StateError('Invalid stored schema version: $version');
    }
    if (version > currentVersion) {
      throw StateError(
        'Database schema version $version is newer than this app supports '
        '($currentVersion). Update Billit before opening this data.',
      );
    }

    while (version < currentVersion) {
      final nextVersion = version + 1;
      final matching = migrations
          .where((migration) =>
              migration.fromVersion == version &&
              migration.toVersion == nextVersion)
          .toList();

      if (matching.length != 1) {
        throw StateError(
          'Expected exactly one schema migration from $version to '
          '$nextVersion; found ${matching.length}.',
        );
      }

      // Advance the version only after the migration completes. A failed
      // migration is retried on next startup and must therefore be idempotent.
      await matching.single.apply(settings);
      await settings.put(versionKey, nextVersion);
      version = nextVersion;
    }
  }
}
