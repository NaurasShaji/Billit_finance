import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';

class SecurityQuestionSettingsScreen extends StatefulWidget {
  const SecurityQuestionSettingsScreen({super.key});

  @override
  State<SecurityQuestionSettingsScreen> createState() =>
      _SecurityQuestionSettingsScreenState();
}

class _SecurityQuestionSettingsScreenState
    extends State<SecurityQuestionSettingsScreen> {
  static const _questions = <String>[
    'What is the name of your favourite pet?',
    'What was the name of your first school?',
    'What is the name of the city where you were born?',
    'What was your childhood nickname?',
    'What is the first name of your oldest friend?',
  ];

  final _formKey = GlobalKey<FormState>();
  final _answer = TextEditingController();
  final _currentPassword = TextEditingController();
  late String _question;
  bool _saving = false;
  bool _obscureAnswer = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthService>();
    final current = auth.getAdminSecurityQuestion();
    _question = _questions.contains(current) ? current : _questions.first;
  }

  @override
  void dispose() {
    _answer.dispose();
    _currentPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthService>().updateAdminSecurityQuestion(
            currentPassword: _currentPassword.text,
            question: _question,
            answer: _answer.text.trim(),
          );
      if (!mounted) return;
      _answer.clear();
      _currentPassword.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Security question updated successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Security Question')),
        body: const Center(child: Text('Admin access required.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Security Question')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.shield_outlined, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text('Account recovery', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 8),
                  const Text('Used for password recovery. Choose a question only you can answer.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Form(
            key: _formKey,
            child: Column(children: [
              DropdownButtonFormField<String>(
                value: _question,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Security question',
                  prefixIcon: Icon(Icons.help_outline),
                  border: OutlineInputBorder(),
                ),
                items: _questions.map((q) => DropdownMenuItem(
                  value: q,
                  child: Text(q, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _question = value);
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _answer,
                obscureText: _obscureAnswer,
                decoration: InputDecoration(
                  labelText: 'New security answer',
                  prefixIcon: const Icon(Icons.edit_note),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureAnswer = !_obscureAnswer),
                    icon: Icon(_obscureAnswer ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter an answer'
                    : value.trim().length < 2
                        ? 'Answer must contain at least 2 characters'
                        : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _currentPassword,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Confirm current admin password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter your current password to save this change'
                    : null,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Update security question'),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
