import 'package:hive_ce/hive_ce.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import 'boxes.dart';

class HrServiceException implements Exception {
  const HrServiceException(this.message);
  final String message;

  @override
  String toString() => 'HrServiceException: $message';
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.presentDays,
    required this.halfDays,
    required this.absentDays,
    required this.leaveDays,
    required this.holidays,
  });

  final int presentDays;
  final int halfDays;
  final int absentDays;
  final int leaveDays;
  final int holidays;

  double get payableDays => presentDays + halfDays * 0.5;
}

class LeavePolicy {
  const LeavePolicy({
    required this.annualEntitlementDays,
    required this.accrualEnabled,
  });
  final int annualEntitlementDays;
  final bool accrualEnabled;

  Map<String, dynamic> toMap() => {
        'annualEntitlementDays': annualEntitlementDays,
        'accrualEnabled': accrualEnabled,
      };

  factory LeavePolicy.fromMap(Map value) => LeavePolicy(
        annualEntitlementDays: value['annualEntitlementDays'] is num
            ? (value['annualEntitlementDays'] as num).toInt()
            : 0,
        accrualEnabled: value['accrualEnabled'] is bool
            ? value['accrualEnabled'] as bool
            : false,
      );
}

class LeaveBalance {
  const LeaveBalance({
    required this.leaveType,
    required this.entitledDays,
    required this.usedDays,
  }) : availableDays = entitledDays - usedDays;
  final String leaveType;
  final double entitledDays;
  final int usedDays;
  final double availableDays;
}

class HrService {
  static const attendanceStatuses = {
    'present',
    'absent',
    'half_day',
    'leave',
    'holiday',
  };
  static const leaveTypes = {'casual', 'sick', 'earned', 'unpaid', 'other'};

  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static const leavePolicySettingsKey = 'hr_leave_policies';

  static const employmentHistorySettingsKey = 'hr_employment_history';

  List<Map<String, dynamic>> employmentHistory(String employeeId) {
    final raw = Hive.box<dynamic>('app_settings').get(employmentHistorySettingsKey);
    if (raw is! Map) return const [];
    final entries = raw[employeeId];
    if (entries is! List) return const [];
    return entries
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList()
      ..sort((a, b) => DateTime.parse(b['effectiveDate'] as String)
          .compareTo(DateTime.parse(a['effectiveDate'] as String)));
  }

