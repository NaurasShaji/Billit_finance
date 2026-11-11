import 'package:hive_ce/hive_ce.dart';
import 'drive_backup_service.dart';

class DriveSyncService {
  DriveSyncService._internal();
  static final DriveSyncService instance = DriveSyncService._internal();

  static const String _settingsBoxName = 'settings';
  static const String _autoSyncKey = 'drive_auto_sync';

  late final Box _settingsBox;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _settingsBox = await Hive.openBox(_settingsBoxName);
    _initialized = true;
  }

  bool get isAutoSyncEnabled =>
      _settingsBox.get(_autoSyncKey, defaultValue: true);
  set isAutoSyncEnabled(bool value) => _settingsBox.put(_autoSyncKey, value);

  Future<void> tryAutoSignIn() async {
    if (!isAutoSyncEnabled) return;

    try {
      await DriveBackupService.instance.signIn(interactive: false);
    } catch (e) {
      // Silently ignore errors during auto sign-in
    }
  }

  Future<void> enableAutoSync() async {
    isAutoSyncEnabled = true;
    await tryAutoSignIn();
  }

  Future<void> disableAutoSync() async {
    isAutoSyncEnabled = false;
    await DriveBackupService.instance.signOut();
  }
}
