import 'package:flutter/material.dart';

import 'screens/auth_screen.dart';
import 'services/auth_service.dart';
import 'theme/serene_theme.dart';
import 'theme/serene_tokens.dart';
import 'widgets/app_shell.dart';

void main() {
  runApp(const CloudReadApp());
}

class CloudReadApp extends StatelessWidget {
  const CloudReadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnyShelf',
      debugShowCheckedModeBanner: false,
      theme: sereneTheme(SereneColorScheme.day),
      darkTheme: sereneTheme(SereneColorScheme.night),
      themeMode: ThemeMode.light,
      home: const _AuthGate(),
    );
  }
}

/// Routes to the library when a session exists, otherwise the sign-in screen.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _auth = AuthService();
  bool _checked = false;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final has = await _auth.hasSession();
    if (!mounted) return;
    setState(() {
      _hasSession = has;
      _checked = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _hasSession ? const AppShell() : const AuthScreen();
  }
}
