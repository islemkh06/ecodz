/// Mirrors the calculate_level() PostgreSQL function exactly.
///
/// Level thresholds (inclusive upper XP bound per level):
///   L1:   0 –  30  (range  30)
///   L2:  31 –  60  (range  30)
///   L3:  61 – 120  (range  60)
///   L4: 121 – 210  (range  90)
///   L5: 211 – 330  (range 120)
///   … each range grows +30 after L2
class LevelSystem {
  // Upper XP bound (inclusive) for each level index (0-based).
  static const List<int> _upperBounds = [
    30, 60, 120, 210, 330, 480, 660, 870, 1_110, 1_410, 1_770,
  ];

  /// Returns the user's level (1-based) for the given XP.
  static int calculateLevel(int xp) {
    for (int i = 0; i < _upperBounds.length; i++) {
      if (xp <= _upperBounds[i]) return i + 1;
    }
    return _upperBounds.length + 1;
  }

  /// Minimum XP needed to be at [level].
  static int levelLowerBound(int level) {
    if (level <= 1) return 0;
    final idx = level - 2;
    if (idx >= _upperBounds.length) return _upperBounds.last + 1;
    return _upperBounds[idx] + 1;
  }

  /// Maximum XP while still at [level].
  static int levelUpperBound(int level) {
    if (level > _upperBounds.length) return _upperBounds.last + 9999;
    return _upperBounds[level - 1];
  }

  /// Progress within the current level: 0.0 – 1.0.
  static double levelProgress(int xp) {
    final level = calculateLevel(xp);
    final lower = levelLowerBound(level);
    final upper = levelUpperBound(level);
    if (upper <= lower) return 1.0;
    return ((xp - lower) / (upper - lower)).clamp(0.0, 1.0);
  }

  /// Human-readable title for a level.
  static String levelTitle(int level) => switch (level) {
        1 => 'Seedling',
        2 => 'Sprout',
        3 => 'Sapling',
        4 => 'Tree',
        5 => 'Forest Guardian',
        6 => 'Eco Warrior',
        7 => 'Earth Defender',
        8 => 'Planet Protector',
        _ => 'Legend',
      };
}
