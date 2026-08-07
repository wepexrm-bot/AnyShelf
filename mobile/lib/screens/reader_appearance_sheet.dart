import 'package:flutter/material.dart';

import '../models/reader_settings.dart';
import '../theme/reader_atmosphere.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';

/// The "Appearance" bottom sheet: theme atmospheres, typography, and layout
/// mode. Matches the AnyShelf "reader appearance" design — a rounded sheet that
/// rises over the reader (which stays visible and dimmed behind it). Every
/// change is streamed out via [onChanged] so the reader behind updates live.
class ReaderAppearanceSheet extends StatefulWidget {
  final ReaderSettings initial;
  final ValueChanged<ReaderSettings> onChanged;
  const ReaderAppearanceSheet({
    super.key,
    required this.initial,
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
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: SereneShape.sheetTop,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 40,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _SheetHeader(onClose: () => Navigator.pop(context)),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                _ThemeSection(
                  selected: _settings.atmosphere,
                  onSelect: (a) =>
                      _update(_settings.copyWith(atmosphere: a)),
                ),
                const SizedBox(height: 28),
                _TypographySection(
                  settings: _settings,
                  onChanged: _update,
                ),
                const SizedBox(height: 28),
                _LayoutSection(
                  settings: _settings,
                  onChanged: _update,
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
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
          letterSpacing: 0.05,
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
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 14,
            childAspectRatio: 0.8,
          ),
          itemBuilder: (context, i) {
            final a = ReadingAtmosphere.all[i];
            return _ThemeCard(
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

class _ThemeCard extends StatelessWidget {
  final ReadingAtmosphere atmosphere;
  final bool active;
  final VoidCallback onTap;
  const _ThemeCard({
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
                          color: colors.primary.withValues(alpha: 0.12),
                          blurRadius: 6,
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
              color: active ? colors.primary : colors.onSurfaceVariant,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Typography'),
        _FontPicker(
          selected: settings.font,
          onSelect: (f) => onChanged(settings.copyWith(font: f)),
        ),
        const SizedBox(height: 20),
        _MiniPanel(
          child: Row(
            children: [
              Icon(Icons.text_fields,
                  size: 18, color: _muted(context)),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 14,
                  max: 32,
                  activeColor: _primary(context),
                  onChanged: (v) =>
                      onChanged(settings.copyWith(fontSize: v)),
                ),
              ),
              Icon(Icons.text_fields, size: 28, color: _muted(context)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            'Page Zoom  ${(settings.pageZoom * 100).round()}%',
            style: SereneType.labelSm.copyWith(
              color: _muted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
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
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: f == selected
                    ? colors.surface
                    : colors.surfaceContainerLow,
                borderRadius: BorderRadius.all(SereneShape.md),
                border: Border.all(
                  color: f == selected ? colors.primary : colors.outlineVariant,
                  width: f == selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                f.label,
                style: SereneType.labelMd.copyWith(
                  fontFamily: f.googleFamily,
                  color: f == selected
                      ? colors.primary
                      : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniPanel extends StatelessWidget {
  final Widget child;
  const _MiniPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.all(SereneShape.xl),
        border: Border.all(color: colors.surfaceVariant),
      ),
      child: child,
    );
  }
}

class _LayoutSection extends StatelessWidget {
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  const _LayoutSection({
    required this.settings,
    required this.onChanged,
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
                active: settings.mode == ReaderMode.scroll,
                icon: Icons.swipe_down,
                label: 'Scroll',
                onTap: () => onChanged(settings.copyWith(mode: ReaderMode.scroll)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LayoutButton(
                active: settings.mode == ReaderMode.singlePage,
                icon: Icons.import_contacts,
                label: 'Single page',
                onTap: () =>
                    onChanged(settings.copyWith(mode: ReaderMode.singlePage)),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Scroll flows every page edge-to-edge continuously. Single page '
            'shows one full page at a time — swipe left/right to turn, '
            'double-tap to zoom, pinch to pan.',
            style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _LayoutButton extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LayoutButton({
    required this.active,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final color = active ? colors.primary : colors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16),
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

Color _muted(BuildContext context) =>
    Theme.of(context).extension<SereneTheme>()!.colors.onSurfaceVariant;

Color _primary(BuildContext context) =>
    Theme.of(context).extension<SereneTheme>()!.colors.primary;
