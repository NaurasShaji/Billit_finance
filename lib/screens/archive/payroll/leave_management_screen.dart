import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_service.dart';

class LeaveManagementScreen extends StatefulWidget {
  const LeaveManagementScreen({super.key});

  @override
  State<LeaveManagementScreen> createState() => _LeaveManagementScreenState();
}

class _LeaveManagementScreenState extends State<LeaveManagementScreen> {
  final _dateFormat = DateFormat('dd MMM yyyy');

  Future<void> _newRequest() async {
    final employees = Hive.box<Employee>(Boxes.employees).values
        .where((employee) => employee.employmentStatus == 'active')
        .toList();
    if (employees.isEmpty) return;
    String employeeId = employees.first.id;
    String leaveType = 'casual';
    DateTimeRange? range;
    final reason = TextEditingController();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New leave request'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: employeeId,
                    decoration: const InputDecoration(labelText: 'Employee'),
                    items: [
                      for (final employee in employees)
                        DropdownMenuItem(
                          value: employee.id,
                          child: Text(employee.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => employeeId = value ?? employeeId),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: leaveType,
                    decoration: const InputDecoration(labelText: 'Leave type'),
                    items: const [
                      DropdownMenuItem(value: 'casual', child: Text('Casual')),
                      DropdownMenuItem(value: 'sick', child: Text('Sick')),
                      DropdownMenuItem(value: 'earned', child: Text('Earned')),
                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => leaveType = value ?? leaveType),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 5),
                        ),
                        initialDateRange: range,
                      );
                      if (picked != null) {
                        setDialogState(() => range = picked);
                      }
                    },
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      range == null
                          ? 'Select leave dates'
                          : '${_dateFormat.format(range!.start)} – '
                              '${_dateFormat.format(range!.end)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: range == null
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Submit request'),
            ),
          ],
        ),
      ),
    );

    if (submitted == true && range != null) {
      try {
        await HrService().submitLeaveRequest(
          employeeId: employeeId,
          leaveType: leaveType,
          startDate: range!.start,
          endDate: range!.end,
          reason: reason.text,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not submit leave: $error')),
          );
        }
      }
    }
    reason.dispose();
  }

  Future<void> _managePolicies() async {
    final service = HrService();
    final current = service.leavePolicies();
    final controllers = <String, TextEditingController>{
      for (final type in HrService.leaveTypes)
        type: TextEditingController(
          text: current[type]!.annualEntitlementDays.toString(),
        ),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annual leave entitlements'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Accrual is monthly from the employee joining date or 1 January, whichever is later. Approved leave reduces the current calendar-year balance.'),
                const SizedBox(height: 12),
                for (final type in HrService.leaveTypes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: controllers[type],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '${type[0].toUpperCase()}${type.substring(1)} (days/year)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save policies')),
        ],
      ),
    );
    if (saved == true) {
      try {
        final policies = <String, LeavePolicy>{};
        for (final type in HrService.leaveTypes) {
          final days = int.tryParse(controllers[type]!.text.trim());
          if (days == null || days < 0 || days > 365) {
            throw const HrServiceException('Enter a whole-number entitlement from 0 to 365 for every leave type.');
          }
          policies[type] = LeavePolicy(
            annualEntitlementDays: days,
            accrualEnabled: days > 0,
          );
        }
        await service.saveLeavePolicies(policies);
        if (mounted) setState(() {});
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save leave policies: $error')),
          );
        }
      }
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _review(LeaveRequest request, String decision) async {
    try {
      await HrService().reviewLeaveRequest(
        requestId: request.id,
        decision: decision,
        reviewerId: 'admin',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              decision == 'approved'
                  ? 'Leave approved and attendance updated.'
                  : 'Leave request rejected.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not review leave: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = Hive.box<Employee>(Boxes.employees);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave management'),
        actions: [
          IconButton(
            onPressed: _managePolicies,
            tooltip: 'Configure leave policies',
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            onPressed: _newRequest,
            tooltip: 'New leave request',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<LeaveRequest>>(
        valueListenable:
            Hive.box<LeaveRequest>(Boxes.leaveRequests).listenable(),
        builder: (context, requests, _) {
          final sorted = requests.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          if (sorted.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_available_outlined, size: 48),
                  const SizedBox(height: 12),
                  const Text('No leave requests'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _newRequest,
                    icon: const Icon(Icons.add),
                    label: const Text('Create request'),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final request = sorted[index];
              final employee = employees.get(request.employeeId);
              final pending = request.status == 'pending';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              employee?.name ?? 'Unknown employee',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Chip(label: Text(request.status.toUpperCase())),
                        ],
                      ),
                      Text(
                        '${request.leaveType.toUpperCase()} · '
                        '${_dateFormat.format(request.startDate)} – '
                        '${_dateFormat.format(request.endDate)}',
                      ),
                      if (employee != null &&
                          request.leaveType != 'unpaid' &&
                          request.leaveType != 'other') ...[
                        const SizedBox(height: 4),
                        Builder(builder: (context) {
                          final balance = HrService().leaveBalance(
                            employeeId: employee.id,
                            leaveType: request.leaveType,
                          );
                          return Text(
                            'Current balance: ${balance.availableDays.toStringAsFixed(1)} days available '
                            '(${balance.entitledDays.toStringAsFixed(1)} accrued, ${balance.usedDays} used)',
                            style: Theme.of(context).textTheme.bodySmall,
                          );
                        }),
                      ],
                      if (request.reason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(request.reason),
                      ],
                      if (request.reviewedAt != null)
                        Text(
                          'Reviewed by ${request.reviewedBy} on '
                          '${_dateFormat.format(request.reviewedAt!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (pending) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _review(request, 'rejected'),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _review(request, 'approved'),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newRequest,
        icon: const Icon(Icons.add),
        label: const Text('Leave request'),
      ),
    );
  }
}
