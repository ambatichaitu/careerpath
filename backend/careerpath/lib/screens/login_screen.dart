import 'package:flutter/material.dart';

import '../core/auth_config.dart';
import '../core/auth_gate.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final String? initialEmail;
  const LoginScreen({super.key, this.initialEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final AuthService _authService = AuthService();
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  // Login Controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  bool _obscureLoginPass = true;

  // Register Controllers
  final _regNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regConfirmPassCtrl = TextEditingController();
  bool _obscureRegPass = true;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialEmail != null) {
      _loginEmailCtrl.text = widget.initialEmail!;
      _regEmailCtrl.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    _regConfirmPassCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------
  // Strict Login Handler with Unregistered User Dialog Trigger
  // -------------------------------------------------------------
  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
    });

    final email = _loginEmailCtrl.text.trim();
    final password = _loginPassCtrl.text;

    try {
      // Authenticate directly with Firebase Authentication
      await _authService.loginWithEmail(email: email, password: password);
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      if (errorMsg.contains('No account found')) {
        _showAccountNotFoundDialog(email);
      } else {
        _showSnackBar(errorMsg, isError: true);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      await _authService.signInWithGoogle();
      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }


  void _showForgotPasswordDialog() {
    final resetEmailCtrl = TextEditingController(text: _loginEmailCtrl.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.lock_reset_rounded, color: AppTheme.primaryIndigo),
            const SizedBox(width: 10),
            Text('Reset Password', style: AppTheme.fontHeading(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your registered email address. We will send a secure password reset link directly to your inbox:',
              style: AppTheme.fontBody(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryIndigo),
            onPressed: () async {
              final email = resetEmailCtrl.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                _showSnackBar('Please enter a valid email address.', isError: true);
                return;
              }
              Navigator.pop(ctx);
              try {
                await _authService.sendPasswordResetEmail(email: email);
                _showSnackBar('Password reset link sent! Please check your email inbox and spam folder.');
              } catch (e) {
                _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
              }
            },
            child: const Text('Send Reset Link'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------
  // Account Not Found Strict Dialog
  // -------------------------------------------------------------
  void _showAccountNotFoundDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accentRose.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_off_rounded,
                  color: AppTheme.accentRose,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Account Not Found',
                  style: AppTheme.fontHeading(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The email address:',
                style: AppTheme.fontBody(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        email,
                        style: AppTheme.fontBody(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppTheme.primaryIndigo,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'is not registered in our student database. You must create a new account before you can access CareerPath.',
                style: AppTheme.fontBody(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.borderLight),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Create a new login'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                // Redirect user to the Registration tab with prefilled email
                _regEmailCtrl.text = email;
                _tabController.animateTo(1);
              },
            ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------
  // Register Handler
  // -------------------------------------------------------------
  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;
    if (_regPassCtrl.text != _regConfirmPassCtrl.text) {
      _showSnackBar('Passwords do not match. Please re-enter.', isError: true);
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // Register with Firebase Authentication and trigger verification email
      await _authService.registerWithEmail(
        email: _regEmailCtrl.text.trim(),
        password: _regPassCtrl.text,
      );

      if (!mounted) return;
      setState(() => _loading = false);
      if (AuthConfig.isEmailVerificationRequired) {
        _showSnackBar('Account created! A verification link has been sent to your email.');
      } else {
        _showSnackBar('Account created! Proceeding to academic onboarding.');
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.accentRose : AppTheme.secondaryTeal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF1F5F9), Color(0xFFE2E8F0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isWide ? 36 : 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header Badge & Logo
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          shape: BoxShape.circle,
                          boxShadow: AppTheme.glowShadow,
                        ),
                        child: const Icon(Icons.explore_rounded, size: 40, color: Colors.white),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'CareerPath',
                        style: AppTheme.fontHeading(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'AI-Powered Student Career Roadmap & Intelligence',
                        textAlign: TextAlign.center,
                        style: AppTheme.fontBody(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tab Switcher (Login / Register)
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderLight),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          indicator: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          labelColor: AppTheme.primaryIndigo,
                          labelStyle: AppTheme.fontBody(fontWeight: FontWeight.w700, fontSize: 14),
                          unselectedLabelColor: AppTheme.textSecondary,
                          unselectedLabelStyle: AppTheme.fontBody(fontWeight: FontWeight.w500, fontSize: 14),
                          tabs: const [
                            Tab(text: 'Sign In'),
                            Tab(text: 'Create Account'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Tab Views
                      AnimatedSize(
                        duration: const Duration(milliseconds: 300),
                        child: SizedBox(
                          height: 480,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildLoginForm(),
                              _buildRegisterForm(),
                            ],
                          ),
                        ),
                      ),

                      // Demo User Credential Helper Box
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, size: 20, color: AppTheme.primaryIndigo),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Demo Login: student@careerpath.edu',
                                    style: AppTheme.fontBody(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryIndigo,
                                    ),
                                  ),
                                  Text(
                                    'Password: password123 (Or enter any new email to test the strict register dialog)',
                                    style: AppTheme.fontBody(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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

  // -------------------------------------------------------------
  // Sign In Form
  // -------------------------------------------------------------
  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _loginEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Student Email Address',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
              hintText: 'alex@college.edu',
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Please enter your email.';
              if (!val.contains('@')) return 'Enter a valid email.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPassCtrl,
            obscureText: _obscureLoginPass,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscureLoginPass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureLoginPass = !_obscureLoginPass),
              ),
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'Please enter your password.';
              return null;
            },
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _showForgotPasswordDialog,
              child: Text(
                'Forgot Password?',
                style: AppTheme.fontBody(fontSize: 13, color: AppTheme.primaryIndigo, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _handleLogin,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryIndigo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Sign In & Open Roadmap', style: AppTheme.fontBody(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          _buildGoogleSignInButton(label: 'Continue with Google'),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => _tabController.animateTo(1),
              child: Text(
                'Don\'t have an account? Create one now',
                style: AppTheme.fontBody(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryIndigo),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // -------------------------------------------------------------
  // Registration Form
  // -------------------------------------------------------------
  Widget _buildRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: ListView(
        children: [
          TextFormField(
            controller: _regNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline, size: 20),
              hintText: 'Alex Chen',
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter your name.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regEmailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'College / Personal Email',
              prefixIcon: Icon(Icons.email_outlined, size: 20),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Enter email.';
              if (!val.contains('@')) return 'Enter valid email.';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regPassCtrl,
            obscureText: _obscureRegPass,
            decoration: InputDecoration(
              labelText: 'Create Password',
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                icon: Icon(_obscureRegPass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscureRegPass = !_obscureRegPass),
              ),
            ),
            validator: (val) => (val == null || val.length < 4) ? 'At least 4 characters.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _regConfirmPassCtrl,
            obscureText: _obscureRegPass,
            decoration: const InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
            ),
            validator: (val) => (val == null || val.isEmpty) ? 'Confirm password.' : null,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _handleRegister,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.secondaryTeal,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Create Account & Get Started', style: AppTheme.fontBody(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(width: 8),
                          const Icon(Icons.check_circle_outline, size: 18),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          _buildGoogleSignInButton(label: 'Sign up with Google'),
        ],
      ),
    );
  }

  Widget _buildGoogleSignInButton({required String label}) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(child: Divider(color: AppTheme.borderLight)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'or',
                style: AppTheme.fontBody(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
            const Expanded(child: Divider(color: AppTheme.borderLight)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _loading ? null : _handleGoogleSignIn,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.borderLight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              backgroundColor: Colors.white,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  child: const Text(
                    'G',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: AppTheme.fontBody(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
