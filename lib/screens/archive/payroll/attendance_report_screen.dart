import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_service.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  late DateTime _start;
  late DateTime _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month + 1, 0);
  }

  Future<void> _pickRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _start, end: _end),
    );
    if (selected != null) {
      setState(() {
        _start = selected.start;
        _end = selected.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance report'),
        actions: [
          IconButton(
            onPressed: _pickRange,
            tooltip: 'Select date range',
            icon: const Icon(Icons.date_range_outlined),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<Employee>>(
        valueListenable: Hive.box<Employee>(Boxes.employees).listenable(),
        builder: (context, employeesBox, _) =>
            ValueListenableBuilder<Box<EmployeeAttendance>>(
          valueListenable:
              Hive.box<EmployeeAttendance>(Boxes.employeeAttendance).listenable(),
          builder: (context, attendanceBox, __) {
            final employees = employeesBox.values.toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            if (employees.isEmpty) {
              return const Center(child: Text('No employee records available.'));
            }
            final service = HrService();
            final rows = employees.map((employee) {
              final summary = service.summarizeAttendance(
                employeeId: employee.id,
                start: _start,
                end: _end,
              );
              return (employee: employee, summary: summary);
            }).toList();
            final totals = rows.fold<(int, int, int, int, int)>((0, 0, 0, 0, 0),
                (sum, row) => (
                  sum.$1 + row.summary.presentDays,
                  sum.$2 + row.summary.halfDays,
                  sum.$3 + row.summary.absentDays,
                  sum.$4 + row.summary.leaveDays,
                  sum.$5 + row.summary.holidays,
                ));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Reporting period'),
                    subtitle: Text('${dateFormat.format(_start)} – ${dateFormat.format(_end)}'),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickRange,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _totalChip('Present', totals.$1),
                    _totalChip('Half day', totals.$2),
                    _totalChip('Absent', totals.$3),
                    _totalChip('Leave', totals.$4),
                    _totalChip('Holiday', totals.$5),
                  ],
                ),
                const SizedBox(height: 12),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      title: Text(row.employee.name),
                      subtitle: Text(
                        'Present ${row.summary.presentDays} · '
                        'Half ${row.summary.halfDays} · '
                        'Absent ${row.summary.absentDays} · '
                        'Leave ${row.summary.leaveDays} · '
                        'Holiday ${row.summary.holidays}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(row.summary.payableDays.toStringAsFixed(1),
                              style: Theme.of(context).textTheme.titleMedium),
                          const Text('Payable days'),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _totalChip(String label, int count) => Chip(label: Text('$label: $count'));
}
