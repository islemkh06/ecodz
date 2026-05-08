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
  static const Color _blue = Color(0xFF0D47A1);
  static const Color _lightBlue = Color(0xFFE3F2FD);
  static const Color _surface = Color(0xFFF5FBF4);

  GroupActivity? _activity;
  List<ActivityParticipant> _participants = [];
  bool _loading = true;
  bool _loadingParticipants = false;
  bool _toggling = false;
  String? _error;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
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
      backgroundColor: isError ? Colors.red.shade700 : _blue,
      behavior: SnackBarBehavior.floating,
    ));
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
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: act.imageUrl != null
                ? Image.network(act.imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _gradientAppBarBg())
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
                const SizedBox(height: 20),

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
                              strokeWidth: 2, color: _blue)),
                  ],
                ),
                const SizedBox(height: 8),
                _ParticipantsList(
                  participants: _participants,
                  maxParticipants: act.maxParticipants,
                ),
                const SizedBox(height: 32),

                // Join / Leave button (only for non-organizers)
                if (!isOrganizer) _joinButton(act),
              ],
            ),
          ),
        ),
      ],
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
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
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
          backgroundColor: act.isJoined ? Colors.red.shade700 : _blue,
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

  static const Color _blue = Color(0xFF0D47A1);

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
            color: _blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _blue.withValues(alpha: 0.3)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_rounded, color: _blue, size: 14),
              SizedBox(width: 5),
              Text('Group Event',
                  style: TextStyle(
                    color: _blue,
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

  static const Color _blue = Color(0xFF0D47A1);

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

  static const Color _blue = Color(0xFF0D47A1);
  static const Color _lightBlue = Color(0xFFE3F2FD);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _lightBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(item.icon, color: _blue, size: 18),
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

  static const Color _blue = Color(0xFF0D47A1);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _blue.withValues(alpha: 0.15),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: _blue, fontWeight: FontWeight.bold, fontSize: 16),
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
                color: _blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('You',
                  style: TextStyle(
                      fontSize: 11,
                      color: _blue,
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

  static const Color _blue = Color(0xFF0D47A1);

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _blue.withValues(alpha: 0.12)),
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
        border: Border.all(color: _blue.withValues(alpha: 0.12)),
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

  static const Color _blue = Color(0xFF0D47A1);

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
                backgroundColor: _blue.withValues(alpha: 0.12),
                child: Text(initial,
                    style: const TextStyle(
                        color: _blue,
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
                    color: _blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('You',
                      style: TextStyle(
                          fontSize: 10,
                          color: _blue,
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
        child: CircularProgressIndicator(color: Color(0xFF0D47A1)),
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
