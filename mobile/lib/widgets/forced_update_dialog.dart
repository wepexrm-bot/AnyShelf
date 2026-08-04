import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/serene_theme.dart';

/// Non-dismissible dialog shown when a newer version is published on GitHub.
/// The only way out is opening the release page to download the update.
class ForcedUpdateDialog extends StatelessWidget {
  const ForcedUpdateDialog({super.key, required this.latestTag});

  final String latestTag;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: Icon(Icons.system_update_alt, size: 40, color: colors.primary),
        title: const Text('Update required'),
        content: Text(
          'A newer version ($latestTag) of AnyShelf is available. '
          'Download it from GitHub to keep using the app.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            onPressed: UpdateService.openReleasesPage,
            icon: const Icon(Icons.download),
            label: const Text('Download update'),
          ),
        ],
      ),
    );
  }
}
