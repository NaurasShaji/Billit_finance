import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';

import '../../../models/models.dart';
import '../../../services/boxes.dart';
import '../../../services/hr_service.dart';
import '../../../services/hr_payroll_service.dart';
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
  String _employmentType = 'permanent';
  String _payFrequency = 'monthly';
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
    final workTerms = HrService().employeeWorkTerms(employee);
    _employmentType = workTerms['employmentType']!;
    _payFrequency = workTerms['payFrequency']!;
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

  Future<void> _addEmployeeAdvance() async {
    final principal = TextEditingController();
    final installment = TextEditingController();
    final description = TextEditingController(text: 'Employee advance');
    DateTime issueDate = DateTime.now(), dueDate = DateTime.now();
    String cashAccountId = 'system:cash';
    final cashAccounts = Hive.box<FinanceAccount>(Boxes.financeAccounts).values
        .where((account) => account.active && account.accountType == 'asset' && account.currencyCode == 'INR').toList();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (dc) =>
      StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
        title: const Text('Issue employee advance'),
        content: Form(key: key, child: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(value: cashAccounts.any((a) => a.id == cashAccountId) ? cashAccountId : cashAccounts.first.id, decoration: const InputDecoration(labelText: 'Paid from account'), items: [for (final account in cashAccounts) DropdownMenuItem(value: account.id, child: Text(account.name))], onChanged: (value) => setDialogState(() => cashAccountId = value ?? cashAccountId)),
          TextFormField(controller: description, decoration: const InputDecoration(labelText: 'Description'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a description' : null),
          TextFormField(controller: principal, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Advance amount', prefixText: '₹ '),
            validator: (v) { final n = double.tryParse((v ?? '').trim()); return n == null || !n.isFinite || n <= 0 ? 'Enter a positive amount' : null; }),
          TextFormField(controller: installment, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monthly instalment', prefixText: '₹ '),
            validator: (v) { final n = double.tryParse((v ?? '').trim()), p = double.tryParse(principal.text.trim()); return n == null || !n.isFinite || n <= 0 || p == null || n > p ? 'Enter an instalment up to the advance amount' : null; }),
          OutlinedButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: issueDate, firstDate: DateTime(1980), lastDate: DateTime.now()); if (d != null) setDialogState(() { issueDate = d; if (dueDate.isBefore(d)) dueDate = d; }); }, child: Text('Issue date: ${DateFormat('dd MMM yyyy').format(issueDate)}')),
          OutlinedButton(onPressed: () async { final d = await showDatePicker(context: context, initialDate: dueDate, firstDate: issueDate, lastDate: DateTime.now().add(const Duration(days: 3650))); if (d != null) setDialogState(() => dueDate = d); }, child: Text('First repayment: ${DateFormat('dd MMM yyyy').format(dueDate)}')),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
          FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(dc, true); }, child: const Text('Save advance'))],
      )));
    if (saved == true) {
      try {
        await HrPayrollService().addEmployeeAdvance(employeeId: widget.employee.id,
          principalPaise: (double.parse(principal.text) * 100).round(),
          installmentPaise: (double.parse(installment.text) * 100).round(),
          issueDate: issueDate, firstDueDate: dueDate, description: description.text, cashAccountId: cashAccountId);
        if (mounted) setState(() {});
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not issue advance: $e'))); }
    }
    principal.dispose(); installment.dispose(); description.dispose();
  }

  Future<void> _recordAdvanceRepayment(Map<String,dynamic> advance) async {
    final amount = TextEditingController(), note = TextEditingController();
    String cashAccountId = 'system:cash';
    final cashAccounts = Hive.box<FinanceAccount>(Boxes.financeAccounts).values
        .where((account) => account.active && account.accountType == 'asset' && account.currencyCode == 'INR').toList();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (dc) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Record advance repayment'),
      content: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: cashAccounts.any((a) => a.id == cashAccountId) ? cashAccountId : cashAccounts.first.id, decoration: const InputDecoration(labelText: 'Received into account'), items: [for (final account in cashAccounts) DropdownMenuItem(value: account.id, child: Text(account.name))], onChanged: (value) => setDialogState(() => cashAccountId = value ?? cashAccountId)),
        Text('Outstanding: ₹${((advance['outstandingPaise'] as int) / 100).toStringAsFixed(2)}'),
        TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount received', prefixText: '₹ '),
          validator: (v) { final n = double.tryParse((v ?? '').trim()); return n == null || !n.isFinite || n <= 0 || (n * 100).round() > (advance['outstandingPaise'] as int) ? 'Enter an amount within the outstanding balance' : null; }),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(dc, true); }, child: const Text('Record'))],
    )));
    if (saved == true) {
      try {
        await HrPayrollService().recordAdvanceRepayment(employeeId: widget.employee.id,
          advanceId: advance['id'] as String, amountPaise: (double.parse(amount.text) * 100).round(),
          date: DateTime.now(), note: note.text, cashAccountId: cashAccountId);
        if (mounted) setState(() {});
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not record repayment: $e'))); }
    }
    amount.dispose(); note.dispose();
  }

  Future<void> _addBonusEntry() async {
    final description = TextEditingController(text: 'Bonus');
    final amount = TextEditingController();
    DateTime date = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record one-off bonus'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Enter a description'
                        : null,
                  ),
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Bonus amount', prefixText: '₹ '),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      return parsed == null || !parsed.isFinite || parsed <= 0
                          ? 'Enter a positive amount'
                          : null;
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(1980),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(DateFormat('dd MMM yyyy').format(date)),
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
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save bonus'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        await HrPayrollService().addBonusEntry(
          employeeId: widget.employee.id,
          date: date,
          amountPaise: (double.parse(amount.text.trim()) * 100).round(),
          description: description.text,
        );
        if (mounted) setState(() {});
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not record bonus: $error')),
          );
        }
      }
    }
    description.dispose();
    amount.dispose();
  }

  Future<void> _reviewOvertimeEntry(
    Map<String, dynamic> entry, {
    required bool approve,
  }) async {
    final reason = TextEditingController();
    if (!approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reject overtime'),
          content: TextField(
            controller: reason,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason for rejection',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                reason.text.trim().isNotEmpty,
              ),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        reason.dispose();
        return;
      }
    }
    try {
      if (approve) {
        await HrPayrollService().approveOvertimeEntry(
          employeeId: widget.employee.id,
          entryId: entry['id'] as String,
        );
      } else {
        await HrPayrollService().rejectOvertimeEntry(
          employeeId: widget.employee.id,
          entryId: entry['id'] as String,
          reason: reason.text,
        );
      }
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not review overtime: $error')),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _addOvertimeEntry() async {
    final hours = TextEditingController();
    final rate = TextEditingController();
    DateTime date = DateTime.now();
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record overtime'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(1980),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => date = picked);
                    },
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(DateFormat('dd MMM yyyy').format(date)),
                  ),
                  TextFormField(
                    controller: hours,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Overtime hours'),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      return parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 24
                          ? 'Enter hours between 0 and 24'
                          : null;
                    },
                  ),
                  TextFormField(
                    controller: rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Hourly rate', prefixText: '₹ '),
                    validator: (value) {
                      final parsed = double.tryParse((value ?? '').trim());
                      return parsed == null || !parsed.isFinite || parsed <= 0
                          ? 'Enter a positive hourly rate'
                          : null;
                    },
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
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Save overtime'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      try {
        final hourlyRatePaise = (double.parse(rate.text.trim()) * 100).round();
        await HrPayrollService().addOvertimeEntry(
          employeeId: widget.employee.id,
          date: date,
          hours: double.parse(hours.text.trim()),
          hourlyRatePaise: hourlyRatePaise,
        );
        if (mounted) setState(() {});
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not record overtime: $error')),
          );
        }
      }
    }
    hours.dispose();
    rate.dispose();
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
      await HrService().saveEmployeeWorkTerms(
        employeeId: employee.id,
        employmentType: _employmentType,
        payFrequency: _payFrequency,
      );
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
                DropdownButtonFormField<String>(
                  value: _employmentType,
                  decoration: const InputDecoration(
                    labelText: 'Employment type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'permanent', child: Text('Permanent')),
                    DropdownMenuItem(value: 'contract', child: Text('Contract')),
                    DropdownMenuItem(value: 'temporary', child: Text('Temporary')),
                    DropdownMenuItem(value: 'intern', child: Text('Intern')),
                    DropdownMenuItem(value: 'part_time', child: Text('Part-time')),
                    DropdownMenuItem(value: 'casual', child: Text('Casual')),
                  ],
                  onChanged: (value) => setState(() => _employmentType = value ?? _employmentType),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _payFrequency,
                  decoration: const InputDecoration(
                    labelText: 'Pay frequency',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'fortnightly', child: Text('Fortnightly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (value) => setState(() => _payFrequency = value ?? _payFrequency),
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
                Row(children: [
                  Expanded(child: Text('Advances & loans', style: Theme.of(context).textTheme.titleMedium)),
                  IconButton(onPressed: _addEmployeeAdvance, tooltip: 'Issue advance', icon: const Icon(Icons.add_circle_outline)),
                ]),
                ...HrPayrollService().advances(widget.employee.id).map((advance) {
                  final outstanding = (advance['outstandingPaise'] as int) / 100;
                  final principal = (advance['principalPaise'] as int) / 100;
                  final due = DateFormat('dd MMM yyyy').format(DateTime.parse(advance['nextDueDate'] as String));
                  final repayments = (advance['repayments'] as List? ?? []).length;
                  return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(advance['description'] as String? ?? 'Employee advance', style: Theme.of(context).textTheme.titleSmall),
                    Text('Issued ₹${principal.toStringAsFixed(2)} · Outstanding ₹${outstanding.toStringAsFixed(2)}'),
                    Text('Instalment ₹${((advance['installmentPaise'] as int) / 100).toStringAsFixed(2)} · Next due $due'),
                    Text('$repayments repayment record(s) · ${advance['status']}'),
                    if (advance['status'] == 'active') Align(alignment: Alignment.centerRight, child: TextButton.icon(
                      onPressed: () => _recordAdvanceRepayment(advance), icon: const Icon(Icons.payments_outlined), label: const Text('Record repayment'))),
                  ])));
                }),
                const SizedBox(height: 18),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text('One-off bonuses',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      onPressed: _addBonusEntry,
                      tooltip: 'Record bonus',
                      icon: const Icon(Icons.card_giftcard_outlined),
                    ),
                  ],
                ),
                ...HrPayrollService().bonusEntries(widget.employee.id).map((entry) {
                  final date = DateTime.parse(entry['date'] as String);
                  final amount = (entry['amountPaise'] as int) / 100;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payments_outlined),
                    title: Text(entry['description'] as String),
                    subtitle: Text(DateFormat('dd MMM yyyy').format(date)),
                    trailing: Text('₹${amount.toStringAsFixed(2)}'),
                  );
                }),
                if (HrPayrollService().bonusEntries(widget.employee.id).isEmpty)
                  const Text('No one-off bonuses recorded.'),
                Row(
                  children: [
                    Expanded(
                      child: Text('Overtime records',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    IconButton(
                      onPressed: _addOvertimeEntry,
                      tooltip: 'Record overtime',
                      icon: const Icon(Icons.more_time),
                    ),
                  ],
                ),
                ...HrPayrollService().overtimeEntries(widget.employee.id).map((entry) {
                  final date = DateTime.parse(entry['date'] as String);
                  final hours = (entry['hoursMilli'] as int) / 1000;
                  final amount = (entry['amountPaise'] as int) / 100;
                  final status = entry['status'] ?? 'approved';
                  final pending = status == 'pending';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      pending ? Icons.pending_outlined :
                          status == 'approved' ? Icons.check_circle_outline : Icons.cancel_outlined,
                    ),
                    title: Text('${DateFormat('dd MMM yyyy').format(date)} · $hours hours'),
                    subtitle: Text('₹${amount.toStringAsFixed(2)} · ${status.toString().toUpperCase()}'),
                    trailing: pending
                        ? Wrap(
                            spacing: 0,
                            children: [
                              IconButton(
                                tooltip: 'Approve overtime',
                                onPressed: () => _reviewOvertimeEntry(entry, approve: true),
                                icon: const Icon(Icons.check_circle_outline),
                              ),
                              IconButton(
                                tooltip: 'Reject overtime',
                                onPressed: () => _reviewOvertimeEntry(entry, approve: false),
                                icon: const Icon(Icons.cancel_outlined),
                              ),
                            ],
                          )
                        : null,
                  );
                }),
                if (HrPayrollService().overtimeEntries(widget.employee.id).isEmpty)
                  const Text('No overtime recorded. Overtime is included in the payroll period containing its date.'),
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
