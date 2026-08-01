import 'package:flutter/material.dart';

import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

/// Cloud sync status pill: a breathing accent dot + label, per the design's
/// "cozy" motion language (soft breathing, never a frantic spinner).
class SyncIndicator extends StatelessWidget {
  final String label;
  final bool active;
  const SyncIndicator({super.key, this.label = 'Synced', this.active = true});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BreathingDot(color: active ? colors.accentTeal : colors.outline),
        const SizedBox(width: 6),
        Text(
          label,
          style: SereneType.labelMd.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _BreathingDot extends StatefulWidget {
  final Color color;
  const _BreathingDot({required this.color});

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final opacity = 0.55 + (0.45 * t);
        final scale = 0.9 + (0.25 * t);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
