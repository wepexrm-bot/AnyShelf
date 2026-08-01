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
                  Icon(Icons.cloud_done, color: colors.accentTeal, size: 44),
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
