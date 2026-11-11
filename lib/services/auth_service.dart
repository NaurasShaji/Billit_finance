import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import '../models/models.dart';
import 'boxes.dart';

class AuthService extends ChangeNotifier {
  User? currentUser;
  static const String _sessionBoxName = 'session';
  static const String _sessionUserIdKey = 'user_id';

  Future<void> ensureSeedUsers() async {
    final usersBox = Hive.box<User>(Boxes.users);

    // Create admin user if not exists
    if (usersBox.values.where((u) => u.userType == UserType.admin).isEmpty) {
      final admin = User()
        ..id = 'admin'
        ..username = 'admin'
        ..password = User.hash('admin123')
        ..userType = UserType.admin
        ..securityAnswer = 'Buddy';
      await usersBox.put(admin.id, admin);
    }

    // Create worker user if not exists
    if (usersBox.values.where((u) => u.userType == UserType.worker).isEmpty) {
      final worker = User()
        ..id = 'worker'
        ..username = 'worker'
        ..password = User.hash('worker123')
        ..userType = UserType.worker;
      await usersBox.put(worker.id, worker);
    }
  }

  Future<void> restoreSessionIfAny() async {
    final session = Hive.box(_sessionBoxName);
    final userId = session.get(_sessionUserIdKey) as String?;
    if (userId == null) return;
    final usersBox = Hive.box<User>(Boxes.users);
    final user = usersBox.get(userId);
    if (user != null) {
      currentUser = user;
      notifyListeners();
    }
  }

  Future<bool> login(String username, String password,
      {UserType? userType}) async {
    final usersBox = Hive.box<User>(Boxes.users);
    try {
      final user = usersBox.values.firstWhere(
        (u) =>
            u.username == username &&
            (userType == null || u.userType == userType),
      );
      if (user.password == User.hash(password)) {
        currentUser = user;
        final session = Hive.box(_sessionBoxName);
        await session.put(_sessionUserIdKey, user.id);
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void logout() {
    currentUser = null;
    final session = Hive.box(_sessionBoxName);
    session.delete(_sessionUserIdKey);
    notifyListeners();
  }

  bool get isAdmin => currentUser?.userType == UserType.admin;
  bool get isWorker => currentUser?.userType == UserType.worker;
  bool get isLoggedIn => currentUser != null;

  /// Change password - only admins can change passwords for any user
  /// Workers cannot change any passwords
  Future<void> changePassword(String newPassword,
      {String? targetUserId, String? currentPassword}) async {
    if (currentUser == null) {
      throw Exception('User not logged in');
    }

    // Only admins can change passwords
    if (!isAdmin) {
      throw Exception('Permission denied: Only admins can change passwords');
    }

    // Validate password requirements
    if (newPassword.length < 6) {
      throw Exception('Password must be at least 6 characters long');
    }
    if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(newPassword)) {
      throw Exception(
          'Password can only contain letters and numbers (no special characters)');
    }

    final usersBox = Hive.box<User>(Boxes.users);
    final userToChangeId = targetUserId ?? currentUser!.id;
    final user = usersBox.get(userToChangeId);

    if (user == null) {
      throw Exception('User not found');
    }

    // If changing own password, require current password
    if (targetUserId == null || targetUserId == currentUser!.id) {
      if (currentPassword == null) {
        throw Exception(
            'Current password is required when changing your own password');
      }
      if (user.password != User.hash(currentPassword)) {
        throw Exception('Incorrect current password');
      }
    }
    // For changing other users' passwords, no current password needed

    user.password = User.hash(newPassword);
    await user.save();

    // If changing own password, update currentUser in session
    if (userToChangeId == currentUser!.id) {
      currentUser = user;
    }
    notifyListeners();
  }

  /// Get all users for admin password management
  List<User> getAllUsers() {
    if (!isAdmin) {
      return [];
    }

    final usersBox = Hive.box<User>(Boxes.users);
    return usersBox.values.toList();
  }

  String getAdminSecurityQuestion() {
    final usersBox = Hive.box<User>(Boxes.users);
    final admin = usersBox.values.firstWhere(
      (user) => user.userType == UserType.admin,
      orElse: () => throw Exception('Admin account not found'),
    );
    return admin.securityQuestion;
  }

  Future<void> updateAdminSecurityQuestion({
    required String currentPassword,
    required String question,
    required String answer,
  }) async {
    if (!isAdmin || currentUser == null) {
      throw Exception('Only the signed-in administrator can update this setting');
    }
    if (currentUser!.password != User.hash(currentPassword)) {
      throw Exception('Current password is incorrect');
    }
    if (question.trim().isEmpty || answer.trim().isEmpty) {
      throw Exception('Choose a question and enter its answer');
    }
    currentUser!
      ..securityQuestion = question.trim()
      ..securityAnswer = answer.trim();
    await currentUser!.save();
    notifyListeners();
  }

  /// Reset admin password using security question
  /// This is used for forgot password functionality
  Future<void> resetAdminPassword(
      String securityAnswer, String newPassword) async {
    if (newPassword.length < 6) {
      throw Exception('Password must be at least 6 characters long');
    }

    final usersBox = Hive.box<User>(Boxes.users);

    // Find the admin user by security answer
    final adminUser = usersBox.values.firstWhere(
      (u) =>
          u.userType == UserType.admin &&
          u.securityAnswer.toLowerCase() == securityAnswer.toLowerCase(),
      orElse: () => throw Exception('Incorrect answer to security question'),
    );

    // Update the password
    adminUser.password = User.hash(newPassword);
    await adminUser.save();

    // If this is the current user, update the session
    if (currentUser?.id == adminUser.id) {
      currentUser = adminUser;
      notifyListeners();
    }
  }
}
