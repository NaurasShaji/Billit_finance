import 'package:hive/hive.dart';
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

    final insertedAttendanceIds = <String>[];
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
          if (attendance.containsKey(id)) continue;
          await attendance.put(
            id,
            EmployeeAttendance(
              id: id,
              employeeId: request.employeeId,
              date: date,
              status: 'leave',
              notes: 'Approved leave request $requestId',
            ),
          );
          insertedAttendanceIds.add(id);
        }
      } catch (_) {
        for (final id in insertedAttendanceIds.reversed) {
          try {
            await attendance.delete(id);
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
      for (final id in insertedAttendanceIds.reversed) {
        try {
          await attendance.delete(id);
        } catch (_) {}
      }
      rethrow;
    }
    return reviewed;
  }
}
