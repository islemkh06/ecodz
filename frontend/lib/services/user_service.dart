import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/level_system.dart';

/// Holds the current user's profile data fetched from Supabase.
class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final int xp;
  final int level;
  final int reputation;
  final int completedCount;
  final int inProgressCount;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.xp,
    required this.level,
    required this.reputation,
    required this.completedCount,
    required this.inProgressCount,
  });

  double get levelProgress => LevelSystem.levelProgress(xp);
  int get xpForNextLevel => LevelSystem.levelUpperBound(level);
  int get xpAtLevelStart => LevelSystem.levelLowerBound(level);
  String get levelTitle => LevelSystem.levelTitle(level);
}

/// Singleton service for the authenticated user's profile.
class UserService extends ChangeNotifier {
  UserService._();
  static final UserService instance = UserService._();

  UserProfile? _profile;
  bool _loading = false;

  UserProfile? get profile => _profile;
  bool get loading => _loading;

  final _supabase = Supabase.instance.client;
  String? get _uid => _supabase.auth.currentUser?.id;

  /// Fetches the profile and activity counts from Supabase.
  /// Returns silently on error (keeps last cached value).
  Future<void> fetch() async {
    final uid = _uid;
    if (uid == null) return;
    _loading = true;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select().eq('id', uid).single(),
        _supabase
            .from('activite')
            .select('status')
            .eq('assigned_worker_id', uid),
      ]);

      final profileRow = results[0] as Map<String, dynamic>;
      final workRows =
          (results[1] as List).cast<Map<String, dynamic>>();

      final xp = (profileRow['xp'] as num?)?.toInt() ?? 0;
      _profile = UserProfile(
        id: uid,
        fullName: profileRow['full_name'] as String? ??
            _supabase.auth.currentUser?.userMetadata?['name'] as String? ??
            'User',
        email: profileRow['email'] as String? ??
            _supabase.auth.currentUser?.email ?? '',
        xp: xp,
        level: LevelSystem.calculateLevel(xp),
        reputation: (profileRow['reputation'] as num?)?.toInt() ?? 0,
        completedCount: workRows
            .where((r) => r['status'] == 'completed')
            .length,
        inProgressCount: workRows
            .where((r) => r['status'] == 'in_progress')
            .length,
      );
    } catch (e) {
      debugPrint('UserService.fetch error: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Refreshes profile data (call after XP-changing actions).
  Future<void> refresh() => fetch();

  void clear() {
    _profile = null;
    notifyListeners();
  }
}
