import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/ui_mode_controller.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import 'auth_screen.dart';

/// Settings: appearance (light/dark), account details, change password and
/// sign out — mirroring the web Settings page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  String _displayName = 'Reader';
  String _email = '';
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final me = await _auth.me();
      if (!mounted) return;
      setState(() {
        _displayName = (me['display_name'] as String?)?.trim().isNotEmpty == true
            ? me['display_name'] as String
            : (me['email'] as String? ?? 'Reader');
        _email = me['email'] as String? ?? '';
        _verified = me['is_verified'] == true;
      });
    } catch (_) {}
  }

  Future<void> _signOut() async {
    await _auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _changePassword() async {
    final oldCtl = TextEditingController();
    final newCtl = TextEditingController();
    final confirmCtl = TextEditingController();
    String? error;
    final errorColor =
        Theme.of(context).extension<SereneTheme>()!.colors.error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldCtl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: SereneType.labelSm.copyWith(color: errorColor)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final newPassword = newCtl.text;
                if (newPassword.length < 8) {
                  setDialogState(() => error = 'New password must be at least 8 characters.');
                  return;
                }
                if (newPassword != confirmCtl.text) {
                  setDialogState(() => error = 'New passwords do not match.');
                  return;
                }
                try {
                  await _auth.api.post('/auth/change-password', body: {
                    'old_password': oldCtl.text,
                    'new_password': newPassword,
                  });
                  if (context.mounted) Navigator.pop(context, true);
                } on ApiException catch (e) {
                  setDialogState(() => error = e.message);
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password changed successfully.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials = _displayName.isNotEmpty
        ? _displayName.split(' ').take(2).map((s) => s[0]).join().toUpperCase()
        : 'R';

    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
              children: [
                _ProfileHeader(
                    initials: initials, name: _displayName, email: _email),
                const SizedBox(height: 24),
                const _AppearanceCard(),
                const SizedBox(height: 24),
                _AccountCard(
                  email: _email,
                  verified: _verified,
                  onChangePassword: _changePassword,
                  onSignOut: _signOut,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionHeader({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: SereneType.labelSm.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.12,
          ),
        ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final String initials;
  final String name;
  final String email;
  const _ProfileHeader({
    required this.initials,
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: colors.surfaceContainerHighest,
          child: Text(initials, style: SereneType.title.copyWith(color: colors.onSurface)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: SereneType.headlineMobile.copyWith(color: colors.onSurface)),
              const SizedBox(height: 2),
              Text(email,
                  style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final uiMode = context.watch<UiModeController>();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.all(SereneShape.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.dark_mode_outlined, text: 'Appearance'),
          const SizedBox(height: 8),
          Text('Choose between light and dark mode for the app interface.',
              style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('App theme',
                    style: SereneType.uiBody.copyWith(color: colors.onSurface)),
              ),
              Switch(
                value: uiMode.isDark,
                onChanged: (_) => uiMode.toggle(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final String email;
  final bool verified;
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;
  const _AccountCard({
    required this.email,
    required this.verified,
    required this.onChangePassword,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.all(SereneShape.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.person, text: 'Account'),
          const SizedBox(height: 16),
          _ReadOnlyField(label: 'Email', value: email),
          const SizedBox(height: 12),
          if (!verified) ...[
            Text('Your email is not verified yet.',
                style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
          ],
          const Divider(height: 24),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.lock_outline, color: colors.onSurfaceVariant),
            title: Text('Change Password',
                style: SereneType.uiBody.copyWith(color: colors.onSurface)),
            trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            onTap: onChangePassword,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.logout, color: colors.error),
            title: Text('Sign Out',
                style: SereneType.uiBody.copyWith(color: colors.error)),
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value, style: SereneType.uiBody.copyWith(color: colors.onSurface)),
      ],
    );
  }
}
