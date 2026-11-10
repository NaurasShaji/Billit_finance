import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';

class DepartmentManagementScreen extends StatelessWidget {
  const DepartmentManagementScreen({super.key});

  Future<void> _editDepartment(
    BuildContext context, {
    HrDepartment? department,
  }) async {
    final name = TextEditingController(text: department?.name ?? '');
    final description =
        TextEditingController(text: department?.description ?? '');
    final formKey = GlobalKey<FormState>();
    final box = Hive.box<HrDepartment>(Boxes.hrDepartments);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(department == null ? 'New department' : 'Edit department'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter a department name'
                    : null,
              ),
              TextFormField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final normalizedName = name.text.trim();
      final duplicate = box.values.any((item) =>
          item.id != department?.id &&
          item.name.toLowerCase() == normalizedName.toLowerCase());
      if (duplicate) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Department name already exists.')),
          );
        }
      } else if (department == null) {
        final id = const Uuid().v4();
        await box.put(
          id,
          HrDepartment(
            id: id,
            name: normalizedName,
            description: description.text.trim(),
          ),
        );
      } else {
        final updated = HrDepartment(
          id: department.id,
          name: normalizedName,
          description: description.text.trim(),
          active: department.active,
          createdAt: department.createdAt,
        );
        await box.put(updated.id, updated);
      }
    }
    name.dispose();
    description.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Departments'),
        actions: [
          IconButton(
            onPressed: () => _editDepartment(context),
            tooltip: 'Add department',
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<HrDepartment>>(
        valueListenable:
            Hive.box<HrDepartment>(Boxes.hrDepartments).listenable(),
        builder: (context, box, _) {
          final departments = box.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: departments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final department = departments[index];
              final employeeCount = Hive.box<Employee>(Boxes.employees)
                  .values
                  .where((employee) => employee.departmentId == department.id)
                  .length;
              return Card(
                child: ListTile(
                  title: Text(department.name),
                  subtitle: Text(
                    '$employeeCount employees'
                    '${department.active ? '' : ' • Archived'}'
                    '${department.description.isEmpty ? '' : '\n${department.description}'}',
                  ),
                  isThreeLine: department.description.isNotEmpty,
                  onTap: () =>
                      _editDepartment(context, department: department),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        await _editDepartment(context, department: department);
                      } else if (value == 'toggle') {
                        final updated = HrDepartment(
                          id: department.id,
                          name: department.name,
                          description: department.description,
                          active: !department.active,
                          createdAt: department.createdAt,
                        );
                        await box.put(updated.id, updated);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          department.active ? 'Archive' : 'Reactivate',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editDepartment(context),
        icon: const Icon(Icons.add),
        label: const Text('Department'),
      ),
    );
  }
}
