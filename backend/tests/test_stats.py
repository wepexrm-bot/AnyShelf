from datetime import date

from app.api.routes.stats import _compute_streaks


def test_streaks_empty():
    assert _compute_streaks([]) == (0, 0)


def test_streaks_single_day():
    assert _compute_streaks([date(2026, 1, 1)])[1] == 1


def test_streaks_best_ignores_break():
    dates = [
        date(2026, 1, 1),
        date(2026, 1, 2),
        date(2026, 1, 3),
        date(2026, 1, 10),
        date(2026, 1, 11),
        date(2026, 1, 12),
    ]
    _, best = _compute_streaks(dates)
    assert best == 3


def test_streaks_gap_resets_run():
    dates = [date(2026, 1, 1), date(2026, 1, 3), date(2026, 1, 4)]
    _, best = _compute_streaks(dates)
    assert best == 2
