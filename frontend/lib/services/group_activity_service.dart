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
  final DateTime? eventDate;       // = event_start_at: when the event actually begins
  final DateTime? lockedAt;        // set when status transitions to 'locked'
  final int maxParticipants;
  final int currentParticipants;
  final String status;
  final DateTime createdAt;
  final String? imageUrl;
  final String? categoryName;
  final int xpFinal;               // XP reward shown on the card

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
    this.lockedAt,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.status,
    required this.createdAt,
    this.imageUrl,
    this.categoryName,
    this.xpFinal = 0,
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
          ? DateTime.tryParse(m['event_date'] as String)?.toLocal()
          : null,
      lockedAt: m['locked_at'] != null
          ? DateTime.tryParse(m['locked_at'] as String)?.toLocal()
          : null,
      maxParticipants: m['max_participants'] as int? ?? 10,
      currentParticipants: m['current_participants_count'] as int? ?? 0,
      status: m['status'] as String? ?? 'open',
      createdAt: m['datecreation'] != null
          ? DateTime.tryParse(m['datecreation'] as String) ?? DateTime.now()
          : DateTime.now(),
      imageUrl: imageUrl,
      categoryName: categoryName,
      xpFinal: (m['xpfinal'] as num?)?.toInt() ?? 0,
    );
  }

  // ── Computed state helpers ────────────────────────────────────────────────

  bool get isFull => currentParticipants >= maxParticipants;

  /// True only when the event is openly available for join/leave.
  bool get isOpen => status == 'open' || status == 'approved';

  /// True when the event is locked (5 min before start) - no join/leave.
  bool get isLocked => status == 'locked';

  /// True when the event is actively in progress.
  bool get isInProgress => status == 'in_progress';

  /// True when the event has completed and is awaiting validation votes.
  bool get isPendingValidation => status == 'pending_validation';

  /// True when the event is fully done.
  bool get isCompleted => status == 'completed';

  /// True when the event start time has passed (locally computed).
  bool get hasStarted =>
      eventDate != null && DateTime.now().isAfter(eventDate!);

  /// True when we are within the 5-minute lock window (local check).
  bool get isWithinLockWindow {
    if (eventDate == null) return false;
    final lockTime = eventDate!.subtract(const Duration(minutes: 5));
    final now = DateTime.now();
    return now.isAfter(lockTime) && now.isBefore(eventDate!);
  }

  /// Duration until the event starts (negative if already started).
  Duration get timeUntilStart =>
      eventDate != null ? eventDate!.difference(DateTime.now()) : Duration.zero;

  /// Duration until the event locks (negative if already locked/started).
  Duration get timeUntilLock {
    if (eventDate == null) return Duration.zero;
    final lockTime = eventDate!.subtract(const Duration(minutes: 5));
    return lockTime.difference(DateTime.now());
  }

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

  // ── Select field list (shared by read methods) ────────────────────────────
  static const _kGroupActivityFields =
      'id_act, titre, description, localisation, latitude, longitude, '
      'id_utilisateur, status, datecreation, event_image_url, xpfinal, '
      'max_participants, current_participants_count, event_date, locked_at, '
      'type_activite(nom), '
      'creator:profiles!activite_id_utilisateur_fkey(full_name), '
      'preuve(url), '
      'activity_participants(user_id, status)';

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
          'id_utilisateur, status, datecreation, event_image_url, xpfinal, '
          'max_participants, current_participants_count, event_date, locked_at, '
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

    // Trigger server-side lock/start transitions before fetching
    _db.rpc('lock_due_group_events').catchError((_) {});
    _db.rpc('start_due_group_events').catchError((_) {});

    final rows = await _db
        .from('activite')
        .select(_kGroupActivityFields)
        .eq('activity_mode', 'group')
        // Show open/approved/locked/in_progress events to everyone
        // (no priority_pending anymore - organizer is auto-added on approval)
        .inFilter(
          'status',
          ['open', 'approved', 'locked', 'in_progress'],
        )
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

    // Atomically advance this event's status if needed
    await _db.rpc(
      'refresh_group_event_status',
      params: {'p_activity_id': activityId},
    ).catchError((_) {});

    final row = await _db
        .from('activite')
        .select(_kGroupActivityFields)
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

  // ── Lifecycle: refresh status ─────────────────────────────────────────────

  /// Asks the server to advance this event's status (open→locked→in_progress).
  /// Returns the new status string, or null on error.
  Future<String?> refreshEventStatus(int activityId) async {
    try {
      final result = await _db.rpc(
        'refresh_group_event_status',
        params: {'p_activity_id': activityId},
      ) as Map<String, dynamic>;
      return result['status'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Completion submission (group events) ──────────────────────────────────

  /// Submits completion for a group event (any participant / organizer).
  /// Returns null on success, or a human-readable error string.
  Future<String?> submitGroupEventCompletion(int activityId) async {
    try {
      final result = await _db.rpc(
        'submit_work_completion',
        params: {'p_act_id': activityId, 'p_user_id': _uid},
      ) as Map<String, dynamic>;
      if (result['success'] == true) return null;
      return _humanizeError(result['error'] as String? ?? 'unknown_error');
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
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
      case 'event_not_found':
        return 'Event not found.';
      case 'not_a_group_activity':
        return 'This is not a group event.';
      case 'activity_not_open':
        return 'This event is no longer open for joining.';
      case 'activity_full':
        return 'This event is already full.';
      case 'already_joined':
        return 'You have already joined this event.';
      case 'event_locked':
        return 'This event is locked — join/leave is disabled 5 minutes before the start.';
      case 'event_started':
        return 'The event has already started. You can no longer join or leave.';
      case 'event_not_started':
      case 'event_not_in_progress':
        return 'The event has not started yet.';
      case 'event_not_started_yet':
        return 'Completion can only be submitted after the event has started.';
      case 'not_a_participant':
        return 'You must be a confirmed participant to submit completion.';
      case 'no_completion_photos':
        return 'Please upload at least one after-photo before submitting.';
      case 'not_creator':
        return 'Only the event creator can perform this action.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
