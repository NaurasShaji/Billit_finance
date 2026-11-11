import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import '../../../models/employee.dart';
import '../../../services/boxes.dart';
import '../../../widgets/responsive_page.dart';

class EmployeesListScreen extends StatelessWidget {
  const EmployeesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(child: Scaffold(
      appBar: AppBar(title: const Text('Employees List')),
      body: ValueListenableBuilder(
        valueListenable: Hive.box<Employee>(Boxes.employees).listenable(),
        builder: (context, Box<Employee> box, _) {
          if (box.isEmpty) {
            return const Center(child: Text('No employees yet'));
          }
          final employees = box.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          return ListView.builder(
            itemCount: employees.length,
            itemBuilder: (context, index) {
              final e = employees[index];
              return ListTile(
                leading: const Icon(Icons.person),
                title: Text(e.name),
                subtitle:
                    Text(e.type == 'daily' ? 'Daily Wage' : 'Monthly Salary'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('₹${e.wage.toStringAsFixed(2)}'),
                    const SizedBox(width: 8),
                    IconButton(tooltip: 'Delete', 
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _showDeleteDialog(context, box, e),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ));
  }

  void _showDeleteDialog(
      BuildContext context, Box<Employee> box, Employee employee) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Employee'),
          content: Text('Are you sure you want to delete ${employee.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                _deleteEmployee(box, employee);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${employee.name} deleted successfully'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _deleteEmployee(Box<Employee> box, Employee employee) {
    // Find the key of the employee and delete it
    for (var key in box.keys) {
      if (box.get(key) == employee) {
        box.delete(key);
        break;
      }
    }
  }
}
