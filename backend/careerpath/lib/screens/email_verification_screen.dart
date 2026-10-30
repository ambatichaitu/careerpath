import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class EmailVerificationScreen extends StatefulWidget {
  final VoidCallback onVerified;

  const EmailVerificationScreen({super.key, required this.onVerified});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _codeController = TextEditingController();
  bool _checking = false;
  bool _canResend = true;
  int _resendCooldown = 0;
  bool _showCodeInput = false;
  bool _applyingCode = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 1) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
        setState(() => _canResend = true);
      }
    });
  }

  Future<void> _checkVerification() async {
    setState(() => _checking = true);
    final user = await _authService.reloadCurrentUser();
    setState(() => _checking = false);

    // Strictly enforce genuine Firebase email verification
    if (user != null && user.emailVerified) {
      widget.onVerified();
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email not verified yet. Please click the link sent to your inbox.'),
          backgroundColor: AppTheme.accentAmber,
        ),
      );
    }
  }

  Future<void> _applyManualCode() async {
    final text = _codeController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the verification code or link.'),
          backgroundColor: AppTheme.accentAmber,
        ),
      );
      return;
    }

    setState(() => _applyingCode = true);
    try {
      final verified = await _authService.verifyEmailWithCode(text);
      if (verified) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified successfully!'),
            backgroundColor: AppTheme.secondaryTeal,
          ),
        );
        widget.onVerified();
      } else {
        final reloaded = await _authService.reloadCurrentUser();
        if (reloaded?.emailVerified == true) {
          widget.onVerified();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Verification code applied, but account status is pending. Please click "I\'ve Verified My Email".'),
              backgroundColor: AppTheme.accentAmber,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppTheme.accentRose,
        ),
      );
    } finally {
      if (mounted) setState(() => _applyingCode = false);
    }
  }

  bool _sendingResend = false;
  String? _resendStatusMessage;
  bool _resendHasError = false;

  Future<void> _resendEmail() async {
    if (!_canResend || _sendingResend) return;
    setState(() {
      _sendingResend = true;
      _resendStatusMessage = null;
      _resendHasError = false;
    });

    try {
      await _authService.sendVerificationEmail();
      _startCooldown();
      final now = TimeOfDay.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final successMsg = 'Firebase accepted verification dispatch ($timeStr). Please check your Inbox and Spam folder.';
      if (!mounted) return;
      setState(() {
        _resendStatusMessage = successMsg;
        _resendHasError = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMsg),
          backgroundColor: AppTheme.secondaryTeal,
        ),
      );
    } catch (e) {
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      if (!mounted) return;
      setState(() {
        _resendStatusMessage = errorMsg;
        _resendHasError = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg), backgroundColor: AppTheme.accentRose),
      );
    } finally {
      if (mounted) setState(() => _sendingResend = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _authService.currentUser?.email ?? 'your email';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Verification'),
        actions: [
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => _authService.logout(),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: const BorderSide(color: AppTheme.borderLight, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryIndigo.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mark_email_unread_rounded, size: 54, color: AppTheme.primaryIndigo),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Verify Your Email',
                      style: AppTheme.fontHeading(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'We have sent a verification link to:\n$email',
                      textAlign: TextAlign.center,
                      style: AppTheme.fontBody(fontSize: 14, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        icon: _checking
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_outline_rounded),
                        label: Text(_checking ? 'Checking...' : "I've Verified My Email"),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryIndigo,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _checking ? null : _checkVerification,
                      ),
                    ),
                    if (_resendStatusMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _resendHasError
                              ? AppTheme.accentRose.withValues(alpha: 0.1)
                              : AppTheme.secondaryTeal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _resendHasError
                                ? AppTheme.accentRose.withValues(alpha: 0.3)
                                : AppTheme.secondaryTeal.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _resendHasError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                              size: 18,
                              color: _resendHasError ? AppTheme.accentRose : AppTheme.secondaryTeal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _resendStatusMessage!,
                                style: AppTheme.fontBody(
                                  fontSize: 12,
                                  color: _resendHasError ? AppTheme.accentRose : AppTheme.secondaryTeal,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: (_canResend && !_sendingResend) ? _resendEmail : null,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _sendingResend
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _canResend ? 'Resend Verification Email' : 'Resend in ${_resendCooldown}s',
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Manual Verification Link or Code Resolver
                    InkWell(
                      onTap: () => setState(() => _showCodeInput = !_showCodeInput),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _showCodeInput ? Icons.keyboard_arrow_up_rounded : Icons.link_rounded,
                              size: 18,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _showCodeInput ? 'Hide Code Input' : 'Trouble with link? Enter code',
                                textAlign: TextAlign.center,
                                style: AppTheme.fontBody(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showCodeInput) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          hintText: 'Paste full verification URL or code',
                          hintStyle: AppTheme.fontBody(fontSize: 12, color: AppTheme.textMuted),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.vpn_key_outlined, size: 18),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 40,
                        child: FilledButton(
                          onPressed: _applyingCode ? null : _applyManualCode,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.secondaryTeal,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _applyingCode
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Verify Code Directly', style: TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => _authService.logout(),
                      child: const Text('Sign In with a Different Account'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
