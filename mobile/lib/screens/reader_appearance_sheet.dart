import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../theme/reader_atmosphere.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

/// The "Appearance" bottom sheet: theme atmospheres, typography, and layout
/// mode. Every change is streamed out via [onChanged] so the reader behind it
/// updates live.
class ReaderAppearanceSheet extends StatefulWidget {
  final ReaderSettings initial;
  final bool reflowAvailable;
  final ValueChanged<ReaderSettings> onChanged;
  const ReaderAppearanceSheet({
    super.key,
    required this.initial,
    required this.reflowAvailable,
    required this.onChanged,
  });

  @override
  State<ReaderAppearanceSheet> createState() => _ReaderAppearanceSheetState();
}

class _ReaderAppearanceSheetState extends State<ReaderAppearanceSheet> {
  late ReaderSettings _settings = widget.initial;

  void _update(ReaderSettings next) {
    setState(() => _settings = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Column(
        children: [
          _SheetHeader(onClose: () => Navigator.pop(context)),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                _ThemeSection(
                  selected: _settings.atmosphere,
                  onSelect: (a) => _update(_settings.copyWith(atmosphere: a)),
                ),
                const SizedBox(height: 32),
                _TypographySection(
                  settings: _settings,
                  onChanged: _update,
                ),
                const SizedBox(height: 32),
                _LayoutSection(
                  mode: _settings.mode,
                  reflowAvailable: widget.reflowAvailable,
                  onSelect: (m) => _update(_settings.copyWith(mode: m)),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _SheetHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.surfaceVariant)),
      ),
      child: Row(
        children: [
          Text(
            'Appearance',
            style: SereneType.headlineMobile.copyWith(color: colors.onSurface),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close),
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text.toUpperCase(),
        style: SereneType.labelMd.copyWith(
          color: colors.onSurfaceVariant,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class _ThemeSection extends StatelessWidget {
  final ReadingAtmosphere selected;
  final ValueChanged<ReadingAtmosphere> onSelect;
  const _ThemeSection({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Theme'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ReadingAtmosphere.all.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemBuilder: (context, i) {
            final a = ReadingAtmosphere.all[i];
            return _ThemeTile(
              atmosphere: a,
              active: a.id == selected.id,
              onTap: () => onSelect(a),
            );
          },
        ),
      ],
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final ReadingAtmosphere atmosphere;
  final bool active;
  final VoidCallback onTap;
  const _ThemeTile({
    required this.atmosphere,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: atmosphere.background,
                borderRadius: BorderRadius.all(SereneShape.md),
                border: Border.all(
                  color: active ? colors.primary : colors.outlineVariant,
                  width: active ? 2 : 1,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.15),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              child: Icon(atmosphere.icon, color: atmosphere.text),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            atmosphere.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SereneType.labelSm.copyWith(
              color: active ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypographySection extends StatelessWidget {
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  const _TypographySection({required this.settings, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Typography'),
        _FontPicker(
          selected: settings.font,
          onSelect: (f) => onChanged(settings.copyWith(font: f)),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.text_fields, size: 18, color: colors.onSurfaceVariant),
            Expanded(
              child: Slider(
                value: settings.fontSize,
                min: 14,
                max: 32,
                onChanged: (v) => onChanged(settings.copyWith(fontSize: v)),
              ),
            ),
            Icon(Icons.text_fields, size: 30, color: colors.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _MiniPanel(
                label: 'Line Height',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final lh in LineHeightLevel.values)
                      _IconStep(
                        active: settings.lineHeight == lh,
                        icon: Icons.format_line_spacing,
                        size: 16.0 + (lh.index * 6),
                        onTap: () => onChanged(settings.copyWith(lineHeight: lh)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _MiniPanel(
                label: 'Margins',
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _IconStep(
                      active: settings.margins == MarginLevel.small,
                      icon: Icons.splitscreen,
                      size: 18,
                      onTap: () => onChanged(settings.copyWith(margins: MarginLevel.small)),
                    ),
                    _IconStep(
                      active: settings.margins == MarginLevel.medium,
                      icon: Icons.horizontal_distribute,
                      size: 18,
                      onTap: () => onChanged(settings.copyWith(margins: MarginLevel.medium)),
                    ),
                    _IconStep(
                      active: settings.margins == MarginLevel.large,
                      icon: Icons.width_normal,
                      size: 18,
                      onTap: () => onChanged(settings.copyWith(margins: MarginLevel.large)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FontPicker extends StatelessWidget {
  final ReaderFont selected;
  final ValueChanged<ReaderFont> onSelect;
  const _FontPicker({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in ReaderFont.values)
          GestureDetector(
            onTap: () => onSelect(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: f == selected
                    ? colors.surface
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.all(SereneShape.full),
                border: Border.all(
                  color: f == selected ? colors.primary : colors.outlineVariant,
                  width: f == selected ? 2 : 1,
                ),
                boxShadow: f == selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
              child: Text(
                f.label,
                style: SereneType.labelMd.copyWith(
                  fontFamily: f.googleFamily,
                  color: f == selected
                      ? colors.primary
                      : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniPanel extends StatelessWidget {
  final String label;
  final Widget child;
  const _MiniPanel({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.all(SereneShape.xl),
        border: Border.all(color: colors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _IconStep extends StatelessWidget {
  final bool active;
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _IconStep({
    required this.active,
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: active ? colors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.all(SereneShape.sm),
        ),
        child: Icon(
          icon,
          size: size,
          color: active ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LayoutSection extends StatelessWidget {
  final ReaderMode mode;
  final bool reflowAvailable;
  final ValueChanged<ReaderMode> onSelect;
  const _LayoutSection({
    required this.mode,
    required this.reflowAvailable,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Layout'),
        Row(
          children: [
            Expanded(
              child: _LayoutButton(
                active: mode == ReaderMode.scroll,
                icon: Icons.swipe_down,
                label: 'Scroll',
                onTap: () => onSelect(ReaderMode.scroll),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LayoutButton(
                active: mode == ReaderMode.paginated,
                icon: Icons.import_contacts,
                label: 'Paginated',
                enabled: reflowAvailable,
                onTap: () => onSelect(ReaderMode.paginated),
              ),
            ),
          ],
        ),
        if (!reflowAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Paginated layout needs reflow mode, which isn\'t available for this book.',
              style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _LayoutButton extends StatelessWidget {
  final bool active;
  final bool enabled;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LayoutButton({
    required this.active,
    required this.icon,
    required this.label,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final color = !enabled
        ? colors.onSurfaceVariant.withValues(alpha: 0.4)
        : active
            ? colors.primary
            : colors.onSurfaceVariant;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: active ? colors.surface : colors.surfaceContainerLow,
          borderRadius: BorderRadius.all(SereneShape.xl),
          border: Border.all(
            color: active ? colors.primary : colors.surfaceVariant,
            width: active ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: SereneType.uiBody.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
