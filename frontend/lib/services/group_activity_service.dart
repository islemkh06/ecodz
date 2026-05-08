import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum ActivityMode { single, group }

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class GroupActivity {
  final int id;
  final String title;
  final String? description;
  final String? location;
  final double? latitude;
  final double? longitude;
  final String organizerId;
  final String? organizerName;
  final DateTime? eventDate;
  final int maxParticipants;
  final int currentParticipants;
  final String status;
  final DateTime createdAt;
  final String? imageUrl;
  final String? categoryName;

  /// Set when the event is in the creator-priority phase
  final DateTime? priorityDeadline;
  final String? creatorPriorityStatus; // 'pending' | 'accepted' | 'declined' | 'expired'

  /// Populated at query time for the current user
  bool isJoined;

  GroupActivity({
    required this.id,
    required this.title,
    this.description,
    this.location,
    this.latitude,
    this.longitude,
    required this.organizerId,
    this.organizerName,
    this.eventDate,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.status,
    required this.createdAt,
    this.imageUrl,
    this.categoryName,
    this.priorityDeadline,
    this.creatorPriorityStatus,
    this.isJoined = false,
  });

  factory GroupActivity.fromMap(Map<String, dynamic> m) {
    final preuveList = m['preuve'] as List? ?? [];
    // Use event_image_url first; fall back to first preuve photo
    final directImageUrl = m['event_image_url'] as String?;
    final imageUrl = directImageUrl?.isNotEmpty == true
        ? directImageUrl
        : (preuveList.isNotEmpty ? preuveList.first['url'] as String? : null);

    // PostgREST alias used to disambiguate the two FK relations to profiles
    final profileMap = (m['creator'] ?? m['profiles']) as Map<String, dynamic>?;
    final organizerName = profileMap?['full_name'] as String?;

    final categoryMap = m['type_activite'] as Map<String, dynamic>?;
    final categoryName = categoryMap?['nom'] as String?;

    return GroupActivity(
      id: m['id_act'] as int,
      title: m['titre'] as String? ?? '',
      description: m['description'] as String?,
      location: m['localisation'] as String?,
      latitude: (m['latitude'] as num?)?.toDouble(),
      longitude: (m['longitude'] as num?)?.toDouble(),
      organizerId: m['id_utilisateur'] as String? ?? '',
      organizerName: organizerName,
      eventDate: m['event_date'] != null
          ? DateTime.tryParse(m['event_date'] as String)
          : null,
      maxParticipants: m['max_participants'] as int? ?? 10,
      currentParticipants: m['current_participants_count'] as int? ?? 0,
      status: m['status'] as String? ?? 'open',
      createdAt: m['datecreation'] != null
          ? DateTime.tryParse(m['datecreation'] as String) ?? DateTime.now()
          : DateTime.now(),
      imageUrl: imageUrl,
      categoryName: categoryName,
      priorityDeadline: m['priority_deadline'] != null
          ? DateTime.tryParse(m['priority_deadline'] as String)?.toLocal()
          : null,
      creatorPriorityStatus: m['creator_priority_status'] as String?,
    );
  }

  bool get isFull => currentParticipants >= maxParticipants;
  /// True only when the event is openly available to all users.
  bool get isOpen => status == 'open' || status == 'approved';
  /// True during the 1-minute creator priority window.
  bool get isPriorityPending => status == 'priority_pending';
  int get spotsLeft => maxParticipants - currentParticipants;
}

class ActivityParticipant {
  final int id;
  final int activityId;
  final String userId;
  final String? userName;
  final String? userEmail;
  final DateTime joinedAt;
  final String status;

  const ActivityParticipant({
    required this.id,
    required this.activityId,
    required this.userId,
    this.userName,
    this.userEmail,
    required this.joinedAt,
    required this.status,
  });