  Future<void> addEmploymentHistory({
    required String employeeId,
    required String eventType,
    required String title,
    required DateTime effectiveDate,
    String notes = '',
  }) async {
    if (!{'joining', 'designation', 'department', 'status', 'pay_change', 'other'}
        .contains(eventType)) {
      throw const HrServiceException('Unsupported employment history event.');
    }
    if (title.trim().isEmpty) {
      throw const HrServiceException('Enter a title for the employment history event.');
    }
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null) throw const HrServiceException('Employee not found.');
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(employmentHistorySettingsKey);
    final history = <String, dynamic>{
      if (raw is Map) ...Map<String, dynamic>.from(raw),
    };
    final entries = (history[employeeId] is List)
        ? List<dynamic>.from(history[employeeId] as List)
        : <dynamic>[];
    entries.add({
      'id': const Uuid().v4(),
      'eventType': eventType,
      'title': title.trim(),
      'effectiveDate': day(effectiveDate).toIso8601String(),
      'notes': notes.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    history[employeeId] = entries;
    await settings.put(employmentHistorySettingsKey, history);
  }

  Map<String, LeavePolicy> leavePolicies() {
    final settings = Hive.box<dynamic>('app_settings');
    final raw = settings.get(leavePolicySettingsKey);
    final result = <String, LeavePolicy>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (leaveTypes.contains(entry.key) && entry.value is Map) {
          result[entry.key.toString()] = LeavePolicy.fromMap(entry.value as Map);
        }
      }
    }
    for (final type in leaveTypes) {
      result.putIfAbsent(
        type,
        () => LeavePolicy(
          annualEntitlementDays: type == 'casual'
              ? 12
              : type == 'sick'
                  ? 12
                  : type == 'earned'
                      ? 15
                      : 0,
          accrualEnabled: type == 'casual' ||
              type == 'sick' ||
              type == 'earned',
        ),
      );
    }
    return result;
  }

  Future<void> saveLeavePolicies(Map<String, LeavePolicy> policies) async {
    if (policies.keys.any((type) => !leaveTypes.contains(type))) {
      throw const HrServiceException('Unsupported leave policy type.');
    }
    for (final type in leaveTypes) {
      final policy = policies[type];
      if (policy == null ||
          policy.annualEntitlementDays < 0 ||
          policy.annualEntitlementDays > 365) {
        throw const HrServiceException(
          'Leave entitlement must be between 0 and 365 days for every leave type.',
        );
      }
      if (type == 'unpaid' && policy.annualEntitlementDays != 0) {
        throw const HrServiceException('Unpaid leave cannot accrue paid leave days.');
      }
      if (!policy.accrualEnabled && policy.annualEntitlementDays != 0) {
        throw const HrServiceException('Disable accrual only when the entitlement is zero.');
      }
    }
    await Hive.box<dynamic>('app_settings').put(
      leavePolicySettingsKey,
      {for (final entry in policies.entries) entry.key: entry.value.toMap()},
    );
  }

  LeaveBalance leaveBalance({
    required String employeeId,
    required String leaveType,
    DateTime? asOf,
  }) {
    if (!leaveTypes.contains(leaveType) || leaveType == 'unpaid') {
      return LeaveBalance(leaveType: leaveType, entitledDays: 0, usedDays: 0);
    }
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null) throw const HrServiceException('Employee not found.');
    final date = day(asOf ?? DateTime.now());
    final policy = leavePolicies()[leaveType]!;
    if (!policy.accrualEnabled || policy.annualEntitlementDays == 0) {
      return LeaveBalance(leaveType: leaveType, entitledDays: 0, usedDays: 0);
    }
    final yearStart = DateTime(date.year, 1, 1);
    final accrualStart = employee.joiningDate == null ||
            employee.joiningDate!.isBefore(yearStart)
        ? yearStart
        : day(employee.joiningDate!);
    final monthDifference = (date.year - accrualStart.year) * 12 +
        date.month - accrualStart.month;
    final completedMonths = date.isBefore(accrualStart)
        ? 0
        : (monthDifference - (date.day < accrualStart.day ? 1 : 0)).clamp(0, 12);
    final entitled = (policy.annualEntitlementDays * completedMonths / 12)
        .clamp(0.0, policy.annualEntitlementDays.toDouble());
    final used = Hive.box<LeaveRequest>(Boxes.leaveRequests).values
        .where((request) => request.employeeId == employeeId &&
            request.leaveType == leaveType && request.status == 'approved' &&
            !day(request.endDate).isBefore(yearStart) &&
            !day(request.startDate).isAfter(date))
        .fold<int>(0, (sum, request) {
          final start = request.startDate.isBefore(yearStart)
              ? yearStart
              : day(request.startDate);
          final end = request.endDate.isAfter(date)
              ? date
              : day(request.endDate);
          return end.isBefore(start) ? sum : sum + end.difference(start).inDays + 1;
        });
    return LeaveBalance(
      leaveType: leaveType,
      entitledDays: entitled,
      usedDays: used,
    );
  }

  static String attendanceId(String employeeId, DateTime date) {
    final normalized = day(date);
    final dateKey = '${normalized.year.toString().padLeft(4, '0')}'
        '${normalized.month.toString().padLeft(2, '0')}'
        '${normalized.day.toString().padLeft(2, '0')}';
    return 'attendance:${Uri.encodeComponent(employeeId)}:$dateKey';
  }

  Future<EmployeeAttendance> recordAttendance({
    required String employeeId,
    required DateTime date,
    required String status,
    DateTime? checkIn,
    DateTime? checkOut,
    String notes = '',
  }) async {
    final employees = Hive.box<Employee>(Boxes.employees);
    final attendance = Hive.box<EmployeeAttendance>(Boxes.employeeAttendance);
    final employee = employees.get(employeeId);
    if (employee == null || employee.employmentStatus != 'active') {
      throw const HrServiceException('Select an active employee.');
    }
    if (!attendanceStatuses.contains(status)) {
      throw const HrServiceException('Unsupported attendance status.');
    }
    if (checkOut != null && checkIn == null) {
      throw const HrServiceException(
        'Record check-in before recording check-out.',
      );
    }
    final attendanceDay = day(date);
    for (final timestamp in [checkIn, checkOut]) {
      if (timestamp != null && day(timestamp) != attendanceDay) {
        throw const HrServiceException(
          'Check-in and check-out times must belong to the attendance date.',
        );
      }
    }
    if (checkIn != null &&
        checkOut != null &&
        checkOut.isBefore(checkIn)) {
      throw const HrServiceException('Check-out cannot be before check-in.');
    }
    if (status != 'present' && (checkIn != null || checkOut != null)) {
      throw const HrServiceException(
        'Check-in and check-out are only supported for present status.',
      );
    }

    final id = attendanceId(employeeId, date);
    final existing = attendance.get(id);
    if (Hive.isBoxOpen(Boxes.expenses)) {
      final paidToday = Hive.box<Expense>(Boxes.expenses).values.any(
        (expense) =>
            expense.employeeId == employeeId &&
            expense.category == 'Salary-Daily' &&
            day(expense.date) == day(date),
      );
      if (paidToday && (existing == null || existing.status != status)) {
        throw const HrServiceException(
          'Attendance cannot change after a daily wage payment has been recorded.',
        );
      }
    }
    if (existing != null &&
        existing.notes.startsWith('Approved leave request')) {
      throw const HrServiceException(
        'Attendance created by an approved leave request is locked.',
      );
    }
    final record = EmployeeAttendance(
      id: id,
      employeeId: employeeId,
      date: day(date),
      status: status,
      checkIn: checkIn,
      checkOut: checkOut,
      notes: notes.trim(),
    );
    await attendance.put(id, record);
    return record;
  }

  AttendanceSummary summarizeAttendance({
    required String employeeId,
    required DateTime start,
    required DateTime end,
  }) {
    final startDay = day(start);
    final endDay = day(end);
    if (endDay.isBefore(startDay)) {
      throw const HrServiceException('End date cannot be before start date.');
    }
    final records = Hive.box<EmployeeAttendance>(Boxes.employeeAttendance)
        .values
        .where((record) =>
            record.employeeId == employeeId &&
            !record.date.isBefore(startDay) &&
            !record.date.isAfter(endDay));
    var present = 0;
    var half = 0;
    var absent = 0;
    var leave = 0;
    var holidays = 0;
    for (final record in records) {
      switch (record.status) {
        case 'present':
          present++;
          break;
        case 'half_day':
          half++;
          break;
        case 'absent':
          absent++;
          break;
        case 'leave':
          leave++;
          break;
        case 'holiday':
          holidays++;
          break;
      }
    }
    return AttendanceSummary(
      presentDays: present,
      halfDays: half,
      absentDays: absent,
      leaveDays: leave,
      holidays: holidays,
    );
  }

  Future<LeaveRequest> submitLeaveRequest({
    required String employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    String reason = '',
  }) async {
    final employee = Hive.box<Employee>(Boxes.employees).get(employeeId);
    if (employee == null || employee.employmentStatus != 'active') {
      throw const HrServiceException('Select an active employee.');
    }
    if (!leaveTypes.contains(leaveType)) {
      throw const HrServiceException('Unsupported leave type.');
    }
    final start = day(startDate);
    final end = day(endDate);
    if (end.isBefore(start)) {
      throw const HrServiceException('Leave end date cannot be before start date.');
    }

    final requests = Hive.box<LeaveRequest>(Boxes.leaveRequests);
    final overlaps = requests.values.any((request) =>
        request.employeeId == employeeId &&
        (request.status == 'pending' || request.status == 'approved') &&
        !end.isBefore(day(request.startDate)) &&
        !start.isAfter(day(request.endDate)));
    if (overlaps) {
      throw const HrServiceException(
        'This leave overlaps an existing pending or approved request.',
      );
    }

    final request = LeaveRequest(
      id: const Uuid().v4(),
      employeeId: employeeId,
      leaveType: leaveType,
      startDate: start,
      endDate: end,
      reason: reason.trim(),
    );
    await requests.put(request.id, request);
    return request;
  }

  Future<LeaveRequest> reviewLeaveRequest({
    required String requestId,
    required String decision,
    required String reviewerId,
  }) async {
    if (decision != 'approved' && decision != 'rejected') {
      throw const HrServiceException('Decision must be approved or rejected.');
    }
    if (reviewerId.trim().isEmpty) {
      throw const HrServiceException('Reviewer ID is required.');
    }

    final requests = Hive.box<LeaveRequest>(Boxes.leaveRequests);
    final attendance = Hive.box<EmployeeAttendance>(Boxes.employeeAttendance);
    final request = requests.get(requestId);
    if (request == null || request.status != 'pending') {
      throw const HrServiceException('Only pending leave requests can be reviewed.');
    }

    final previousAttendance = <String, EmployeeAttendance?>{};
    if (decision == 'approved') {
      for (var date = day(request.startDate);
          !date.isAfter(day(request.endDate));
          date = date.add(const Duration(days: 1))) {
        final id = attendanceId(request.employeeId, date);
        final existing = attendance.get(id);
        if (existing != null && existing.status != 'leave') {
          throw HrServiceException(
            'Attendance already exists for ${date.toIso8601String()}.',
          );
        }
      }

      try {
        for (var date = day(request.startDate);
            !date.isAfter(day(request.endDate));
            date = date.add(const Duration(days: 1))) {
          final id = attendanceId(request.employeeId, date);
          final existing = attendance.get(id);
          previousAttendance[id] = existing;
          await attendance.put(
            id,
            EmployeeAttendance(
              id: id,
              employeeId: request.employeeId,
              date: date,
              status: 'leave',
              notes: 'Approved leave request $requestId',
              checkIn: existing?.checkIn,
              checkOut: existing?.checkOut,
            ),
          );
        }
      } catch (_) {
        for (final entry in previousAttendance.entries.toList().reversed) {
          try {
            if (entry.value == null) {
              await attendance.delete(entry.key);
            } else {
              await attendance.put(entry.key, entry.value!);
            }
          } catch (_) {}
        }
        rethrow;
      }
    }

    final reviewed = LeaveRequest(
      id: request.id,
      employeeId: request.employeeId,
      leaveType: request.leaveType,
      startDate: request.startDate,
      endDate: request.endDate,
      reason: request.reason,
      status: decision,
      reviewedBy: reviewerId,
      reviewedAt: DateTime.now(),
      createdAt: request.createdAt,
    );
    try {
      await requests.put(reviewed.id, reviewed);
    } catch (_) {
      for (final entry in previousAttendance.entries.toList().reversed) {
        try {
          if (entry.value == null) {
            await attendance.delete(entry.key);
          } else {
            await attendance.put(entry.key, entry.value!);
          }
        } catch (_) {}
      }
      rethrow;
    }
    return reviewed;
  }
}
