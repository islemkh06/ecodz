import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/group_activity_service.dart';
import 'work_completion_page.dart';

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
  bool _submitActing = false;
  String? _error;

  // ── Lifecycle: lock countdown + status auto-refresh ──────────────────────
  Timer? _lifecycleTimer;

  // ── Realtime subscription ───────────────────────────────────────────────────
  RealtimeChannel? _realtimeChannel;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeToActivity();
    // Refresh lifecycle status every 30 seconds so lock/start transitions are caught
    _lifecycleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _activity != null) {
        final act = _activity!;
        // Only keep polling while the event can still transition
        if (act.status == 'open' || act.status == 'approved' || act.status == 'locked') {
          _load();
        } else {
          _lifecycleTimer?.cancel();
        }
      }
    });
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
            // Row changed (e.g., status → open after vote)
            if (mounted) _load();
          },
        )
        .subscribe();
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
    _lifecycleTimer?.cancel();
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

                // ── Lock countdown banner (5 min window before start) ───────
                if (act.isWithinLockWindow || act.isLocked) ...[
                  _buildLockBanner(act),
                  const SizedBox(height: 16),
                ],

                // ── In-progress banner ──────────────────────────────────────
                if (act.isInProgress) ...[
                  _buildInProgressBanner(act),
                  const SizedBox(height: 16),
                ],

                // ── Pending validation banner ───────────────────────────────
                if (act.isPendingValidation) ...[
                  _buildValidationPendingBanner(act),
                  const SizedBox(height: 16),
                ],

                // ── Completed banner ────────────────────────────────────────
                if (act.isCompleted) ...[
                  _buildCompletedBanner(act),
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

                // Join / Leave button (everyone, not in terminal states)
                _joinButton(act),

                // Submit completion button (participants + organizer, in_progress only)
                if (act.isInProgress &&
                    (act.isJoined || isOrganizer) &&
                    act.hasStarted) ...[
                  const SizedBox(height: 12),
                  _submitCompletionButton(act),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Lock countdown banner ─────────────────────────────────────────────────

  Widget _buildLockBanner(GroupActivity act) {
    final isLocked = act.isLocked;
    final timeLeft = act.timeUntilStart;
    final mins = timeLeft.inMinutes.remainder(60).abs();
    final secs = timeLeft.inSeconds.remainder(60).abs().toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLocked
              ? [const Color(0xFFB71C1C), const Color(0xFF7F0000)]
              : [const Color(0xFFE65100), const Color(0xFFBF360C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isLocked ? const Color(0xFFB71C1C) : const Color(0xFFE65100))
                .withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isLocked ? Icons.lock_rounded : Icons.lock_clock_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isLocked
                    ? 'Event Locked — starts soon'
                    : 'Locking in $mins:$secs',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            isLocked
                ? 'Participant list is frozen. No more joining or leaving.'
                : 'Event locks 5 minutes before start. Join or leave before then.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          if (!isLocked) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_rounded,
                      color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Starts in  $mins:$secs',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── In-progress banner ────────────────────────────────────────────────────

  Widget _buildInProgressBanner(GroupActivity act) {
    final canSubmit = (act.isJoined || act.organizerId == _myId) && act.hasStarted;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1565C0).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.play_circle_filled_rounded,
                color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'Event In Progress',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            canSubmit
                ? 'The event has started! Once you\'re done, submit your completion photos below.'
                : 'The event is in progress. A participant will submit completion when done.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          if (canSubmit) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitActing ? null : () => _goToCompletion(act),
                icon: _submitActing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Color(0xFF0D47A1), strokeWidth: 2))
                    : const Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('Submit Completion Photos',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF0D47A1),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Pending validation banner ─────────────────────────────────────────────

  Widget _buildValidationPendingBanner(GroupActivity act) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFF9A825).withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.how_to_vote_rounded,
            color: Color(0xFFF9A825), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Awaiting Community Validation',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFF5D4037)),
                ),
                SizedBox(height: 4),
                Text(
                  'Completion has been submitted. The community will vote to approve or reject it.',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF795548), height: 1.4),
                ),
              ]),
        ),
      ]),
    );
  }

  // ── Completed banner ──────────────────────────────────────────────────────

  Widget _buildCompletedBanner(GroupActivity act) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.verified_rounded, color: Colors.amber, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Event Completed!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800),
                ),
                if (act.xpFinal > 0)
                  Text(
                    '+${act.xpFinal} XP awarded to all participants',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
              ]),
        ),
      ]),
    );
  }

  // ── Navigate to completion submission ────────────────────────────────────

  Future<void> _goToCompletion(GroupActivity act) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WorkCompletionPage(
          activityId: act.id,
          activityTitle: act.title,
        ),
      ),
    );
    // Always reload: status may have changed to pending_validation
    if (mounted) await _load();
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
    // Don't show join/leave button in terminal states
    if (act.isInProgress || act.isPendingValidation ||
        act.isCompleted || act.status == 'rejected') {
      return const SizedBox.shrink();
    }

    final isLocked = act.isLocked;
    final isFull = act.isFull && !act.isJoined;
    final isNotOpen = !act.isOpen && !isLocked;

    String label;
    IconData icon;
    Color bgColor;
    bool enabled;

    if (isLocked) {
      label = 'Event Locked';
      icon = Icons.lock_rounded;
      bgColor = Colors.grey.shade500;
      enabled = false;
    } else if (act.isJoined) {
      label = 'Leave Event';
      icon = Icons.exit_to_app_rounded;
      bgColor = Colors.red.shade700;
      enabled = !_toggling;
    } else if (isFull) {
      label = 'Event Full';
      icon = Icons.people_alt_rounded;
      bgColor = Colors.grey.shade500;
      enabled = false;
    } else if (isNotOpen) {
      label = 'Not Available';
      icon = Icons.cancel_rounded;
      bgColor = Colors.grey.shade500;
      enabled = false;
    } else {
      label = 'Join Event';
      icon = Icons.group_add_rounded;
      bgColor = _green;
      enabled = !_toggling;
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? _toggleJoin : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bgColor.withValues(alpha: 0.6),
          disabledForegroundColor: Colors.white70,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: enabled ? 4 : 0,
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
                  Icon(icon, size: 20),
                  const SizedBox(width: 8),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }

  Widget _submitCompletionButton(GroupActivity act) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _submitActing ? null : () => _goToCompletion(act),
        icon: _submitActing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : const Icon(Icons.camera_alt_rounded, size: 20),
        label: const Text('Submit Completion',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 4,
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
    final (chipLabel, chipColor, chipIcon) = _resolveStatus();

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

  (String, Color, IconData) _resolveStatus() {
    if (activity.isFull && activity.isOpen) {
      return ('Full', Colors.orange.shade700, Icons.people_alt_rounded);
    }
    return switch (activity.status) {
      'waiting'            => ('Pending Approval',    Colors.orange.shade600,    Icons.hourglass_top_rounded),
      'open' || 'approved' => ('Open',                const Color(0xFF2E7D32),   Icons.check_circle_rounded),
      'locked'             => ('Locked',              Colors.red.shade700,       Icons.lock_rounded),
      'in_progress'        => ('In Progress',         const Color(0xFF1565C0),   Icons.play_circle_filled_rounded),
      'pending_validation' => ('Awaiting Validation', Colors.amber.shade800,     Icons.how_to_vote_rounded),
      'completed'          => ('Completed',           const Color(0xFF2E7D32),   Icons.verified_rounded),
      'rejected'           => ('Rejected',            Colors.red.shade900,       Icons.cancel_rounded),
      _                    => (activity.status.toUpperCase(), Colors.grey.shade600, Icons.info_rounded),
    };
  }
}

