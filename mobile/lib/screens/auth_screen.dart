import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_shell.dart';

/// Sign in / create account gate before the library.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = AuthService();
  final _emailCtl = TextEditingController();
  final _passwordCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _obscure = true;

  Future<void> _submit() async {
    final email = _emailCtl.text.trim();
    final password = _passwordCtl.text;
    if (email.isEmpty || password.isEmpty) {
      _toast('Please enter your email and password');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_signup) {
        await _auth.register(
          email: email,
          password: password,
          displayName: _nameCtl.text.trim(),
        );
        final ok = await _verifyEmailFlow(email);
        if (!ok) {
          if (!mounted) return;
          setState(() => _busy = false);
          return;
        }
        await _auth.login(email, password);
      } else {
        await _auth.login(email, password);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _verifyEmailFlow(String email) async {
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerifyEmailDialog(email: email, auth: _auth),
    );
    return verified ?? false;
  }

  Future<void> _forgotPasswordFlow() async {
    final emailCtl = TextEditingController(text: _emailCtl.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Forgot password'),
        content: TextField(
          controller: emailCtl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send verification code'),
          ),
        ],
      ),
    );
    if (sent != true) return;
    try {
      await _auth.forgotPassword(emailCtl.text.trim());
      _toast('If that email exists, a verification code was sent.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
    if (!mounted) return;
    await _resetPasswordFlow(emailCtl.text.trim());
  }

  Future<void> _resetPasswordFlow(String email) async {
    final tokenCtl = TextEditingController();
    final passCtl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tokenCtl,
              decoration: const InputDecoration(
                  labelText: '6-digit verification code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _auth.resetPassword(
        email: email,
        token: tokenCtl.text.trim(),
        password: passCtl.text,
      );
      _toast('Password reset. You can sign in now.');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _emailCtl.dispose();
    _passwordCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset('assets/images/logo.png', width: 44, height: 44),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AnyShelf',
                    textAlign: TextAlign.center,
                    style: SereneType.headlineLg.copyWith(
                      color: colors.accentTeal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Upload once, read anywhere.\nMake every book feel like yours.',
                    textAlign: TextAlign.center,
                    style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _signup ? 'Create your account' : 'Welcome back',
                    style: SereneType.headlineMobile.copyWith(color: colors.onSurface),
                  ),
                  const SizedBox(height: 20),
                  if (_signup) ...[
                    TextField(
                      controller: _nameCtl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _emailCtl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordCtl,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text(_signup ? 'Create account' : 'Sign in'),
                  ),
                  const SizedBox(height: 16),
                  if (!_signup)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPasswordFlow,
                        child: const Text('Forgot password?'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _signup ? 'Already have an account?' : 'New to AnyShelf?',
                        style:
                            SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _signup = !_signup),
                        child: Text(_signup ? 'Sign in' : 'Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifyEmailDialog extends StatefulWidget {
  final String email;
  final AuthService auth;
  const _VerifyEmailDialog({required this.email, required this.auth});

  @override
  State<_VerifyEmailDialog> createState() => _VerifyEmailDialogState();
}

class _VerifyEmailDialogState extends State<_VerifyEmailDialog> {
  final _codeCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.verifyEmail(widget.email, _codeCtl.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Verification failed. Check your connection and try again.';
      });
    }
  }

  Future<void> _resend() async {
    if (_busy) return;
    try {
      await widget.auth.resendVerification(widget.email);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Verification code sent.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resend. Check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return AlertDialog(
      title: const Text('Verify your email'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter the 6-digit code sent to ${widget.email}.',
            style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _codeCtl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            onSubmitted: (_) => _verify(),
            decoration: const InputDecoration(labelText: 'Code'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                style: SereneType.labelSm.copyWith(color: colors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _resend,
          child: const Text('Resend code'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify'),
        ),
      ],
    );
  }
}
