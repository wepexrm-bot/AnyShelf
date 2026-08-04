import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/ui_mode_controller.dart';
import 'services/update_service.dart';
import 'theme/serene_theme.dart';
import 'theme/serene_tokens.dart';
import 'widgets/app_shell.dart';
import 'widgets/forced_update_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Wake the backend on launch (Render free tier sleeps after idle), so the
  // first real request doesn't wait out a slow cold start.
  _warmApi();
  runApp(const CloudReadApp());
}

Future<void> _warmApi() async {
  try {
    await ApiClient().get('/health');
  } catch (_) {
    // Best-effort warm-up; failures are expected on the first cold boot.
  }
}

class CloudReadApp extends StatefulWidget {
  const CloudReadApp({super.key});

  @override
  State<CloudReadApp> createState() => _CloudReadAppState();
}

class _CloudReadAppState extends State<CloudReadApp> {
  final _uiMode = UiModeController();
  final _navKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _uiMode.load();
    _checkForUpdate();
  }

  @override
  void dispose() {
    _uiMode.dispose();
    super.dispose();
  }

  /// Blocks the app when a newer build is published on GitHub so stale APKs
  /// can't keep running an old version.
  Future<void> _checkForUpdate() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final tag = await UpdateService.requiredUpdateTag();
    if (tag == null || !mounted) return;
    final nav = _navKey.currentState;
    if (nav == null) return;
    await showDialog<void>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => ForcedUpdateDialog(latestTag: tag),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _uiMode,
      child: ListenableBuilder(
        listenable: _uiMode,
        builder: (context, _) => MaterialApp(
          title: 'AnyShelf',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navKey,
          theme: sereneTheme(SereneColorScheme.day),
          darkTheme: sereneTheme(SereneColorScheme.night),
          themeMode: _uiMode.mode,
          home: const _AuthGate(),
        ),
      ),
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