// ─── Info grid ────────────────────────────────────────────────────────────────

class _InfoGrid extends StatelessWidget {
  final GroupActivity activity;
  const _InfoGrid({required this.activity});

  @override
  Widget build(BuildContext context) {
    final eventDate = activity.eventDate;
    final timeLeft = activity.timeUntilStart;
    final hasStarted = activity.hasStarted;

    String? remainingLabel;
    if (eventDate != null && !hasStarted) {
      if (timeLeft.inDays > 0) {
        remainingLabel = '${timeLeft.inDays}d ${timeLeft.inHours.remainder(24)}h remaining';
      } else if (timeLeft.inHours > 0) {
        remainingLabel = '${timeLeft.inHours}h ${timeLeft.inMinutes.remainder(60)}m remaining';
      } else if (timeLeft.inMinutes > 0) {
        remainingLabel = '${timeLeft.inMinutes}m ${timeLeft.inSeconds.remainder(60)}s remaining';
      } else {
        remainingLabel = 'Starting now';
      }
    } else if (hasStarted) {
      remainingLabel = 'Event has started';
    }

    final items = <_InfoItem>[
      if (eventDate != null)
        _InfoItem(
          icon: Icons.event_rounded,
          label: 'Event Start',
          value: _fmt(eventDate),
        ),
      if (remainingLabel != null)
        _InfoItem(
          icon: hasStarted ? Icons.play_arrow_rounded : Icons.schedule_rounded,
          label: hasStarted ? 'Status' : 'Time Remaining',
          value: remainingLabel,
        ),
      _InfoItem(
        icon: Icons.people_rounded,
        label: 'Participants',
        value:
            '${activity.currentParticipants} / ${activity.maxParticipants}  (${activity.spotsLeft} spots left)',
      ),
      if (activity.xpFinal > 0)
        _InfoItem(
          icon: Icons.star_rounded,
          label: 'XP Reward',
          value: '+${activity.xpFinal} XP per participant',
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
