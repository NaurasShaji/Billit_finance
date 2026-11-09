import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../services/payroll_service.dart';
import 'package:intl/intl.dart';
import '../../../models/employee.dart';
import '../../../models/expense.dart';
import '../../../services/boxes.dart';
import '../../../utils/theme_colors.dart';

class DailyWageScreen extends StatelessWidget {
  const DailyWageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'en_IN');

    return Scaffold(
      backgroundColor:
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      appBar: AppBar(
        title: const Text('Daily Wage Payments'),
        backgroundColor: Colors.orange.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Employee>(Boxes.employees).listenable(),
        builder: (context, Box<Employee> empBox, _) {
          return ValueListenableBuilder(
            valueListenable: Hive.box<Expense>(Boxes.expenses).listenable(),
            builder: (context, Box<Expense> expBox, __) {
              final dailyEmployees = empBox.values
                  .where((e) => e.type == 'daily')
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

              if (dailyEmployees.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Daily Wage Employees',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add daily wage employees to manage their payments',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }

              final todayStart = DateTime(DateTime.now().year,
                  DateTime.now().month, DateTime.now().day);
              final todayEnd = todayStart.add(const Duration(days: 1));
              final todaysPayments = expBox.values
                  .where((ex) =>
                      ex.category == 'Salary-Daily' &&
                      !ex.date.isBefore(todayStart) &&
                      ex.date.isBefore(todayEnd))
                  .toList();

              return Column(
                children: [
                  // Summary Header Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.08),
                          offset: const Offset(0, 2),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.schedule_outlined,
                                  color: Colors.orange.shade600,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Daily Wage Overview',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('EEEE, MMMM d, yyyy')
                                          .format(DateTime.now()),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryItem(
                                  'Total Employees',
                                  '${dailyEmployees.length}',
                                  Icons.people_outlined,
                                  Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _buildSummaryItem(
                                  'Paid Today',
                                  '${todaysPayments.length}',
                                  Icons.check_circle_outlined,
                                  Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Employee List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: dailyEmployees.length,
                      itemBuilder: (context, index) {
                        final e = dailyEmployees[index];
                        final controller = TextEditingController(
                            text: e.wage.toStringAsFixed(2));
                        final isPaidToday = PayrollService.isPaid(
                          e,
                          expBox.values,
                          DateTime.now(),
                          allEmployees: empBox.values,
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.08),
                                offset: const Offset(0, 2),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              children: [
                                // Employee Header
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isPaidToday
                                            ? Colors.green.withValues(alpha: 0.12)
                                            : Colors.orange.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.person_outlined,
                                        color: isPaidToday
                                            ? Colors.green.shade600
                                            : Colors.orange.shade600,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            e.name,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Daily Wage Employee',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isPaidToday
                                            ? Colors.green.withValues(alpha: 0.18)
                                            : Colors.red.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isPaidToday
                                                ? Icons.check_circle
                                                : Icons.pending,
                                            size: 16,
                                            color: isPaidToday
                                                ? Colors.green.shade700.adaptive(context)
                                                : Colors.red.shade700.adaptive(context),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            isPaidToday ? 'Paid' : 'Pending',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isPaidToday
                                                  ? Colors.green.shade700.adaptive(context)
                                                  : Colors.red.shade700.adaptive(context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 20),

                                // Payment Section
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.3),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: theme.colorScheme.outline
                                                .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: TextFormField(
                                          controller: controller,
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          enabled: !isPaidToday,
                                          decoration: InputDecoration(
                                            prefixIcon: Icon(
                                              Icons.currency_rupee_outlined,
                                              color: isPaidToday
                                                  ? theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.4)
                                                  : Colors.orange.shade600,
                                            ),
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 16),
                                            hintText: 'Enter amount',
                                            hintStyle: TextStyle(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.5),
                                            ),
                                          ),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: isPaidToday
                                                ? theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.4)
                                                : theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      height: 56,
                                      child: ElevatedButton.icon(
                                        onPressed: isPaidToday
                                            ? null
                                            : () => _processPayment(context, e,
                                                controller, expBox, currency),
                                        icon: Icon(isPaidToday
                                            ? Icons.check
                                            : Icons.payment_outlined),
                                        label: Text(
                                            isPaidToday ? 'Paid' : 'Pay Now'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isPaidToday
                                              ? Theme.of(context).colorScheme.outline
                                              : Colors.orange.shade600,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor:
                                              Theme.of(context).colorScheme.surfaceContainerHighest,
                                          disabledForegroundColor:
                                              Theme.of(context).colorScheme.onSurfaceVariant,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 20, vertical: 16),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, IconData icon, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.shade600, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _processPayment(
    BuildContext context,
    Employee employee,
    TextEditingController controller,
    Box<Expense> expBox,
    NumberFormat currency,
  ) async {
    final amount = double.tryParse(controller.text.trim());

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter a valid amount'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    // Show confirmation dialog
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.payment, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('Confirm Payment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pay daily wage to ${employee.name}?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.currency_rupee,
                      color: Colors.orange.shade600, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    currency.format(amount),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade700.adaptive(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (shouldProceed == true) {
      await PayrollService.recordPayment(employee, amount);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Paid ${currency.format(amount)} to ${employee.name}'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
}
