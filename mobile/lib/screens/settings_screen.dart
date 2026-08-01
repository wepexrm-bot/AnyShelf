import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../theme/reader_atmosphere.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';
import 'auth_screen.dart';

/// Account & Storage: profile, cloud storage meter, active devices, general
/// reading preferences, and account actions.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = AuthService();
  final _settings = SettingsService();
  bool _notifications = true;
  String _displayName = 'Reader';
  String _email = '';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );
    if (confirmed != true || newCtl.text.isEmpty) return;
    try {
      await _auth.api.post('/auth/change-password',
          body: {
            'old_password': oldCtl.text,
            'new_password': newCtl.text,
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password updated.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
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
                _ProfileHeader(initials: initials, name: _displayName, email: _email),
                const SizedBox(height: 24),
                _StorageCard(),
                const SizedBox(height: 24),
                const _DevicesCard(),
                const SizedBox(height: 24),
                _GeneralCard(
                  notifications: _notifications,
                  onNotificationsChanged: (v) => setState(() => _notifications = v),
                  onThemeQuick: (a) => _settings.save(ReaderSettings.defaults().copyWith(atmosphere: a)),
                ),
                const SizedBox(height: 24),
                _AccountCard(
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

class _StorageCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: SereneShape.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.cloud, text: 'Cloud Storage'),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('1.2 GB used',
                  style: SereneType.uiBody.copyWith(color: colors.onSurface)),
              const Spacer(),
              Text('5 GB total',
                  style: SereneType.uiBody.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: SereneShape.fullPill,
            child: Container(
              height: 8,
              color: colors.surfaceVariant,
              child: const FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.24,
                child: ColoredBox(color: Color(0xFF003633)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {},
            child: const Text('Manage Storage'),
          ),
        ],
      ),
    );
  }
}

class _DevicesCard extends StatelessWidget {
  const _DevicesCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: SereneShape.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.devices, text: 'Active Devices'),
          const SizedBox(height: 16),
          _DeviceRow(
            icon: Icons.smartphone,
            name: 'This Device',
            detail: 'Active now',
            revoke: false,
          ),
          const Divider(height: 24),
          const _DeviceRow(
            icon: Icons.tablet_mac,
            name: 'Tablet',
            detail: 'Last active 2 days ago',
            revoke: true,
          ),
          const Divider(height: 24),
          const _DeviceRow(
            icon: Icons.laptop_mac,
            name: 'Web Browser',
            detail: 'Last active 1 week ago',
            revoke: true,
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String detail;
  final bool revoke;
  const _DeviceRow({
    required this.icon,
    required this.name,
    required this.detail,
    this.revoke = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Row(
      children: [
        Icon(icon, color: colors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: SereneType.uiBody.copyWith(color: colors.onSurface)),
              Text(detail,
                  style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
        if (revoke)
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(foregroundColor: colors.error),
            child: const Text('Revoke'),
          ),
      ],
    );
  }
}

class _GeneralCard extends StatelessWidget {
  final bool notifications;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<ReadingAtmosphere> onThemeQuick;
  const _GeneralCard({
    required this.notifications,
    required this.onNotificationsChanged,
    required this.onThemeQuick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: SereneShape.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.tune, text: 'General Settings'),
          const SizedBox(height: 20),
          Text('Reading Theme',
              style: SereneType.uiBody.copyWith(color: colors.onSurface)),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final a in [ReadingAtmosphere.day, ReadingAtmosphere.night, ReadingAtmosphere.sepia])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: OutlinedButton(
                      onPressed: () => onThemeQuick(a),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: a.background,
                        foregroundColor: a.text,
                        side: BorderSide(color: colors.outlineVariant),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(a.label, style: SereneType.labelMd),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 20),
          Text('Default Font Size',
              style: SereneType.uiBody.copyWith(color: colors.onSurface)),
          const Slider(min: 1, max: 5, value: 3, onChanged: null),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Small', style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
              Text('Default', style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
              Text('Large', style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Push Notifications',
                        style: SereneType.uiBody.copyWith(color: colors.onSurface)),
                    Text('Sync alerts and reading reminders',
                        style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(
                value: notifications,
                onChanged: onNotificationsChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final VoidCallback onChangePassword;
  final VoidCallback onSignOut;
  const _AccountCard({required this.onChangePassword, required this.onSignOut});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: SereneShape.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(icon: Icons.person, text: 'Account'),
          const SizedBox(height: 8),
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
