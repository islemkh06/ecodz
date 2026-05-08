import 'package:flutter/material.dart';

/// Shown when the user taps the "+" FAB.
/// Returns [ActivityTypeChoice.single] or [ActivityTypeChoice.group],
/// or null if dismissed.
enum ActivityTypeChoice { single, group }

Future<ActivityTypeChoice?> showActivityTypeSelectionModal(
    BuildContext context) {
  return showModalBottomSheet<ActivityTypeChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ActivityTypeSheet(),
  );
}

// ─── Sheet widget ──────────────────────────────────────────────────────────

class _ActivityTypeSheet extends StatelessWidget {
  const _ActivityTypeSheet();

  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _surface = Color(0xFFF5FBF4);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          const Text(
            'Create Activity',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _deepGreen,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'What type of activity do you want to create?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Cards row
          Row(
            children: [
              Expanded(
                child: _TypeCard(
                  icon: Icons.person_rounded,
                  label: 'Single Activity',
                  sublabel: 'Solo eco-task\nfor one person',
                  color: _deepGreen,
                  gradientColors: const [Color(0xFF388E3C), Color(0xFF1B5E20)],
                  onTap: () =>
                      Navigator.of(context).pop(ActivityTypeChoice.single),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _TypeCard(
                  icon: Icons.groups_rounded,
                  label: 'Group Event',
                  sublabel: 'Community event\nwith multiple people',
                  color: const Color(0xFF0D47A1),
                  gradientColors: const [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  onTap: () =>
                      Navigator.of(context).pop(ActivityTypeChoice.group),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Cancel
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.45),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Individual card ──────────────────────────────────────────────────────

class _TypeCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_TypeCard> createState() => _TypeCardState();
}

class _TypeCardState extends State<_TypeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 14),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                widget.sublabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11.5,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
