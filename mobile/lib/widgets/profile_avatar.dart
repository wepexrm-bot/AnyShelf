import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

/// Circular avatar showing the signed-in user's initials. Used as the header
/// trailing widget in place of the cloud sync status pill.
class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({super.key});

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  static String? _cachedInitials;
  String _initials = 'R';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = _cachedInitials;
    if (cached != null) {
      if (mounted) setState(() => _initials = cached);
      return;
    }
    String initials = 'R';
    try {
      final name = await AuthService().getDisplayName();
      final trimmed = name?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        initials =
            trimmed.split(' ').take(2).map((s) => s[0]).join().toUpperCase();
      }
      _cachedInitials = initials;
    } catch (_) {}
    if (mounted) setState(() => _initials = initials);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: SereneType.labelSm.copyWith(
          color: colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
