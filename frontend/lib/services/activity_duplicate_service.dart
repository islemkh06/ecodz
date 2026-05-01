import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents a nearby activity returned by the anti-duplication RPC.
class NearbyActivity {
  final int idAct;
  final String titre;
  final String? localisation;
  final String status;
  final double distanceMeters;
  final bool hasAssignedWorker;
  final String? assignedWorkerId;
  final double similarityScore;

  const NearbyActivity({
    required this.idAct,
    required this.titre,
    this.localisation,
    required this.status,
    required this.distanceMeters,
    required this.hasAssignedWorker,
    this.assignedWorkerId,
    required this.similarityScore,
  });

  factory NearbyActivity.fromMap(Map<String, dynamic> m) => NearbyActivity(
        idAct: m['id_act'] as int,
        titre: m['titre'] as String? ?? '',
        localisation: m['localisation'] as String?,
        status: m['status'] as String? ?? '',
        distanceMeters: (m['distance_meters'] as num).toDouble(),
        hasAssignedWorker: m['has_assigned_worker'] as bool? ?? false,
        assignedWorkerId: m['assigned_worker_id'] as String?,
        similarityScore: (m['similarity_score'] as num?)?.toDouble() ?? 0.0,
      );

  /// True if the activity is open but nobody has taken it yet.
  bool get isAvailableToJoin =>
      !hasAssignedWorker && status == 'open';

  /// Human-readable distance label.
  String get distanceLabel {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m away';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km away';
  }
}

/// Result of a duplicate check.
class DuplicateCheckResult {
  final List<NearbyActivity> nearby;

  const DuplicateCheckResult({required this.nearby});

  bool get hasDuplicates => nearby.isNotEmpty;

  /// True if any nearby activity is exact same type, very close (< 100 m)
  /// and has a high title similarity — considered a hard block.
  bool get isHardBlock => nearby.any(
        (a) => a.distanceMeters < 100 && a.similarityScore > 0.7,
      );
}

class ActivityDuplicateService {
  ActivityDuplicateService._();
  static final instance = ActivityDuplicateService._();

  final _supabase = Supabase.instance.client;

  /// Calls the `find_nearby_activities` Supabase RPC.
  ///
  /// [lat] / [lon] — activity coordinates
  /// [typeId]      — selected `id_type_act`
  /// [radius]      — search radius in metres (default 500 m)
  /// [titleHint]   — user-typed title for similarity matching
  Future<DuplicateCheckResult> check({
    required double lat,
    required double lon,
    required int typeId,
    double radius = 500,
    String? titleHint,
  }) async {
    try {
      final raw = await _supabase.rpc(
        'find_nearby_activities',
        params: {
          'p_lat':           lat,
          'p_lon':           lon,
          'p_type_id':       typeId,
          'p_radius_meters': radius,
          'p_title_hint':    titleHint,
        },
      ) as List;

      final nearby = raw
          .cast<Map<String, dynamic>>()
          .map(NearbyActivity.fromMap)
          .toList();

      return DuplicateCheckResult(nearby: nearby);
    } catch (_) {
      // On network / RPC error, allow creation to proceed rather than blocking
      return const DuplicateCheckResult(nearby: []);
    }
  }
}
