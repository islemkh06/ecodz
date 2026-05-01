import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class EventModel {
  final int id;
  final int? actId;
  final String title;
  final String? description;
  final String organizerId;
  final DateTime eventDate;
  final DateTime expirationDate;
  final int maxParticipants;
  final int currentParticipants;
  final String status; // open | closed | expired | cancelled
  final DateTime createdAt;

  // Joined field — populated when fetching with registration context
  bool isRegistered;

  EventModel({
    required this.id,
    this.actId,
    required this.title,
    this.description,
    required this.organizerId,
    required this.eventDate,
    required this.expirationDate,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.status,
    required this.createdAt,
    this.isRegistered = false,
  });

  factory EventModel.fromMap(Map<String, dynamic> m) {
    final eventDate = DateTime.parse(m['event_date'] as String);
    return EventModel(
      id: m['id'] as int,
      actId: m['id_act'] as int?,
      title: m['title'] as String,
      description: m['description'] as String?,
      organizerId: m['organizer_id'] as String,
      eventDate: eventDate,
      expirationDate: eventDate.subtract(const Duration(hours: 12)),
      maxParticipants: m['max_participants'] as int? ?? 10,
      currentParticipants: m['current_participants'] as int? ?? 0,
      status: m['status'] as String? ?? 'open',
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  bool get isFull => currentParticipants >= maxParticipants;
  bool get isExpired => DateTime.now().isAfter(expirationDate);
  bool get isOpen => status == 'open' && !isExpired && !isFull;

  int get spotsLeft => maxParticipants - currentParticipants;
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class EventService {
  EventService._();
  static final instance = EventService._();

  final _db = Supabase.instance.client;

  String get _currentUserId =>
      _db.auth.currentUser?.id ?? (throw Exception('Not authenticated'));

  // ── Create ───────────────────────────────────────────────────────────────

  /// Creates a new event linked to an activity.
  Future<EventModel> createEvent({
    required int actId,
    required String title,
    String? description,
    required DateTime eventDate,
    required int maxParticipants,
  }) async {
    final row = await _db
        .from('event')
        .insert({
          'id_act':           actId,
          'title':            title,
          'description':      description,
          'organizer_id':     _currentUserId,
          'event_date':       eventDate.toUtc().toIso8601String(),
          'max_participants': maxParticipants,
        })
        .select()
        .single();

    return EventModel.fromMap(row);
  }

  // ── Read ─────────────────────────────────────────────────────────────────

  /// Fetches all events for a given activity, ordered by event_date ascending.
  Future<List<EventModel>> fetchEventsForActivity(int actId) async {
    final uid = _currentUserId;

    final rows = await _db
        .from('event')
        .select('*, event_registration(user_id, status)')
        .eq('id_act', actId)
        .order('event_date');

    return rows.map<EventModel>((m) {
      final event = EventModel.fromMap(m);
      final regs = (m['event_registration'] as List?) ?? [];
      event.isRegistered = regs.any(
        (r) => r['user_id'] == uid && r['status'] == 'confirmed',
      );
      return event;
    }).toList();
  }

  /// Fetches all upcoming events across the platform.
  Future<List<EventModel>> fetchUpcomingEvents() async {
    final uid = _currentUserId;

    final rows = await _db
        .from('event')
        .select('*, event_registration(user_id, status)')
        .inFilter('status', ['open', 'closed'])
        .gte('event_date', DateTime.now().toUtc().toIso8601String())
        .order('event_date')
        .limit(50);

    return rows.map<EventModel>((m) {
      final event = EventModel.fromMap(m);
      final regs = (m['event_registration'] as List?) ?? [];
      event.isRegistered = regs.any(
        (r) => r['user_id'] == uid && r['status'] == 'confirmed',
      );
      return event;
    }).toList();
  }

  // ── Participate ───────────────────────────────────────────────────────────

  /// Joins an event. Returns null on success, or an error message string.
  Future<String?> joinEvent(int eventId) async {
    try {
      final result = await _db.rpc(
        'join_event',
        params: {
          'p_event_id': eventId,
          'p_user_id':  _currentUserId,
        },
      ) as Map<String, dynamic>;

      if (result['success'] == true) return null;
      final err = result['error'] as String? ?? 'unknown_error';
      return _humanizeError(err);
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Leaves / cancels registration for an event.
  Future<String?> leaveEvent(int eventId) async {
    try {
      final result = await _db.rpc(
        'leave_event',
        params: {
          'p_event_id': eventId,
          'p_user_id':  _currentUserId,
        },
      ) as Map<String, dynamic>;

      if (result['success'] == true) return null;
      final err = result['error'] as String? ?? 'unknown_error';
      return _humanizeError(err);
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Cancel event (organizer) ──────────────────────────────────────────────

  Future<void> cancelEvent(int eventId) async {
    await _db
        .from('event')
        .update({'status': 'cancelled'})
        .eq('id', eventId)
        .eq('organizer_id', _currentUserId);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _humanizeError(String code) => switch (code) {
        'already_registered'    => 'You are already registered for this event.',
        'registration_not_found'=> 'No active registration found.',
        _                       => code,
      };
}
