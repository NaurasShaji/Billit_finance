import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/boxes.dart';
import '../../services/finance_service.dart';
import '../../services/payroll_service.dart';
import '../../utils/theme_colors.dart';
import '../../widgets/app_components.dart';
import '../archive/payroll/add_employee_screen.dart';
import '../archive/payroll/daily_wage_screen.dart';
import '../archive/payroll/monthly_salary_screen.dart';
import '../archive/payroll/payroll_report_screen.dart';
import '../archive/payroll/employee_profile_screen.dart';
import '../archive/payroll/attendance_screen.dart';
import '../archive/payroll/leave_management_screen.dart';
import '../archive/payroll/department_management_screen.dart';

/// Top-level Team screen: who works here, who has been paid, who is due.
class TeamTab extends StatelessWidget {
  const TeamTab({super.key});

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');

    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<Box<Employee>>(
          valueListenable: Hive.box<Employee>(Boxes.employees).listenable(),
          builder: (context, employeesBox, _) =>
              ValueListenableBuilder<Box<Expense>>(
            valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
            builder: (context, expensesBox, __) {
              final employees = employeesBox.values.toList();
              final expenses = expensesBox.values.toList();
              final now = DateTime.now();
              final summary = PayrollService.summarize(employees, expenses, now);

              // Unpaid first, then alphabetical.
              final sorted = [...employees]..sort((a, b) {
                  final activeA = a.employmentStatus == 'active';
                  final activeB = b.employmentStatus == 'active';
                  if (activeA != activeB) return activeA ? -1 : 1;
                  final pa = PayrollService.isPaid(a, expenses, now,
                      allEmployees: employees);
                  final pb = PayrollService.isPaid(b, expenses, now,
                      allEmployees: employees);
                  if (pa != pb) return pa ? 1 : -1;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  _header(context, theme, scheme),
                  const SizedBox(height: 18),
                  if (employees.isEmpty)
                    SizedBox(
                      height: 360,
                      child: AppEmptyState(
                        icon: Icons.groups_outlined,
                        title: 'No team members yet',
                        message: 'Add employees to track monthly salaries '
                            'and daily wages.',
                        actions: [
                          FilledButton.icon(
                            onPressed: () =>
                                _open(context, const AddEmployeeScreen()),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Add employee'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    _metrics(summary, currency),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              _open(context, const MonthlySalaryScreen()),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Pay salaries'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              _open(context, const DailyWageScreen()),
                          icon: const Icon(Icons.today_outlined),
                          label: const Text('Pay daily wages'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _open(context, const PayrollReportScreen()),
                          icon: const Icon(Icons.assessment_outlined),
                          label: const Text('Payroll report'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _open(context, const AttendanceScreen()),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Attendance'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _open(context, const LeaveManagementScreen()),
                          icon: const Icon(Icons.event_available_outlined),
                          label: const Text('Leave'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _open(
                            context,
                            const DepartmentManagementScreen(),
                          ),
                          icon: const Icon(Icons.business_outlined),
                          label: const Text('Departments'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'TEAM',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final e in sorted)
                      _EmployeeCard(
                        employee: e,
                        paid: PayrollService.isPaid(e, expenses, now,
                            allEmployees: employees),
                        attendanceStatus: e.type == PayrollService.typeDaily
                            ? PayrollService.attendanceFor(e, now)?.status
                            : null,
                        paidAmount: PayrollService.paidAmountFor(
                          e, expenses, now, allEmployees: employees),
                        outstanding: PayrollService.outstandingFor(
                          e, expenses, now, allEmployees: employees),
                        currency: currency,
                        onPay: () =>
                            _confirmAndPay(context, e, expenses, employees, currency),
                        onHistory: () => _showHistory(
                            context, e, expenses, employees, currency),
                        onProfile: () => _open(
                          context,
                          EmployeeProfileScreen(employee: e),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, ThemeData theme, ColorScheme scheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Employees and payroll',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: () => _open(context, const AddEmployeeScreen()),
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Manage'),
        ),
      ],
    );
  }

  Widget _metrics(PayrollSummary s, NumberFormat currency) {
    final cards = [
      _StatTile(
        title: 'Paid this month',
        value: currency.format(s.paidThisMonth),
        note: 'Salaries and wages',
        icon: Icons.check_circle_outline_rounded,
        color: Colors.green,
      ),
      _StatTile(
        title: 'Salaries due',
        value: currency.format(s.monthlyDueAmount),
        note: s.monthlyCount == 0
            ? 'No monthly staff'
            : s.monthlyUnpaid == 0
                ? 'All paid this month'
                : '${s.monthlyUnpaid} of ${s.monthlyCount} unpaid',
        icon: Icons.event_available_outlined,
        color: s.monthlyUnpaid == 0 ? Colors.teal : Colors.orange,
      ),
      _StatTile(
        title: 'Wages due today',
        value: currency.format(s.dailyDueTodayAmount),
        note: s.dailyCount == 0
            ? 'No daily-wage staff'
            : s.dailyUnpaidToday == 0
                ? 'All paid today'
                : '${s.dailyUnpaidToday} of ${s.dailyCount} unpaid',
        icon: Icons.today_outlined,
        color: s.dailyUnpaidToday == 0 ? Colors.teal : Colors.orange,
      ),
      _StatTile(
        title: 'Team size',
        value: '${s.employeeCount}',
        note: '${s.monthlyCount} monthly · ${s.dailyCount} daily',
        icon: Icons.groups_outlined,
        color: Colors.blue,
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 720 ? 4 : 2;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in cards) SizedBox(width: width, child: c)],
      );
    });
  }

  Future<void> _confirmAndPay(
    BuildContext context,
    Employee employee,
    List<Expense> expenses,
    List<Employee> employees,
    NumberFormat currency,
  ) async {
    final isDaily = employee.type == PayrollService.typeDaily;
    final outstanding = PayrollService.outstandingFor(
      employee, expenses, DateTime.now(), allEmployees: employees);
    if (outstanding <= 0.005) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDaily ? 'Pay daily wage' : 'Pay monthly salary'),
        content: Text(
          'Pay the remaining ${currency.format(outstanding)} to ${employee.name}? '
          'This is recorded as an expense.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await PayrollService.recordPayment(employee, outstanding);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Paid ${currency.format(employee.wage)} to ${employee.name}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showHistory(
    BuildContext context,
    Employee employee,
    List<Expense> expenses,
    List<Employee> employees,
    NumberFormat currency,
  ) {
    final payments = PayrollService.paymentsFor(
      employee,
      expenses,
      DateSpan(DateTime(2000), DateTime(2200)),
      allEmployees: employees,
    )..sort((a, b) => b.date.compareTo(a.date));
    final dateFmt = DateFormat('dd MMM yyyy');

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '${employee.name} · payment history',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (payments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 28),
                    child: Text('No payments recorded yet.'),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: payments.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(currency.format(payments[i].amount)),
                        subtitle: Text(dateFmt.format(payments[i].date)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.note,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String note;
  final IconData icon;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color.shade700.adaptive(context)),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    required this.paid,
    required this.attendanceStatus,
    required this.paidAmount,
    required this.outstanding,
    required this.currency,
    required this.onPay,
    required this.onHistory,
    required this.onProfile,
  });

  final Employee employee;
  final bool paid;
  final String? attendanceStatus;
  final double paidAmount;
  final double outstanding;
  final NumberFormat currency;
  final VoidCallback onPay;
  final VoidCallback onHistory;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDaily = employee.type == PayrollService.typeDaily;
    final active = employee.employmentStatus == 'active';
    final attendanceNotEligible = isDaily &&
        (attendanceStatus == null ||
            (attendanceStatus != 'present' && attendanceStatus != 'half_day'));
    final statusColor = !active || attendanceNotEligible
        ? Colors.grey
        : paid
            ? Colors.green
            : Colors.orange;
    final partiallyPaid = paidAmount > 0.005 && !paid;
    final statusText = !active
        ? employee.employmentStatus.replaceAll('_', ' ').toUpperCase()
        : attendanceNotEligible
            ? attendanceStatus == null
                ? 'Attendance not marked'
                : 'No wage due today'
            : paid
                ? (isDaily ? 'Paid today' : 'Paid this month')
                : partiallyPaid
                    ? 'Partially paid · ${currency.format(outstanding)} due'
                    : (isDaily ? 'Wage due' : 'Salary due');
    final initial =
        employee.name.trim().isEmpty ? '?' : employee.name.trim()[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.panelColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onProfile,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(initial,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${isDaily ? 'Daily wage' : 'Monthly salary'} · '
                        '${currency.format(employee.wage)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusText,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: statusColor.shade800.adaptive(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Payment history',
                  onPressed: onHistory,
                  icon: const Icon(Icons.history),
                ),
                if (active && !attendanceNotEligible && !paid)
                  FilledButton.tonal(onPressed: onPay, child: const Text('Pay'))
                else if (active && !attendanceNotEligible)
                  Icon(Icons.check_circle_rounded,
                      color: Colors.green.shade600.adaptive(context))
                else
                  const Icon(Icons.person_off_outlined),
              ],
            ),
          ),
        ),
      ),
    );
  }
}