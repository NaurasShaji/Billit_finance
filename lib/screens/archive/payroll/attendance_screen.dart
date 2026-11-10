import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_service.dart';
import 'attendance_report_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _date = DateTime.now();

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _setStatus(Employee employee, String? status) async {
    final attendance = Hive.box<EmployeeAttendance>(Boxes.employeeAttendance);
    final id = HrService.attendanceId(employee.id, _date);
    try {
      if (status == null) {
        await attendance.delete(id);
      } else {
        await HrService().recordAttendance(
          employeeId: employee.id,
          date: _date,
          status: status,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update attendance: $error')),
        );
      }
    }
  }

  Future<void> _setAttendanceTime(
    Employee employee,
    EmployeeAttendance record,
    bool isCheckIn,
  ) async {
    final current = isCheckIn ? record.checkIn : record.checkOut;
    final selected = await showTimePicker(
      context: context,
      initialTime: current == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(current),
    );
    if (selected == null || !mounted) return;
    final value = DateTime(
      _date.year, _date.month, _date.day, selected.hour, selected.minute,
    );
    try {
      await HrService().recordAttendance(
        employeeId: employee.id,
        date: _date,
        status: 'present',
        checkIn: isCheckIn ? value : record.checkIn,
        checkOut: isCheckIn ? record.checkOut : value,
        notes: record.notes,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update attendance time: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEEE, dd MMM yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AttendanceReportScreen()),
            ),
            tooltip: 'Attendance report',
            icon: const Icon(Icons.assessment_outlined),
          ),
          IconButton(
            onPressed: _pickDate,
            tooltip: 'Select date',
            icon: const Icon(Icons.calendar_month_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    dateFormat.format(_date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _date = DateTime.now()),
                  child: const Text('Today'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<Box<Employee>>(
              valueListenable:
                  Hive.box<Employee>(Boxes.employees).listenable(),
              builder: (context, employeesBox, _) =>
                  ValueListenableBuilder<Box<EmployeeAttendance>>(
                valueListenable:
                    Hive.box<EmployeeAttendance>(Boxes.employeeAttendance)
                        .listenable(),
                builder: (context, attendanceBox, __) {
                  final employees = employeesBox.values
                      .where((employee) =>
                          employee.employmentStatus == 'active')
                      .toList()
                    ..sort((a, b) => a.name.compareTo(b.name));
                  if (employees.isEmpty) {
                    return const Center(
                      child: Text('No active employees to mark attendance.'),
                    );
                  }
                  final counts = <String, int>{
                    'present': 0,
                    'half_day': 0,
                    'absent': 0,
                    'leave': 0,
                    'holiday': 0,
                  };
                  for (final employee in employees) {
                    final record = attendanceBox.get(
                      HrService.attendanceId(employee.id, _date),
                    );
                    if (record != null) {
                      counts[record.status] = (counts[record.status] ?? 0) + 1;
                    }
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _countChip('Present', counts['present'] ?? 0),
                          _countChip('Half day', counts['half_day'] ?? 0),
                          _countChip('Absent', counts['absent'] ?? 0),
                          _countChip('Leave', counts['leave'] ?? 0),
                          _countChip('Holiday', counts['holiday'] ?? 0),
                        ],
                      ),
                      const SizedBox(height: 16),
                      for (final employee in employees)
                        _attendanceTile(
                          employee,
                          attendanceBox.get(
                            HrService.attendanceId(employee.id, _date),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, int count) => Chip(
        label: Text('$label: $count'),
        visualDensity: VisualDensity.compact,
      );

  Widget _attendanceTile(
    Employee employee,
    EmployeeAttendance? record,
  ) {
    final status = record?.status;
    final approvedLeave = record?.notes.startsWith('Approved leave request') ?? false;
    final timeFormat = DateFormat('hh:mm a');
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.name, style: Theme.of(context).textTheme.titleSmall),
                      Text(employee.employeeCode.isEmpty
                          ? (employee.designation.isEmpty
                              ? (employee.type == 'daily' ? 'Daily wage' : 'Monthly salary')
                              : employee.designation)
                          : employee.employeeCode),
                    ],
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String?>(
                    value: status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Attendance',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('Not marked')),
                      DropdownMenuItem(value: 'present', child: Text('Present')),
                      DropdownMenuItem(value: 'half_day', child: Text('Half day')),
                      DropdownMenuItem(value: 'absent', child: Text('Absent')),
                      DropdownMenuItem(value: 'holiday', child: Text('Holiday')),
                      DropdownMenuItem(value: 'leave', child: Text('Leave')),
                    ],
                    onChanged: approvedLeave ? null : (value) => _setStatus(employee, value),
                  ),
                ),
              ],
            ),
            if (status == 'present' && record != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: approvedLeave ? null : () => _setAttendanceTime(employee, record, true),
                    icon: const Icon(Icons.login, size: 16),
                    label: Text(record.checkIn == null ? 'Check in' : 'In ${timeFormat.format(record.checkIn!)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: approvedLeave || record.checkIn == null
                        ? null
                        : () => _setAttendanceTime(employee, record, false),
                    icon: const Icon(Icons.logout, size: 16),
                    label: Text(record.checkOut == null ? 'Check out' : 'Out ${timeFormat.format(record.checkOut!)}'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
