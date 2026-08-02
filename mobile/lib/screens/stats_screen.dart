import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/stats_service.dart';
import '../theme/serene_theme.dart';
import '../theme/serene_tokens.dart';
import '../widgets/app_header.dart';

/// The Stats destination: reading dashboard with profile header, headline
/// numbers and a trailing-6-months bar chart — mirroring the web Stats page.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _auth = AuthService();
  final _statsService = StatsService();

  Map<String, dynamic>? _me;
  ReadingStats? _stats;
  List<MonthlyMinutes> _monthly = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        _auth.me(),
        _statsService.stats(),
        _statsService.monthly(),
      ]);
      if (!mounted) return;
      setState(() {
        _me = results[0] as Map<String, dynamic>;
        _stats = results[1] as ReadingStats?;
        _monthly = results[2] as List<MonthlyMinutes>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                      children: [
                        _ProfileHeader(me: _me, streak: _stats?.currentStreak ?? 0),
                        const SizedBox(height: 24),
                        _StatGrid(stats: _stats),
                        const SizedBox(height: 24),
                        _MonthlyChart(monthly: _monthly),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Map<String, dynamic>? me;
  final int streak;
  const _ProfileHeader({required this.me, required this.streak});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final displayName = (me?['display_name'] as String?)?.trim().isNotEmpty == true
        ? me!['display_name'] as String
        : (me?['email'] as String? ?? 'Reader');
    final initials = displayName
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final verified = me?['is_verified'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.all(SereneShape.lg),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: colors.surfaceContainerHighest,
            child: Text(initials,
                style: SereneType.title.copyWith(color: colors.onSurface)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SereneType.headlineMobile
                        .copyWith(color: colors.onSurface)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (verified) const _Badge(label: 'Verified reader'),
                    if (streak > 0) _Badge(label: '$streak day streak'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.all(SereneShape.full),
      ),
      child: Text(label,
          style: SereneType.labelSm.copyWith(color: colors.primary)),
    );
  }
}

class _StatGrid extends StatelessWidget {
  final ReadingStats? stats;
  const _StatGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final hours = ((stats?.totalReadingMinutes ?? 0) / 60).round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _StatCard(width: width, value: '${stats?.booksCompleted ?? 0}', label: 'Books Read'),
            _StatCard(width: width, value: '${stats?.totalPages ?? 0}', label: 'Pages'),
            _StatCard(width: width, value: '$hours', label: 'Hours'),
            _StatCard(width: width, value: '${stats?.bestStreak ?? 0}', label: 'Best Streak'),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final double width;
  final String value;
  final String label;
  const _StatCard({required this.width, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.all(SereneShape.lg),
      ),
      child: Column(
        children: [
          Text(value,
              style: SereneType.title.copyWith(
                  color: colors.primary, fontSize: 30, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(label.toUpperCase(),
              style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<MonthlyMinutes> monthly;
  const _MonthlyChart({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SereneTheme>()!.colors;
    final maxMinutes = monthly.fold<int>(1, (m, e) => e.minutes > m ? e.minutes : m);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.all(SereneShape.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('READING MINUTES — LAST 6 MONTHS',
              style: SereneType.labelSm.copyWith(color: colors.onSurfaceVariant, letterSpacing: 1)),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in monthly)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (m.minutes > 0)
                            Text('${m.minutes}',
                                style: SereneType.labelSm.copyWith(
                                    color: colors.onSurfaceVariant, fontSize: 10)),
                          const SizedBox(height: 4),
                          Container(
                            height: 4 + (m.minutes / maxMinutes) * 80,
                            decoration: BoxDecoration(
                              color: m.minutes == 0
                                  ? colors.primary.withValues(alpha: 0.25)
                                  : colors.primary,
                              borderRadius:
                                  const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(m.label,
                              style: SereneType.labelSm.copyWith(
                                  color: colors.onSurfaceVariant, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