  factory ActivityParticipant.fromMap(Map<String, dynamic> m) {
    final profileMap = m['profiles'] as Map<String, dynamic>?;
    return ActivityParticipant(
      id: m['id'] as int,
      activityId: m['activity_id'] as int,
      userId: m['user_id'] as String,
      userName: profileMap?['full_name'] as String?,
      userEmail: profileMap?['email'] as String?,
      joinedAt: DateTime.parse(m['joined_at'] as String),
      status: m['status'] as String? ?? 'confirmed',
    );
  }
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class GroupActivityService {
  GroupActivityService._();
  static final instance = GroupActivityService._();

  final _db = Supabase.instance.client;

  String get _uid =>
      _db.auth.currentUser?.id ?? (throw Exception('Not authenticated'));

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<GroupActivity> createGroupActivity({
    required String title,
    String? description,
    String? location,
    double? latitude,
    double? longitude,
    required DateTime eventDate,
    required int maxParticipants,
    int? categoryId,
    int? levelId,
    int? xpFinal,
    String? imageUrl,
  }) async {
    final uid = _uid;

    // Ensure profiles row exists
    await _db.from('profiles').upsert({
      'id': uid,
      'full_name': _db.auth.currentUser?.userMetadata?['name'] as String? ??
          _db.auth.currentUser?.email?.split('@').first ?? 'User',
      'email': _db.auth.currentUser?.email ?? '',
      'level': 1,
      'reputation': 0,
    }, onConflict: 'id');

    final row = await _db
        .from('activite')
        .insert({
          'titre': title,
          'description': description,
          'localisation': location,
          'latitude': latitude,
          'longitude': longitude,
          'xpfinal': xpFinal,
          'id_type_act': categoryId,
          'id_niv_act': levelId,
          'id_utilisateur': uid,
          'activity_mode': 'group',
          'max_participants': maxParticipants,
          'event_date': eventDate.toUtc().toIso8601String(),
          'current_participants_count': 0,
          // status = 'waiting' so community must approve before event goes public
          'status': 'waiting',
          if (imageUrl != null && imageUrl.isNotEmpty) 'event_image_url': imageUrl,
        })
        .select(
          'id_act, titre, description, localisation, latitude, longitude, '
          'id_utilisateur, status, datecreation, event_image_url, '
          'max_participants, current_participants_count, event_date, '
          'type_activite(nom), '
          'creator:profiles!activite_id_utilisateur_fkey(full_name), '
          'preuve(url)',
        )
        .single();

    return GroupActivity.fromMap(row);
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  Future<List<GroupActivity>> fetchUpcomingGroupActivities() async {
    final uid = _uid;

    final rows = await _db
        .from('activite')
        .select(
          'id_act, titre, description, localisation, latitude, longitude, '
          'id_utilisateur, status, datecreation, event_image_url, '
          'max_participants, current_participants_count, event_date, '
          'priority_deadline, creator_priority_status, '
          'type_activite(nom), '
          'creator:profiles!activite_id_utilisateur_fkey(full_name), '
          'preuve(url), '
          'activity_participants(user_id, status)',
        )
        .eq('activity_mode', 'group')
        // Show open/approved events to everyone;
        // also show this user's own priority_pending events (their 1-min window)
        .or('status.in.(open,approved),and(status.eq.priority_pending,id_utilisateur.eq.$uid)')
        .order('event_date', ascending: true)
        .limit(50);

    return (rows as List).map<GroupActivity>((m) {
      final act = GroupActivity.fromMap(m);
      final parts = (m['activity_participants'] as List?) ?? [];
      act.isJoined = parts.any(
        (p) => p['user_id'] == uid && p['status'] == 'confirmed',
      );
      return act;
    }).toList();
  }

  Future<GroupActivity> fetchGroupActivity(int activityId) async {
    final uid = _uid;

    final row = await _db
        .from('activite')
        .select(
          'id_act, titre, description, localisation, latitude, longitude, '
          'id_utilisateur, status, datecreation, event_image_url, '
          'max_participants, current_participants_count, event_date, '
          'priority_deadline, creator_priority_status, '
          'type_activite(nom), '
          'creator:profiles!activite_id_utilisateur_fkey(full_name), '
          'preuve(url), '
          'activity_participants(user_id, status)',
        )
        .eq('id_act', activityId)
        .eq('activity_mode', 'group')
        .single();

    final act = GroupActivity.fromMap(row);
    final parts = (row['activity_participants'] as List?) ?? [];
    act.isJoined = parts.any(
      (p) => p['user_id'] == uid && p['status'] == 'confirmed',
    );
    return act;
  }

  Future<List<ActivityParticipant>> fetchParticipants(int activityId) async {
    final rows = await _db
        .from('activity_participants')
        .select('*, profiles(full_name, email)')
        .eq('activity_id', activityId)
        .eq('status', 'confirmed')
        .order('joined_at');

    return (rows as List)
        .map<ActivityParticipant>(
          (m) => ActivityParticipant.fromMap(m as Map<String, dynamic>),
        )
        .toList();
  }

  // ── Creator Priority RPCs ─────────────────────────────────────────────────

  /// Creator accepts priority participation. Returns null on success.
  Future<String?> acceptCreatorPriority(int activityId) async {
    try {
      final result = await _db.rpc(
        'accept_creator_priority',
        params: {'p_activity_id': activityId},
      ) as Map<String, dynamic>;
      if (result['success'] == true) return null;
      return _humanizeError(result['error'] as String? ?? 'unknown_error');
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Creator declines priority participation. Returns null on success.
  Future<String?> declineCreatorPriority(int activityId) async {
    try {
      final result = await _db.rpc(
        'decline_creator_priority',
        params: {'p_activity_id': activityId},
      ) as Map<String, dynamic>;
      if (result['success'] == true) return null;
      return _humanizeError(result['error'] as String? ?? 'unknown_error');
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Auto-expire the priority window server-side (called when client timer hits 0).
  Future<void> expireCreatorPriority(int activityId) async {
    try {
      await _db.rpc(
        'expire_creator_priority',
        params: {'p_activity_id': activityId},
      );
    } catch (_) {
      // Non-critical – the DB will handle expiry on next RPC call anyway
    }
  }

  // ── Join / Leave ───────────────────────────────────────────────────────────

  /// Returns null on success, or a human-readable error string.
  Future<String?> joinGroupActivity(int activityId) async {
    try {
      final result = await _db.rpc(
        'join_group_activity',
        params: {'p_activity_id': activityId, 'p_user_id': _uid},
      ) as Map<String, dynamic>;

      if (result['success'] == true) return null;
      return _humanizeError(result['error'] as String? ?? 'unknown_error');
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> leaveGroupActivity(int activityId) async {
    try {
      final result = await _db.rpc(
        'leave_group_activity',
        params: {'p_activity_id': activityId, 'p_user_id': _uid},
      ) as Map<String, dynamic>;

      if (result['success'] == true) return null;
      return _humanizeError(result['error'] as String? ?? 'unknown_error');
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _humanizeError(String code) {
    switch (code) {
      case 'activity_not_found':
        return 'Activity not found.';
      case 'not_a_group_activity':
        return 'This is not a group activity.';
      case 'activity_not_open':
        return 'This activity is no longer open.';
      case 'activity_full':
        return 'This activity is already full.';
      case 'already_joined':
        return 'You have already joined this activity.';
      case 'creator_priority_active':
        return 'The event creator has a 1-minute priority window. Please try again shortly.';
      case 'priority_expired':
        return 'The priority window has expired. The event is now open.';
      case 'not_creator':
        return 'Only the event creator can perform this action.';
      case 'not_in_priority_phase':
        return 'This event is no longer in the priority phase.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
