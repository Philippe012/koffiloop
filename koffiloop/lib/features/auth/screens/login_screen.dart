import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/core/theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLogin = true;
  String _role = 'customer';
  bool _obscure = true;
  bool _loading = false;

  @override void dispose() {
    _email.dispose(); _pass.dispose(); super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      if (_isLogin) {
        await auth.login(_email.text.trim(), _pass.text, context);
      } else {
        await auth.signup(_email.text.trim(), _pass.text, _role, context);
      }
      // Navigation handled in AuthService with mounted checks
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('FirebaseAuthException: ', '')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // Logo/Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.local_cafe, size: 48, color: AppTheme.primary),
                      SizedBox(height: 12),
                      Text('☕ KofiLoop', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      SizedBox(height: 4),
                      Text('Your neighborhood coffee, simplified', style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Email
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  validator: (v) => v == null || v.isEmpty || !v.contains('@') ? 'Enter valid email' : null,
                ),
                const SizedBox(height: 16),
                // Password
                TextFormField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _obscure = !_obscure)),
                  ),
                  validator: (v) => v == null || v.length < 6 ? 'Min 6 characters' : null,
                ),
                // Role selector (signup only)
                if (!_isLogin) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE0D6C9))),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _role, isExpanded: true,
                        items: const [
                          DropdownMenuItem(value: 'customer', child: Text('👤 Customer')),
                          DropdownMenuItem(value: 'seller', child: Text('🏪 Seller')),
                        ],
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Submit Button
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_isLogin ? 'Sign In' : 'Create Account'),
                ),
                const SizedBox(height: 16),
                // Toggle login/signup
                TextButton(
                  onPressed: () => setState(() { _isLogin = !_isLogin; _formKey.currentState?.reset(); }),
                  child: Text(_isLogin ? 'New here? Create account' : 'Already have an account? Sign in'),
                ),
                const SizedBox(height: 24),
                // Disclaimer
                Center(
                  child: Text('By continuing, you agree to our Terms', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary.withValues(alpha: 0.8))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}