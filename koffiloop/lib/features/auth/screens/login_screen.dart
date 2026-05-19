import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'dart:io';
import 'dart:async';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  final _googleSignInPlugin = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: '680298750372-jg909kjei1a9jkm45drkoqv04obntdb2.apps.googleusercontent.com',
  );

  bool _isLogin = true;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _googleLoading = false;
  String _role = 'customer';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _formKey.currentState?.reset();
    });
    _slideCtrl.reset();
    _slideCtrl.forward();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      if (_isLogin) {
        await auth.login(_emailCtrl.text.trim(), _passCtrl.text, context);
      } else {
        await auth.signup(
        _emailCtrl.text.trim(), _passCtrl.text, _role, context,
        displayName: _nameCtrl.text.trim());
      }
    } catch (e) {
      if (mounted) {
        _showError(e
            .toString()
            .replaceAll('Exception: ', '')
            .replaceAll('FirebaseAuthException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
  setState(() => _googleLoading = true);

  try {
    final GoogleSignInAccount? googleUser =
        await _googleSignInPlugin.signIn();

    if (googleUser == null) {
      if (mounted) _showError('Sign-in cancelled');
      return;
    }

    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    if (googleAuth.accessToken == null ||
        googleAuth.idToken == null) {
      throw Exception('Missing authentication tokens');
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await FirebaseAuth.instance
        .signInWithCredential(credential);

    if (mounted && userCredential.user != null) {
      final authService = context.read<AuthService>();

      try {
        final result = await InternetAddress.lookup(
          'firestore.googleapis.com',
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('DNS lookup timed out'),
        );

        debugPrint('Firestore DNS: ${result[0].address}');
      } catch (e) {
        debugPrint('DNS check skipped: $e');
      }

      if (mounted) {
        await authService.handlePostLogin(context);
      }
      }
  } on FirebaseAuthException catch (e) {
    debugPrint(
      'FirebaseAuthException: ${e.code} - ${e.message}',
    );

    if (mounted) {
      String msg = e.message ?? 'Google sign-in failed';

      if (e.code ==
          'account-exists-with-different-credential') {
        msg =
            'This email is already registered with a different sign-in method.';
      }

      _showError(msg);
    }
  } on SocketException catch (e) {
    debugPrint('Network error: $e');

    if (mounted) {
      _showError(
        'Network error: Check your internet connection and try again.',
      );
    }
  } on TimeoutException catch (e) {
    debugPrint('Timeout: $e');

    if (mounted) {
      _showError(
        'Request timed out. Please check your connection and try again.',
      );
    }
  } catch (e, stack) {
    debugPrint('Unexpected error: $e\n$stack');

    if (mounted) {
      final msg = e.toString();
      final shortMsg = msg.length > 100
          ? '${msg.substring(0, 100)}...'
          : msg;

      _showError('Sign-in failed: $shortMsg');
    }
  } finally {
    if (mounted) {
      setState(() => _googleLoading = false);
    }
  }
}

  Future<void> _resetPassword() async {
    if (_emailCtrl.text.trim().isEmpty || !_emailCtrl.text.contains('@')) {
      _showError('Enter your email address first, then tap Reset Password.');
      return;
    }
    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailCtrl.text.trim());
      if (mounted) {
        _showSuccess(
            'Reset email sent to ${_emailCtrl.text.trim()}. Check your inbox.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _showError(e.message ?? 'Failed to send reset email.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppTheme.error,
    ));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: AppTheme.success,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [AppTheme.darkBackground, const Color(0xFF1E1208)]
                    : [AppTheme.background, const Color(0xFFF5EBE0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          // Top decorative arc
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
              ),
            ),
          ),
          Positioned(
            top: -40,
            right: -80,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.secondary
                    .withValues(alpha: isDark ? 0.15 : 0.1),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Back button
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Navigator.canPop(context)
                              ? IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: Icon(
                                    Icons.arrow_back_rounded,
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.textPrimary,
                                  ),
                                  padding: EdgeInsets.zero,
                                )
                              : const SizedBox(height: 40),
                        ),
                        const SizedBox(height: 8),
                        // Logo
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.primary,
                                  AppTheme.primaryDark
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/logo-white.png',
                              width: 48,
                              height: 48,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.local_cafe_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isLogin ? 'Welcome back' : 'Create account',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Georgia',
                            color: isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _isLogin
                              ? 'Sign in to order your favourite coffee'
                              : 'Join thousands of coffee lovers',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Google Sign In
                        _GoogleButton(
                          loading: _googleLoading,
                          isDark: isDark,
                          onTap: _googleSignIn,
                        ),
                        const SizedBox(height: 20),
                        _Divider(isDark: isDark),
                        const SizedBox(height: 20),

                        // Display name (signup only)
                        if (!_isLogin) ...[
                          _InputField(
                            controller: _nameCtrl,
                            hint: 'Full name',
                            icon: Icons.person_outline_rounded,
                            isDark: isDark,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter your name'
                                : null,
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Email
                        _InputField(
                          controller: _emailCtrl,
                          hint: 'Email address',
                          icon: Icons.email_outlined,
                          isDark: isDark,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) =>
                              v == null || !v.contains('@')
                                  ? 'Enter a valid email'
                                  : null,
                        ),
                        const SizedBox(height: 14),

                        // Password
                        _InputField(
                          controller: _passCtrl,
                          hint: 'Password',
                          icon: Icons.lock_outline_rounded,
                          isDark: isDark,
                          obscure: _obscurePass,
                          onToggleObscure: () =>
                              setState(() => _obscurePass = !_obscurePass),
                          validator: (v) => v == null || v.length < 6
                              ? 'Minimum 6 characters'
                              : null,
                        ),

                        // Confirm password (signup)
                        if (!_isLogin) ...[
                          const SizedBox(height: 14),
                          _InputField(
                            controller: _confirmPassCtrl,
                            hint: 'Confirm password',
                            icon: Icons.lock_outline_rounded,
                            isDark: isDark,
                            obscure: _obscureConfirm,
                            onToggleObscure: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                            validator: (v) => v != _passCtrl.text
                                ? 'Passwords do not match'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          // Role selector
                          _RoleSelector(
                            value: _role,
                            isDark: isDark,
                            onChanged: (v) => setState(() => _role = v),
                          ),
                        ],

                        // Forgot password (login only)
                        if (_isLogin) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _resetPassword,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'Forgot password?',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? AppTheme.secondary
                                      : AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Submit button
                        _SubmitButton(
                          label: _isLogin ? 'Sign In' : 'Create Account',
                          loading: _loading,
                          onTap: _submit,
                        ),
                        const SizedBox(height: 20),

                        // Toggle mode
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isLogin
                                  ? "Don't have an account? "
                                  : 'Already have an account? ',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            GestureDetector(
                              onTap: _toggleMode,
                              child: Text(
                                _isLogin ? 'Sign Up' : 'Sign In',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppTheme.secondary
                                      : AppTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            'By continuing you agree to our Terms of Service',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                      .withValues(alpha: 0.6)
                                  : AppTheme.textSecondary
                                      .withValues(alpha: 0.7),
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
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isDark;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isDark,
    this.obscure = false,
    this.onToggleObscure,
    this.validator,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: onToggleObscure,
              )
            : null,
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final bool isDark;
  final VoidCallback onTap;

  const _GoogleButton(
      {required this.loading, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? AppTheme.darkDivider : AppTheme.divider,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.primary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Real Google logo
                  Container(
                    width: 22,
                    height: 22,
                    padding: const EdgeInsets.all(2),
                    child: Image.asset(
                      'assets/images/google_logo.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.g_mobiledata_rounded,
                        color: Color(0xFF4285F4),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
              color: isDark ? AppTheme.darkDivider : AppTheme.divider),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Divider(
              color: isDark ? AppTheme.darkDivider : AppTheme.divider),
        ),
      ],
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final String value;
  final bool isDark;
  final ValueChanged<String> onChanged;

  const _RoleSelector(
      {required this.value, required this.isDark, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'I am a...',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _RoleOption(
              label: 'Customer',
              icon: Icons.person_rounded,
              selected: value == 'customer',
              isDark: isDark,
              onTap: () => onChanged('customer'),
            ),
            const SizedBox(width: 12),
            _RoleOption(
              label: 'Seller',
              icon: Icons.storefront_rounded,
              selected: value == 'seller',
              isDark: isDark,
              onTap: () => onChanged('seller'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _RoleOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary
                : (isDark ? AppTheme.darkCard : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : (isDark ? AppTheme.darkDivider : AppTheme.divider),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected
                    ? Colors.white
                    : (isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary),
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : (isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _SubmitButton(
      {required this.label, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: loading
                ? [Colors.grey.shade400, Colors.grey.shade400]
                : [AppTheme.primary, AppTheme.primaryDark],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: loading ? [] : AppTheme.buttonShadow,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
        ),
      ),
    );
  }
}