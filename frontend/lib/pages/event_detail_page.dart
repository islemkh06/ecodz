import 'package:flutter/material.dart';
import '../services/event_service.dart';
import 'event_create_page.dart';

class EventDetailPage extends StatefulWidget {
  final int actId;
  final String activityTitle;

  const EventDetailPage({
    super.key,
    required this.actId,
    required this.activityTitle,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  static const Color _deepGreen  = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);
  static const Color _softGreen  = Color(0xFFA5D6A7);
  static const Color _surface    = Color(0xFFF5FBF4);

  List<EventModel> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final events =
          await EventService.instance.fetchEventsForActivity(widget.actId);
      if (mounted) setState(() { _events = events; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _toggleRegistration(EventModel event) async {
    final svc = EventService.instance;
    final String? error;

    if (event.isRegistered) {
      error = await svc.leaveEvent(event.id);
    } else {
      error = await svc.joinEvent(event.id);
    }

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(event.isRegistered
            ? 'You have left the event.'
            : 'You have joined the event!'),
        backgroundColor: _deepGreen,
        behavior: SnackBarBehavior.floating,
      ));
      _load(); // refresh
    }
  }

  Future<void> _createEvent() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventCreatePage(
          actId: widget.actId,
          activityTitle: widget.activityTitle,
        ),
      ),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        backgroundColor: _deepGreen,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              widget.activityTitle,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createEvent,
        backgroundColor: _deepGreen,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _deepGreen))
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : _events.isEmpty
                  ? _EmptyState(onCreateTap: _createEvent)
                  : RefreshIndicator(
                      color: _deepGreen,
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: _events.length,
                        itemBuilder: (_, i) => _EventCard(
                          event: _events[i],
                          onToggle: () => _toggleRegistration(_events[i]),
                        ),
                      ),
                    ),
    );
  }
}

// ─── Event card ───────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  static const Color _deepGreen  = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);
  static const Color _softGreen  = Color(0xFFA5D6A7);

  final EventModel event;
  final VoidCallback onToggle;

  const _EventCard({required this.event, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final pct = event.maxParticipants > 0
        ? (event.currentParticipants / event.maxParticipants).clamp(0.0, 1.0)
        : 0.0;
    final canRegister = event.isOpen && !event.isRegistered;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: event.isRegistered ? _softGreen : _lightGreen,
          width: event.isRegistered ? 2.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + status badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _deepGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: event.status, isExpired: event.isExpired),
              ],
            ),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                event.description!,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),

            // Event date
            _InfoRow(
              icon: Icons.calendar_today,
              label: _formatDate(event.eventDate),
            ),
            const SizedBox(height: 4),

            // Expiration
            _InfoRow(
              icon: Icons.lock_clock,
              label:
                  'Registrations close: ${_formatDate(event.expirationDate)}',
              color: event.isExpired ? Colors.red : Colors.orange.shade700,
            ),
            const SizedBox(height: 12),

            // Participant bar
            Row(
              children: [
                const Icon(Icons.group, size: 16, color: Colors.black45),
                const SizedBox(width: 6),
                Text(
                  '${event.currentParticipants} / ${event.maxParticipants} participants',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if (event.spotsLeft > 0 && event.isOpen) ...[
                  const Spacer(),
                  Text(
                    '${event.spotsLeft} spot${event.spotsLeft == 1 ? '' : 's'} left',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _deepGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: _lightGreen,
                valueColor: AlwaysStoppedAnimation(
                  pct >= 1.0 ? Colors.red.shade400 : _deepGreen,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Join / leave button
            SizedBox(
              width: double.infinity,
              child: event.isRegistered
                  ? OutlinedButton.icon(
                      onPressed: onToggle,
                      icon: const Icon(Icons.exit_to_app, size: 18),
                      label: const Text('Leave Event'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: canRegister ? onToggle : null,
                      icon: const Icon(Icons.how_to_reg, size: 18),
                      label: Text(
                        event.isFull
                            ? 'Event Full'
                            : event.isExpired
                                ? 'Registrations Closed'
                                : event.status == 'cancelled'
                                    ? 'Event Cancelled'
                                    : 'Join Event',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _deepGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}  •  $h:$m';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black54;
    return Row(
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isExpired;
  const _StatusBadge({required this.status, required this.isExpired});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  (String, Color) _resolve() {
    if (isExpired) return ('Expired', Colors.grey);
    return switch (status) {
      'open'      => ('Open', const Color(0xFF2E7D32)),
      'closed'    => ('Full', Colors.red),
      'expired'   => ('Expired', Colors.grey),
      'cancelled' => ('Cancelled', Colors.red.shade900),
      _           => (status, Colors.grey),
    };
  }
}

// ─── Empty / error states ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  static const Color _deepGreen = Color(0xFF1B5E20);
  final VoidCallback onCreateTap;
  const _EmptyState({required this.onCreateTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.event_available, size: 64, color: Colors.black26),
          const SizedBox(height: 16),
          const Text(
            'No events yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black45),
          ),
          const SizedBox(height: 8),
          const Text(
            'Organise a group effort by creating the first event.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black38),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add),
            label: const Text('Create Event'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _deepGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
