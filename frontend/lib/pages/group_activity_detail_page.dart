import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_activity_service.dart';

class GroupActivityDetailPage extends StatefulWidget {
  final int activityId;

  const GroupActivityDetailPage({super.key, required this.activityId});

  @override
  State<GroupActivityDetailPage> createState() =>
      _GroupActivityDetailPageState();
}

class _GroupActivityDetailPageState extends State<GroupActivityDetailPage> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _surface = Color(0xFFF5FBF4);

  GroupActivity? _activity;
  List<ActivityParticipant> _participants = [];
  bool _loading = true;
  bool _loadingParticipants = false;
  bool _toggling = false;
  bool _priorityActing = false;
  String? _error;

  // ── Priority countdown ──────────────────────────────────────────────────────
  Timer? _priorityTimer;
  int _countdownSeconds = 0;

  // ── Realtime subscription ───────────────────────────────────────────────────
  RealtimeChannel? _realtimeChannel;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToActivity();
  }

  // ── Realtime subscription ───────────────────────────────────────────────────
  void _subscribeToActivity() {
    _realtimeChannel = Supabase.instance.client
        .channel('grp_act_${widget.activityId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'activite',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id_act',
            value: widget.activityId,
          ),
          callback: (payload) {
            // Row changed (e.g., status → priority_pending after vote)
            if (mounted) _load();
          },
        )
        .subscribe();
  }

  // ── Priority countdown ──────────────────────────────────────────────────────
  void _startPriorityCountdown() {
    _stopPriorityCountdown();
    final deadline = _activity?.priorityDeadline;
    if (deadline == null) return;

    final remaining = deadline.difference(DateTime.now());
    if (remaining.isNegative) {
      _expirePriority();
      return;
    }

    setState(() => _countdownSeconds = remaining.inSeconds.clamp(0, 60));

    _priorityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final rem = (_activity?.priorityDeadline
                  ?.difference(DateTime.now())
                  .inSeconds ??
              -1)
          .clamp(0, 60);
      if (rem <= 0) {
        _stopPriorityCountdown();
        _expirePriority();
      } else {
        setState(() => _countdownSeconds = rem);
      }
    });
  }

  void _stopPriorityCountdown() {
    _priorityTimer?.cancel();
    _priorityTimer = null;
  }

  Future<void> _expirePriority() async {
    await GroupActivityService.instance.expireCreatorPriority(widget.activityId);
    if (mounted) _load();
  }

  // ── Priority accept / decline ───────────────────────────────────────────────
  Future<void> _acceptPriority() async {
    setState(() => _priorityActing = true);
    final err = await GroupActivityService.instance
        .acceptCreatorPriority(widget.activityId);
    if (!mounted) return;
    if (err != null) {
      _snack(err, isError: true);
    } else {
      _snack('You joined! The event is now open to all participants.');
      _stopPriorityCountdown();
    }
    setState(() => _priorityActing = false);
    await _load();
  }

  Future<void> _declinePriority() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip priority spot?'),
        content: const Text(
            'The event will immediately open to other participants. You can still join normally afterwards.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _priorityActing = true);
    final err = await GroupActivityService.instance
        .declineCreatorPriority(widget.activityId);
    if (!mounted) return;
    if (err != null) {
      _snack(err, isError: true);
    } else {
      _snack('Priority skipped. The event is now public.');
      _stopPriorityCountdown();
    }
    setState(() => _priorityActing = false);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final act = await GroupActivityService.instance
          .fetchGroupActivity(widget.activityId);
      if (!mounted) return;
      setState(() {
        _activity = act;
        _loading = false;
      });
      // Start or stop countdown based on priority phase
      if (act.isPriorityPending && act.organizerId == _myId) {
        _startPriorityCountdown();
      } else {
        _stopPriorityCountdown();
      }
      _loadParticipants();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadParticipants() async {
    setState(() => _loadingParticipants = true);
    try {
      final list = await GroupActivityService.instance
          .fetchParticipants(widget.activityId);
      if (mounted) setState(() => _participants = list);
    } catch (_) {
      // non-critical
    } finally {
      if (mounted) setState(() => _loadingParticipants = false);
    }
  }

  Future<void> _toggleJoin() async {
    final act = _activity;
    if (act == null) return;
    setState(() => _toggling = true);

    final svc = GroupActivityService.instance;
    final String? err;

    if (act.isJoined) {
      err = await svc.leaveGroupActivity(act.id);
    } else {
      err = await svc.joinGroupActivity(act.id);
    }

    if (!mounted) return;

    if (err != null) {
      _snack(err, isError: true);
    } else {
      _snack(act.isJoined ? 'You left the event.' : 'You joined the event!');
      await _load();
    }
    if (mounted) setState(() => _toggling = false);
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : _green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _stopPriorityCountdown();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      body: _loading
          ? const _LoadingView()
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final act = _activity!;
    final isOrganizer = act.organizerId == _myId;

    return CustomScrollView(
      slivers: [
        // App bar with image or gradient
        SliverAppBar(
          expandedHeight: 200,
          pinned: true,
          backgroundColor: _deepGreen,
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: act.imageUrl != null
                ? Image.network(act.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => _gradientAppBarBg())
                : _gradientAppBarBg(),
          ),
          title: Text(act.title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          actions: [
            if (isOrganizer)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
              ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status row
                _StatusRow(activity: act),
                const SizedBox(height: 16),

                // ── Priority banner (only during priority_pending) ──────────
                if (act.isPriorityPending) ...[  
                  if (isOrganizer)
                    _buildCreatorPriorityBanner(act)
                  else
                    _buildWaitingForCreatorBanner(act),
                  const SizedBox(height: 16),
                ],

                // Info cards
                _InfoGrid(activity: act),
                const SizedBox(height: 24),

                // Description
                if (act.description != null && act.description!.isNotEmpty) ...[
                  _sectionTitle('About This Event'),
                  const SizedBox(height: 8),
                  Text(
                    act.description!,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.black87, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                ],

                // Organizer
                _sectionTitle('Organizer'),
                const SizedBox(height: 8),
                _OrganizerTile(
                  name: act.organizerName ?? 'Unknown',
                  isMe: isOrganizer,
                ),
                const SizedBox(height: 24),

                // Participants section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle(
                        'Participants (${act.currentParticipants}/${act.maxParticipants})'),
                    if (_loadingParticipants)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF2E7D32))),
                  ],
                ),
                const SizedBox(height: 8),
                _ParticipantsList(
                  participants: _participants,
                  maxParticipants: act.maxParticipants,
                ),
                const SizedBox(height: 32),

                // Join / Leave button (only for non-organizers, not during priority_pending)
                if (!isOrganizer && !act.isPriorityPending) _joinButton(act),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Priority phase widgets ─────────────────────────────────────────────────

  /// Banner shown to the event creator during the 1-minute priority window.
  Widget _buildCreatorPriorityBanner(GroupActivity act) {
    final mins = _countdownSeconds ~/ 60;
    final secs = (_countdownSeconds % 60).toString().padLeft(2, '0');
    final urgency = _countdownSeconds <= 15;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: urgency
              ? [const Color(0xFFE65100), const Color(0xFFBF360C)]
              : [const Color(0xFF2E7D32), const Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (urgency ? const Color(0xFFE65100) : const Color(0xFF1B5E20))
                .withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'You have Priority Participation!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'As the event creator, you get the first spot — confirm within the countdown.',
            style: TextStyle(
                color: Colors.white70, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),

          // Countdown
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_rounded,
                    color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Time remaining: $mins:$secs',
                  style: TextStyle(
                    color: urgency ? Colors.amber : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Buttons
          if (_priorityActing)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
            )
          else
            Row(children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _acceptPriority,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Confirm Participation',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1B5E20),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _declinePriority,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Skip',
                    style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  /// Banner shown to OTHER users while the creator has priority.
  Widget _buildWaitingForCreatorBanner(GroupActivity act) {
    final deadline = act.priorityDeadline;
    final rem = deadline != null
        ? deadline.difference(DateTime.now()).inSeconds.clamp(0, 60)
        : 0;
    final mins = rem ~/ 60;
    final secs = (rem % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC02).withValues(alpha: 0.6)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.hourglass_top_rounded,
            color: Color(0xFFF57F17), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Awaiting creator confirmation',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF5D4037)),
            ),
            const SizedBox(height: 4),
            Text(
              rem > 0
                  ? 'The creator has $mins:$secs to claim their spot.\nJoin will open immediately after.'
                  : 'Join is opening soon…',
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF795548), height: 1.4),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF333333),
        ),
      );

  Widget _gradientAppBarBg() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF388E3C), Color(0xFF1B5E20)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.groups_rounded, size: 80, color: Colors.white24),
        ),
      );

  Widget _joinButton(GroupActivity act) {
    final isFull = act.isFull && !act.isJoined;
    final isNotOpen = !act.isOpen;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (_toggling || isFull || isNotOpen) ? null : _toggleJoin,
        style: ElevatedButton.styleFrom(
          backgroundColor: act.isJoined ? Colors.red.shade700 : _green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          disabledForegroundColor: Colors.grey.shade600,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
        ),
        child: _toggling
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    act.isJoined
                        ? Icons.exit_to_app_rounded
                        : Icons.group_add_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isNotOpen
                        ? 'Activity Closed'
                        : isFull
                            ? 'Event Full'
                            : act.isJoined
                                ? 'Leave Event'
                                : 'Join Event',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Status row ───────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final GroupActivity activity;
  const _StatusRow({required this.activity});

  @override
  Widget build(BuildContext context) {
    final isOpen = activity.isOpen && !activity.isFull;
    final isFull = activity.isFull;

    Color chipColor;
    String chipLabel;
    IconData chipIcon;

    if (isFull) {
      chipColor = Colors.orange.shade700;
      chipLabel = 'Full';
      chipIcon = Icons.people_alt_rounded;
    } else if (activity.status == 'waiting') {
      chipColor = Colors.orange.shade600;
      chipLabel = 'Pending Approval';
      chipIcon = Icons.hourglass_top_rounded;
    } else if (isOpen) {
      chipColor = const Color(0xFF2E7D32);
      chipLabel = 'Open';
      chipIcon = Icons.check_circle_rounded;
    } else {
      chipColor = Colors.grey.shade600;
      chipLabel = activity.status.toUpperCase();
      chipIcon = Icons.cancel_rounded;
    }

    return Row(
      children: [
        // Status chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: chipColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: chipColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chipIcon, color: chipColor, size: 14),
              const SizedBox(width: 5),
              Text(chipLabel,
                  style: TextStyle(
                    color: chipColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),

        const SizedBox(width: 10),

        // Group badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_rounded, color: Color(0xFF2E7D32), size: 14),
              SizedBox(width: 5),
              Text('Group Event',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Info grid ────────────────────────────────────────────────────────────────

class _InfoGrid extends StatelessWidget {
  final GroupActivity activity;
  const _InfoGrid({required this.activity});

  @override
  Widget build(BuildContext context) {
    final items = <_InfoItem>[
      if (activity.eventDate != null)
        _InfoItem(
          icon: Icons.event_rounded,
          label: 'Date & Time',
          value: _fmt(activity.eventDate!),
        ),
      _InfoItem(
        icon: Icons.people_rounded,
        label: 'Participants',
        value:
            '${activity.currentParticipants} / ${activity.maxParticipants}  (${activity.spotsLeft} spots left)',
      ),
      if (activity.location != null)
        _InfoItem(
          icon: Icons.location_on_rounded,
          label: 'Location',
          value: activity.location!,
        ),
      if (activity.categoryName != null)
        _InfoItem(
          icon: Icons.category_rounded,
          label: 'Category',
          value: activity.categoryName!,
        ),
    ];

    return Column(
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _InfoTile(item: item),
              ))
          .toList(),
    );
  }

  static String _fmt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  ·  $h:$m';
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  const _InfoItem({required this.icon, required this.label, required this.value});
}

class _InfoTile extends StatelessWidget {
  final _InfoItem item;
  const _InfoTile({required this.item});

  static const Color _green = Color(0xFF2E7D32);
  static const Color _lightGreen = Color(0xFFE8F5E9);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _lightGreen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: _green, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(item.value,
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Organizer tile ───────────────────────────────────────────────────────────

class _OrganizerTile extends StatelessWidget {
  final String name;
  final bool isMe;

  const _OrganizerTile({required this.name, required this.isMe});

  static const Color _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _green.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: _green, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ),
          if (isMe)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('You',
                  style: TextStyle(
                      fontSize: 11,
                      color: _green,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

// ─── Participants list ────────────────────────────────────────────────────────

class _ParticipantsList extends StatelessWidget {
  final List<ActivityParticipant> participants;
  final int maxParticipants;

  const _ParticipantsList({
    required this.participants,
    required this.maxParticipants,
  });

  static const Color _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withValues(alpha: 0.12)),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.people_outline_rounded,
                  size: 36, color: Colors.black.withValues(alpha: 0.25)),
              const SizedBox(height: 8),
              Text(
                'No participants yet. Be the first to join!',
                style: TextStyle(
                    fontSize: 13, color: Colors.black.withValues(alpha: 0.4)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _green.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: participants
            .asMap()
            .entries
            .map((e) => _ParticipantTile(
                  participant: e.value,
                  isLast: e.key == participants.length - 1,
                ))
            .toList(),
      ),
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  final ActivityParticipant participant;
  final bool isLast;

  const _ParticipantTile({required this.participant, required this.isLast});

  static const Color _green = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final isMe = participant.userId == myId;
    final name = participant.userName ?? 'Member';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _green.withValues(alpha: 0.12),
                child: Text(initial,
                    style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    Text(
                      'Joined ${_timeAgo(participant.joinedAt)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.black.withValues(alpha: 0.4)),
                    ),
                  ],
                ),
              ),
              if (isMe)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('You',
                      style: TextStyle(
                          fontSize: 10,
                          color: _green,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 56,
              endIndent: 14,
              color: Colors.black.withValues(alpha: 0.06)),
      ],
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─── Loading / Error views ────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 56, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D47A1),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
}
