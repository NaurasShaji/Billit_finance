import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../models/models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  UserType _selectedRole = UserType.worker; // Default to worker

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final appColors = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: appColors.surface,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              appColors.primaryContainer.withValues(alpha: 0.22),
              appColors.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 28, 24, viewInsets.bottom + 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Section
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: const BoxDecoration(
                          color: Colors.transparent,
                        ),
                        child: Column(
                          children: [
                            // App Logo/Icon
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: appColors.surfaceContainerHighest,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: appColors.primary
                                        .withValues(alpha: 0.2),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.receipt_long_rounded,
                                size: 40,
                                color: appColors.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Billit',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: appColors.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Retail management, simplified.',
                              style: TextStyle(
                                color: appColors.primary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Login Form
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _form,
                          child: Column(
                            children: [
                              // Role-specific welcome message
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _selectedRole == UserType.worker
                                      ? appColors.secondaryContainer
                                      : appColors.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedRole == UserType.worker
                                        ? appColors.secondary
                                            .withValues(alpha: 0.45)
                                        : appColors.tertiary
                                            .withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _selectedRole == UserType.worker
                                          ? Icons.person
                                          : Icons.admin_panel_settings,
                                      color: _selectedRole == UserType.worker
                                          ? appColors.onSecondaryContainer
                                          : appColors.onTertiaryContainer,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _selectedRole == UserType.worker
                                            ? 'Worker Login - Access billing and inventory'
                                            : 'Admin Login - Full system access',
                                        style: TextStyle(
                                          color: _selectedRole ==
                                                  UserType.worker
                                              ? appColors.onSecondaryContainer
                                              : appColors.onTertiaryContainer,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Role Dropdown
                              DropdownButtonFormField<UserType>(
                                value: _selectedRole,
                                decoration: InputDecoration(
                                  labelText: 'Login As',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: appColors.surfaceContainerHighest,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: UserType.worker,
                                    child: Text('Worker'),
                                  ),
                                  DropdownMenuItem(
                                    value: UserType.admin,
                                    child: Text('Admin'),
                                  ),
                                ],
                                onChanged: (UserType? newValue) {
                                  setState(() {
                                    _selectedRole = newValue!;
                                    _usernameController.text =
                                        _selectedRole == UserType.worker
                                            ? 'worker'
                                            : 'admin';
                                  });
                                },
                              ),
                              const SizedBox(height: 16),

                              // Username Field
                              TextFormField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.username],
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: const Icon(Icons.person_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: appColors.surfaceContainerHighest,
                                ),
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Please enter username'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Password Field
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [AutofillHints.password],
                                onFieldSubmitted: (_) {
                                  if (!_loading) _handleLogin();
                                },
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: appColors.surfaceContainerHighest,
                                ),
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Please enter password'
                                    : null,
                              ),

                              // Forgot Password Link (Admin Only)
                              if (_selectedRole == UserType.admin)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () =>
                                          _showForgotPasswordDialog(),
                                      child: Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          color: appColors.tertiary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 24),

                              // Login Button
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        _selectedRole == UserType.worker
                                            ? appColors.primary
                                            : appColors.tertiary,
                                    foregroundColor:
                                        _selectedRole == UserType.worker
                                            ? appColors.onPrimary
                                            : appColors.onTertiary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    Colors.white),
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.login, size: 20),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Sign In as ${_selectedRole == UserType.worker ? 'Worker' : 'Admin'}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final securityQuestion = Provider.of<AuthService>(context, listen: false).getAdminSecurityQuestion();
    final securityAnswerController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    bool loading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.security,
                color: Theme.of(context).colorScheme.tertiary,
                size: 24, // Reduced size
              ),
              const SizedBox(width: 8), // Reduced spacing
              const Text(
                'Security Question',
                style: TextStyle(
                  fontSize: 18, // Reduced font size
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.85, // Responsive width
            child: SingleChildScrollView(
              // Added scroll capability
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Security Question - Made more compact
                  Container(
                    padding: const EdgeInsets.all(12), // Reduced padding
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .tertiary
                              .withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.pets,
                          color: Colors.orange[600],
                          size: 20, // Reduced size
                        ),
                        const SizedBox(width: 8), // Reduced spacing
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Security Question:',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.tertiary,
                                  fontSize: 12, // Reduced font size
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2), // Reduced spacing
                              Text(
                                securityQuestion,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiaryContainer,
                                  fontSize: 14, // Reduced font size
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16), // Reduced spacing

                  // Security Answer Field - More compact
                  TextFormField(
                    controller: securityAnswerController,
                    decoration: const InputDecoration(
                      labelText: 'Your Answer',
                      prefixIcon: Icon(Icons.edit_note),
                      border: OutlineInputBorder(),
                      hintText: 'Enter your answer',
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12), // Compact padding
                      isDense: true, // Make field more compact
                    ),
                  ),
                  const SizedBox(height: 16), // Reduced spacing

                  // New Password Field - More compact
                  TextFormField(
                    controller: newPasswordController,
                    obscureText: obscureNewPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(
                            () => obscureNewPassword = !obscureNewPassword),
                        icon: Icon(
                          obscureNewPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                      hintText: 'Enter new password',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12), // Compact padding
                      isDense: true, // Make field more compact
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter new password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12), // Reduced spacing

                  // Confirm Password Field - More compact
                  TextFormField(
                    controller: confirmPasswordController,
                    obscureText: obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setDialogState(() =>
                            obscureConfirmPassword = !obscureConfirmPassword),
                        icon: Icon(
                          obscureConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                      hintText: 'Confirm new password',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12), // Compact padding
                      isDense: true, // Make field more compact
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm new password';
                      }
                      if (value != newPasswordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16), // Reduced spacing

                  // Info Text - More compact
                  Container(
                    padding: const EdgeInsets.all(10), // Reduced padding
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                          size: 18, // Reduced size
                        ),
                        const SizedBox(width: 6), // Reduced spacing
                        Expanded(
                          child: Text(
                            'Answer your security question to reset the admin password.',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                              fontSize: 12, // Reduced font size
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: loading
                  ? null
                  : () async {
                      // Validate form
                      if (securityAnswerController.text.isEmpty ||
                          newPasswordController.text.isEmpty ||
                          confirmPasswordController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please fill in all fields'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      if (newPasswordController.text !=
                          confirmPasswordController.text) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Passwords do not match'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      if (newPasswordController.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Password must be at least 6 characters'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => loading = true);

                      try {
                        final auth = context.read<AuthService>();
                        await auth.resetAdminPassword(
                          securityAnswerController.text.trim(),
                          newPasswordController.text,
                        );

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Admin password reset successfully!'),
                                ],
                              ),
                              backgroundColor: Colors.green[600],
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          setDialogState(() => loading = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text('Error: ${e.toString()}'),
                                ],
                              ),
                              backgroundColor:
                                  Theme.of(context).colorScheme.error,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        }
                      }
                    },
              icon: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.lock_reset),
              label: Text(loading ? 'Resetting...' : 'Reset Password'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_form.currentState!.validate()) return;

    setState(() => _loading = true);

    final auth = context.read<AuthService>();
    final success = await auth.login(
      _usernameController.text.trim(),
      _passwordController.text,
      userType: _selectedRole, // Pass selected role to login
    );

    setState(() => _loading = false);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Invalid username or password'),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }
}
