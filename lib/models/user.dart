import 'package:hive_ce/hive_ce.dart';
part 'user.g.dart';

@HiveType(typeId: 1)
enum UserType {
  @HiveField(0)
  admin,
  @HiveField(1)
  worker,
}

@HiveType(typeId: 2)
class User extends HiveObject {
  @HiveField(0)
  late String id;
  @HiveField(1)
  late String username;
  @HiveField(2)
  late String password; // hashed simple
  @HiveField(3)
  late UserType userType;
  @HiveField(4)
  String securityAnswer = 'Buddy'; // Default security answer
  @HiveField(5)
  String securityQuestion = 'What is the name of your favourite pet?';

  static String hash(String input) {
    return input.codeUnits
        .fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFFFFFF)
        .toRadixString(16);
  }
}
