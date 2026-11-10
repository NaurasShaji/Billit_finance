import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive/hive.dart';

import '../../models/models.dart';
import '../../services/boxes.dart';
import '../../services/backup_restore_service.dart';
import '../../services/drive_backup_service.dart';
import '../../utils/theme_colors.dart';

class BackupRestoreScreen extends StatelessWidget {
  const BackupRestoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Backup & Restore',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: const BackupRestoreTab(),
    );
  }
}

class BackupRestoreTab extends StatefulWidget {
  const BackupRestoreTab({super.key});

  @override
  State<BackupRestoreTab> createState() => _BackupRestoreTabState();
}

class _BackupRestoreTabState extends State<BackupRestoreTab>
    with TickerProviderStateMixin {
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isSigningIn = false;
  List<DriveFileEntry> _driveBackups = [];
  int _autoBackupDays = 0;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _loadAutoBackupPreference();
    _initializeGoogleDrive();
    _slideController.forward();
  }

  Future<void> _initializeGoogleDrive() async {
    // Try silent sign-in first
    await DriveBackupService.instance.signIn(interactive: false);
    if (mounted) {
      await _refreshDriveBackups();
      await _maybeRunAutoBackup();
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadAutoBackupPreference() async {
    final session = Hive.box('session');
    setState(() {
      _autoBackupDays = (session.get('autoBackupDays') as int?) ?? 0;
    });
  }

  Future<void> _backupNow() async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    try {
      final payload = await _exportAllBoxesToJson();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'floral_backup_$timestamp.json';
      await DriveBackupService.instance
          .uploadJson(filename: filename, json: payload);

      if (!mounted) return;
      await _refreshDriveBackups();
      _showSuccessSnackbar('Backup uploaded successfully to Google Drive');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackbar('Backup failed: $e');
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _restoreFromDrive(DriveFileEntry entry) async {
    final confirmed = await _showRestoreConfirmationDialog(entry.name);
    if (!confirmed) return;

    if (_isRestoring) return;
    setState(() => _isRestoring = true);
    try {
      final data = await DriveBackupService.instance.downloadJson(entry.id);
      await _importAllBoxesFromJson(data);
      if (!mounted) return;
      _showSuccessSnackbar('Data restored successfully from ${entry.name}');
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackbar('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<bool> _showRestoreConfirmationDialog(String fileName) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Restore Data',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('This will replace all current data with:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.insert_drive_file,
                            color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'This cannot be undone. Create a backup first.',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Restore'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _initGoogle() async {
    setState(() => _isSigningIn = true);
    try {
      await DriveBackupService.instance.signIn();
      await _refreshDriveBackups();
      await _maybeRunAutoBackup();
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(
            'Google Drive sign-in failed: ${e is StateError ? e.message : e}');
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _refreshDriveBackups() async {
    final items = await DriveBackupService.instance.listBackups(pageSize: 5);
    if (!mounted) return;
    setState(() {
      _driveBackups = items;
    });
  }

  Future<void> _maybeRunAutoBackup() async {
    if (_autoBackupDays <= 0) return;
    if (!(await DriveBackupService.instance.isSignedIn())) return;
    final session = Hive.box('session');
    final lastIso = session.get('lastAutoBackupAt') as String?;
    final now = DateTime.now();
    DateTime? last;
    if (lastIso != null) {
      try {
        last = DateTime.parse(lastIso);
      } catch (_) {}
    }
    if (last != null) {
      final dueAt = last.add(Duration(days: _autoBackupDays));
      if (now.isBefore(dueAt)) return;
    }
    try {
      await _backupNow();
    } finally {
      session.put('lastAutoBackupAt', now.toIso8601String());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return SlideTransition(
      position: _slideAnimation,
      child: RefreshIndicator(
        onRefresh: () async {
          await _refreshDriveBackups();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Google Drive Section
              _buildGoogleDriveCard(theme, isTablet),
              const SizedBox(height: 24),

              // Quick Actions and Auto Backup in responsive layout
              if (isTablet)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 2,
                        child: _buildQuickActionsCard(theme, isTablet)),
                    const SizedBox(width: 24),
                    Expanded(child: _buildAutoBackupCard(theme)),
                  ],
                )
              else ...[
                _buildQuickActionsCard(theme, isTablet),
                const SizedBox(height: 24),
                _buildAutoBackupCard(theme),
              ],

              const SizedBox(height: 24),

              // Drive Backups List
              _buildBackupsCard(theme, isTablet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleDriveCard(ThemeData theme, bool isTablet) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.teal.shade600,
              Colors.teal.shade700,
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 32.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.cloud,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Drive Sync',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Cloud backup for business data',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildUserStatus(isTablet),
              const SizedBox(height: 24),
              _buildAuthButton(theme, isTablet),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserStatus(bool isTablet) {
    final user = DriveBackupService.instance.currentUser;
    if (user == null) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(isTablet ? 20 : 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.white.withValues(alpha: 0.9),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connect to Google Drive',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to connect Google Drive.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final name = user.displayName ?? user.email ?? 'Unknown User';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.panelColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.person,
              color: Colors.teal.shade600,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connected as:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthButton(ThemeData theme, bool isTablet) {
    final isSignedIn = DriveBackupService.instance.currentUser != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSigningIn || isSignedIn ? null : _initGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.panelColor,
          foregroundColor: Colors.teal.shade700.adaptive(context),
          padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        icon: _isSigningIn
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.teal.shade700),
                ),
              )
            : Icon(isSignedIn ? Icons.check_circle : Icons.login, size: 24),
        label: Text(
          _isSigningIn
              ? 'Connecting...'
              : (isSignedIn
                  ? 'Connected to Google Drive'
                  : 'Connect to Google Drive'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(ThemeData theme, bool isTablet) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.flash_on,
                    color: theme.primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Quick Actions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Backup and Restore Buttons
            isTablet
                ? Row(
                    children: [
                      Expanded(
                        child: _buildActionButton(
                          onPressed: _isBackingUp ? null : _backupNow,
                          icon: _isBackingUp ? null : Icons.cloud_upload,
                          label: _isBackingUp
                              ? 'Creating Backup...'
                              : 'Create Backup',
                          isLoading: _isBackingUp,
                          color: Colors.blue,
                          height: 100,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildActionButton(
                          onPressed: _isRestoring || _driveBackups.isEmpty
                              ? null
                              : () => _restoreFromDrive(_driveBackups.first),
                          icon: _isRestoring ? null : Icons.restore,
                          label:
                              _isRestoring ? 'Restoring...' : 'Restore Latest',
                          isLoading: _isRestoring,
                          color: Colors.orange,
                          height: 100,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _buildActionButton(
                        onPressed: _isBackingUp ? null : _backupNow,
                        icon: _isBackingUp ? null : Icons.cloud_upload,
                        label: _isBackingUp
                            ? 'Creating Backup...'
                            : 'Create Backup',
                        isLoading: _isBackingUp,
                        color: Colors.blue,
                        height: 60,
                      ),
                      const SizedBox(height: 16),
                      _buildActionButton(
                        onPressed: _isRestoring || _driveBackups.isEmpty
                            ? null
                            : () => _restoreFromDrive(_driveBackups.first),
                        icon: _isRestoring ? null : Icons.restore,
                        label: _isRestoring ? 'Restoring...' : 'Restore Latest',
                        isLoading: _isRestoring,
                        color: Colors.orange,
                        height: 60,
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData? icon,
    required String label,
    required bool isLoading,
    required Color color,
    required double height,
  }) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          side: BorderSide(color: color.withValues(alpha: 0.2)),
        ),
        child: isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAutoBackupCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.schedule,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Automatic Backup',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Set an automatic backup schedule.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: DropdownButton<int>(
                value: _autoBackupDays,
                isExpanded: true,
                underline: const SizedBox(),
                icon: const Icon(Icons.keyboard_arrow_down),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Disabled')),
                  DropdownMenuItem(value: 1, child: Text('Every 1 day')),
                  DropdownMenuItem(value: 3, child: Text('Every 3 days')),
                  DropdownMenuItem(value: 7, child: Text('Every 7 days')),
                  DropdownMenuItem(value: 14, child: Text('Every 14 days')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _autoBackupDays = v);
                  final session = Hive.box('session');
                  await session.put('autoBackupDays', v);
                  if (v == 0) return;
                  await _maybeRunAutoBackup();
                },
              ),
            ),
            if (_autoBackupDays > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Auto backup every $_autoBackupDays day${_autoBackupDays == 1 ? '' : 's'} when connected',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBackupsCard(ThemeData theme, bool isTablet) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.history,
                    color: Colors.purple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Available Backups',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    onPressed: _refreshDriveBackups,
                    icon: Icon(Icons.refresh, color: theme.primaryColor),
                    tooltip: 'Refresh',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_driveBackups.isEmpty)
              _buildEmptyBackupsState()
            else
              _buildBackupsList(isTablet),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBackupsState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No backups found',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first backup to get started',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupsList(bool isTablet) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _driveBackups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final backup = _driveBackups[index];
        final isLatest = index == 0;

        return AnimatedContainer(
          duration: Duration(milliseconds: 100 + (index * 50)),
          decoration: BoxDecoration(
            color: isLatest
                ? Colors.green.withValues(alpha: 0.05)
                : context.subtleFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLatest
                  ? Colors.green.withValues(alpha: 0.3)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: isTablet ? 20 : 16,
              vertical: isTablet ? 12 : 8,
            ),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLatest
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.insert_drive_file,
                color: isLatest ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    backup.name
                        .replaceAll('floral_backup_', '')
                        .replaceAll('.json', ''),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (isLatest)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Latest',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(_buildBackupSubtitle(backup)),
            trailing: Container(
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: const Icon(Icons.restore, color: Colors.orange),
                onPressed:
                    _isRestoring ? null : () => _restoreFromDrive(backup),
                tooltip: 'Restore this backup',
              ),
            ),
          ),
        );
      },
    );
  }

  String _buildBackupSubtitle(DriveFileEntry backup) {
    final parts = <String>[];
    if (backup.modifiedTime != null) {
      parts.add(DateFormat('MMM dd, yyyy HH:mm').format(backup.modifiedTime!));
    }
    if (backup.sizeBytes != null) {
      parts.add(_formatSizeBytes(backup.sizeBytes!));
    }
    return parts.join(' • ');
  }

  String _formatSizeBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Keep your existing data export/import methods unchanged
  Future<Map<String, dynamic>> _exportAllBoxesToJson() async {
    final usersBox = Hive.box<User>(Boxes.users);
    final productsBox = Hive.box<Product>(Boxes.products);
    final salesBox = Hive.box<Sale>(Boxes.sales);
    final expensesBox = Hive.box<Expense>(Boxes.expenses);
    final employeesBox = Hive.box<Employee>(Boxes.employees);
    final financeAccountsBox =
        Hive.box<FinanceAccount>(Boxes.financeAccounts);
    final financeTransactionsBox =
        Hive.box<FinanceTransaction>(Boxes.financeTransactions);
    final financePostingsBox =
        Hive.box<FinancePosting>(Boxes.financePostings);
    final financeCategoriesBox =
        Hive.box<FinanceCategory>(Boxes.financeCategories);
    final financePartiesBox =
        Hive.box<FinanceParty>(Boxes.financeParties);
    final appSettingsBox = Hive.box<dynamic>('app_settings');

    return {
      'meta': {
        'app': 'floral_billing_refined',
        'version': '0.2.0',
        'exportedAt': DateTime.now().toIso8601String(),
      },
      'users': usersBox.values
          .map((u) => {
                'id': u.id,
                'username': u.username,
                'password': u.password,
                'userType': u.userType.name,
              })
          .toList(),
      'appSettings': appSettingsBox
          .toMap()
          .map((key, value) => MapEntry(key.toString(), value)),
      'products': productsBox.values
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'sellingPrice': p.sellingPrice,
                'costPrice': p.costPrice,
                'stock': p.stock,
                'unit': p.unit.name,
                'category': p.category,
                'subCategory': p.subCategory,
                'active': p.active,
                'barcode': p.barcode,
                'hsnCode': p.hsnCode,
                'gstRate': p.gstRate,
              })
          .toList(),
      'sales': salesBox.values
          .map((s) => {
                'id': s.id,
                'date': s.date.toIso8601String(),
                'items': s.items
                    .map((it) => {
                          'productId': it.productId,
                          'qty': it.qty,
                          'sellingPrice': it.sellingPrice,
                          'costPrice': it.costPrice,
                          'subtotal': it.subtotal,
                          'unitLabel': it.unitLabel,
                          'hsnCode': it.hsnCode,
                          'gstRate': it.gstRate,
                          'taxableAmount': it.taxableAmount,
                          'cgstAmount': it.cgstAmount,
                          'sgstAmount': it.sgstAmount,
                          'igstAmount': it.igstAmount,
                        })
                    .toList(),
                'totalAmount': s.totalAmount,
                'totalCost': s.totalCost,
                'profit': s.profit,
                'payment': s.payment.name,
                'customerName': s.customerName,
                'customerPhone': s.customerPhone,
                'userId': s.userId,
                'discount': s.discount,
                'gstEnabled': s.gstEnabled,
                'gstRate': s.gstRate,
                'taxableAmount': s.taxableAmount,
                'cgstAmount': s.cgstAmount,
                'sgstAmount': s.sgstAmount,
                'igstAmount': s.igstAmount,
                'customerGstin': s.customerGstin,
                'interstateSale': s.interstateSale,
                'gstInclusive': s.gstInclusive,
                'financeRevision': s.financeRevision,
              })
          .toList(),
      'expenses': expensesBox.values
          .map((e) => {
                'id': e.id,
                'date': e.date.toIso8601String(),
                'category': e.category,
                'amount': e.amount,
                'description': e.description,
                if (e.employeeId != null) 'employeeId': e.employeeId,
                'financeRevision': e.financeRevision,
              })
          .toList(),
      'employees': employeesBox.values
          .map((e) => {
                'id': e.id,
                'name': e.name,
                'type': e.type,
                'wage': e.wage,
                'attendance': e.attendance,
                'salaryPaid': e.salaryPaid,
                'employeeCode': e.employeeCode,
                'phone': e.phone,
                'email': e.email,
                'departmentId': e.departmentId,
                'designation': e.designation,
                'joiningDate': e.joiningDate?.toIso8601String(),
                'employmentStatus': e.employmentStatus,
                'emergencyContact': e.emergencyContact,
                'address': e.address,
                'notes': e.notes,
              })
          .toList(),
      'hrDepartments': Hive.box<HrDepartment>(Boxes.hrDepartments).values
          .map((department) => {
                'id': department.id,
                'name': department.name,
                'description': department.description,
                'active': department.active,
                'createdAt': department.createdAt.toIso8601String(),
              })
          .toList(),
      'employeeAttendance':
          Hive.box<EmployeeAttendance>(Boxes.employeeAttendance).values
              .map((record) => {
                    'id': record.id,
                    'employeeId': record.employeeId,
                    'date': record.date.toIso8601String(),
                    'status': record.status,
                    'checkIn': record.checkIn?.toIso8601String(),
                    'checkOut': record.checkOut?.toIso8601String(),
                    'notes': record.notes,
                    'updatedAt': record.updatedAt.toIso8601String(),
                  })
              .toList(),
      'leaveRequests': Hive.box<LeaveRequest>(Boxes.leaveRequests).values
          .map((request) => {
                'id': request.id,
                'employeeId': request.employeeId,
                'leaveType': request.leaveType,
                'startDate': request.startDate.toIso8601String(),
                'endDate': request.endDate.toIso8601String(),
                'reason': request.reason,
                'status': request.status,
                'reviewedBy': request.reviewedBy,
                'reviewedAt': request.reviewedAt?.toIso8601String(),
                'createdAt': request.createdAt.toIso8601String(),
              })
          .toList(),
      'financeAccounts': financeAccountsBox.values
          .map((a) => {
                'id': a.id,
                'name': a.name,
                'accountType': a.accountType,
                'parentId': a.parentId,
                'currencyCode': a.currencyCode,
                'active': a.active,
                'createdAt': a.createdAt.toIso8601String(),
              })
          .toList(),
      'financeTransactions': financeTransactionsBox.values
          .map((t) => {
                'id': t.id,
                'transactionNumber': t.transactionNumber,
                'transactionType': t.transactionType,
                'status': t.status,
                'date': t.date.toIso8601String(),
                'memo': t.memo,
                'reference': t.reference,
                'sourceType': t.sourceType,
                'sourceId': t.sourceId,
                'createdAt': t.createdAt.toIso8601String(),
                'postedAt': t.postedAt?.toIso8601String(),
                'reversedTransactionId': t.reversedTransactionId,
              })
          .toList(),
      'financePostings': financePostingsBox.values
          .map((p) => {
                'id': p.id,
                'transactionId': p.transactionId,
                'accountId': p.accountId,
                'debitPaise': p.debitPaise,
                'creditPaise': p.creditPaise,
                'partyId': p.partyId,
                'categoryId': p.categoryId,
                'memo': p.memo,
              })
          .toList(),
      'financeCategories': financeCategoriesBox.values
          .map((category) => {
                'id': category.id,
                'name': category.name,
                'kind': category.kind,
                'accountId': category.accountId,
                'active': category.active,
              })
          .toList(),
      'financeParties': financePartiesBox.values
          .map((party) => {
                'id': party.id,
                'name': party.name,
                'partyType': party.partyType,
                'phone': party.phone,
                'email': party.email,
                'taxIdentifier': party.taxIdentifier,
                'active': party.active,
              })
          .toList(),
    };
  }

  Future<void> _importAllBoxesFromJson(Map<String, dynamic> data) async {
    await const BackupRestoreService().restore(
      data,
      usersBox: Hive.box<User>(Boxes.users),
      productsBox: Hive.box<Product>(Boxes.products),
      salesBox: Hive.box<Sale>(Boxes.sales),
      expensesBox: Hive.box<Expense>(Boxes.expenses),
      employeesBox: Hive.box<Employee>(Boxes.employees),
      appSettingsBox: Hive.box<dynamic>('app_settings'),
      financeAccountsBox: Hive.box<FinanceAccount>(Boxes.financeAccounts),
      financeTransactionsBox:
          Hive.box<FinanceTransaction>(Boxes.financeTransactions),
      financePostingsBox: Hive.box<FinancePosting>(Boxes.financePostings),
      financeCategoriesBox:
          Hive.box<FinanceCategory>(Boxes.financeCategories),
      financePartiesBox: Hive.box<FinanceParty>(Boxes.financeParties),
      hrDepartmentsBox: Hive.box<HrDepartment>(Boxes.hrDepartments),
      employeeAttendanceBox:
          Hive.box<EmployeeAttendance>(Boxes.employeeAttendance),
      leaveRequestsBox: Hive.box<LeaveRequest>(Boxes.leaveRequests),
    );
  }
}
