import 'api_client.dart';

/// A single month's reading minutes from `GET /stats/monthly`.
class MonthlyMinutes {
  final String month;
  final String label;
  final int minutes;

  const MonthlyMinutes({required this.month, required this.label, required this.minutes});

  factory MonthlyMinutes.fromJson(Map<String, dynamic> json) => MonthlyMinutes(
        month: (json['month'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      );
}

/// Reading statistics for the Stats dashboard.
class ReadingStats {
  final int booksCompleted;
  final int totalPages;
  final int totalReadingMinutes;
  final int currentStreak;
  final int bestStreak;

  const ReadingStats({
    required this.booksCompleted,
    required this.totalPages,
    required this.totalReadingMinutes,
    required this.currentStreak,
    required this.bestStreak,
  });

  factory ReadingStats.fromJson(Map<String, dynamic> json) => ReadingStats(
        booksCompleted: (json['books_completed'] as num?)?.toInt() ?? 0,
        totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
        totalReadingMinutes: (json['total_reading_minutes'] as num?)?.toInt() ?? 0,
        currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
        bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
      );
}

class StatsService {
  final ApiClient api;
  StatsService({ApiClient? api}) : api = api ?? ApiClient();

  Future<ReadingStats?> stats() async {
    final data = await api.get('/stats/');
    return ReadingStats.fromJson(data as Map<String, dynamic>);
  }

  Future<List<MonthlyMinutes>> monthly() async {
    final data = await api.get('/stats/monthly');
    return (data as List)
        .map((m) => MonthlyMinutes.fromJson(m as Map<String, dynamic>))
        .toList();
  }
}
