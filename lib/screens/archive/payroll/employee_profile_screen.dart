import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import 'salary_components_screen.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key, required this.employee});

  final Employee employee;

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _designation;
  late final TextEditingController _emergency;
  late final TextEditingController _address;
  late final TextEditingController _notes;
  late String _status;
  String? _departmentId;
  DateTime? _joiningDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final employee = widget.employee;
    _name = TextEditingController(text: employee.name);
    _code = TextEditingController(text: employee.employeeCode);
    _phone = TextEditingController(text: employee.phone);
    _email = TextEditingController(text: employee.email);
    _designation = TextEditingController(text: employee.designation);
    _emergency = TextEditingController(text: employee.emergencyContact);
    _address = TextEditingController(text: employee.address);
    _notes = TextEditingController(text: employee.notes);
    _status = employee.employmentStatus;
    _departmentId = employee.departmentId;
    _joiningDate = employee.joiningDate;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _code,
      _phone,
      _email,
      _designation,
      _emergency,
      _address,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickJoiningDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joiningDate ?? DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _joiningDate = picked);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final code = _code.text.trim();
    final duplicateCode = code.isNotEmpty &&
        Hive.box<Employee>(Boxes.employees).values.any((employee) =>
            employee.id != widget.employee.id &&
            employee.employeeCode.toLowerCase() == code.toLowerCase());
    if (duplicateCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee code already exists.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final employee = widget.employee
        ..name = _name.text.trim()
        ..employeeCode = code
        ..phone = _phone.text.trim()
        ..email = _email.text.trim()
        ..departmentId = _departmentId
        ..designation = _designation.text.trim()
        ..joiningDate = _joiningDate
        ..employmentStatus = _status
        ..emergencyContact = _emergency.text.trim()
        ..address = _address.text.trim()
        ..notes = _notes.text.trim();
      await employee.save();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save employee profile: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Employee profile')),
      body: ValueListenableBuilder<Box<HrDepartment>>(
        valueListenable:
            Hive.box<HrDepartment>(Boxes.hrDepartments).listenable(),
        builder: (context, departments, _) {
          final availableDepartments = departments.values
              .where((department) =>
                  department.active || department.id == _departmentId)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Enter employee name'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Employee code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final email = (value ?? '').trim();
                    if (email.isNotEmpty &&
                        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(email)) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _departmentId,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    for (final department in availableDepartments)
                      DropdownMenuItem(
                        value: department.id,
                        child: Text(department.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _departmentId = value),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _designation,
                  decoration: const InputDecoration(
                    labelText: 'Designation',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _pickJoiningDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    _joiningDate == null
                        ? 'Set joining date'
                        : 'Joined ${dateFormat.format(_joiningDate!)}',
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    labelText: 'Employment status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                    DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                    DropdownMenuItem(value: 'terminated', child: Text('Terminated')),
                  ],
                  onChanged: (value) =>
                      setState(() => _status = value ?? _status),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emergency,
                  decoration: const InputDecoration(
                    labelText: 'Emergency contact',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _address,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SalaryComponentsScreen(
                        employee: widget.employee,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Manage salary components'),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save profile'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
