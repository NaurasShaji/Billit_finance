import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_service.dart';
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

  Future<void> _addHistoryEvent() async {
    String eventType = 'other';
    DateTime effectiveDate = DateTime.now();
    final title = TextEditingController();
    final notes = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add employment history'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: eventType,
                    decoration: const InputDecoration(labelText: 'Event type'),
                    items: const [
                      DropdownMenuItem(value: 'joining', child: Text('Joining')),
                      DropdownMenuItem(value: 'designation', child: Text('Designation change')),
                      DropdownMenuItem(value: 'department', child: Text('Department change')),
                      DropdownMenuItem(value: 'status', child: Text('Employment status')),
                      DropdownMenuItem(value: 'pay_change', child: Text('Pay change')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (value) => setDialogState(() => eventType = value ?? eventType),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: effectiveDate,
                        firstDate: DateTime(1980),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setDialogState(() => effectiveDate = picked);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(DateFormat('dd MMM yyyy').format(effectiveDate)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save event')),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await HrService().addEmploymentHistory(
          employeeId: widget.employee.id,
          eventType: eventType,
          title: title.text,
          effectiveDate: effectiveDate,
          notes: notes.text,
        );
        if (mounted) setState(() {});
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not add employment history: $error')),
          );
        }
      }
    }
    title.dispose();
    notes.dispose();
  }

  Future<void> _addEmployeeDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'doc', 'docx'],
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw StateError('The selected file could not be read.');
      }
      await HrService().addEmployeeDocument(
        employeeId: widget.employee.id,
        fileName: file.name,
        bytes: bytes,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add document: $error')),
        );
      }
    }
  }

  Future<void> _downloadEmployeeDocument(Map<String, dynamic> document) async {
    try {
      final bytes = HrService().employeeDocumentBytes(document);
      final name = document['name'] as String;
      final extension = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mimeType = extension == 'pdf'
          ? MimeType.pdf
          : extension == 'png'
              ? MimeType.png
              : extension == 'jpg' || extension == 'jpeg'
                  ? MimeType.jpeg
                  : MimeType.other;
      await FileSaver.instance.saveFile(
        name: name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name,
        bytes: bytes,
        fileExtension: extension,
        mimeType: mimeType,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export document: $error')),
        );
      }
    }
  }

  Future<void> _deleteEmployeeDocument(Map<String, dynamic> document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete employee document?'),
        content: Text('Delete "${document['name']}" from this employee profile?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await HrService().deleteEmployeeDocument(
        employeeId: widget.employee.id,
        documentId: document['id'] as String,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete document: $error')),
        );
      }
    }
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text('Employment history', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      onPressed: _addHistoryEvent,
                      tooltip: 'Add history event',
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                ...HrService().employmentHistory(widget.employee.id).map((entry) {
                  final effective = DateTime.parse(entry['effectiveDate'] as String);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: Text(entry['title'] as String? ?? ''),
                    subtitle: Text('${(entry['eventType'] as String? ?? 'other').replaceAll('_', ' ')} · ${dateFormat.format(effective)}${(entry['notes'] as String? ?? '').isEmpty ? '' : '\\n${entry['notes']}'}'),
                    isThreeLine: (entry['notes'] as String? ?? '').isNotEmpty,
                  );
                }),
                if (HrService().employmentHistory(widget.employee.id).isEmpty)
                  const Text('No employment history recorded.'),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text('Employee documents',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      onPressed: _addEmployeeDocument,
                      tooltip: 'Add document (administrator only)',
                      icon: const Icon(Icons.upload_file_outlined),
                    ),
                  ],
                ),
                const Text(
                  'PDF, PNG, JPG, DOC, and DOCX · maximum 2 MB per file · administrator access only',
                ),
                ...HrService().employeeDocuments(widget.employee.id).map((document) {
                  final size = (document['sizeBytes'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(document['name'] as String? ?? 'Document'),
                    subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Export document',
                          onPressed: () => _downloadEmployeeDocument(document),
                          icon: const Icon(Icons.download_outlined),
                        ),
                        IconButton(
                          tooltip: 'Delete document',
                          onPressed: () => _deleteEmployeeDocument(document),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  );
                }),
                if (HrService().employeeDocuments(widget.employee.id).isEmpty)
                  const Text('No documents stored.'),
                const SizedBox(height: 12),
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
