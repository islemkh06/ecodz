import 'package:flutter/material.dart';
import '../services/user_service.dart';

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

class _ActivityTypeSheet extends StatefulWidget {
  const _ActivityTypeSheet();

  @override
  State<_ActivityTypeSheet> createState() => _ActivityTypeSheetState();
}

class _ActivityTypeSheetState extends State<_ActivityTypeSheet> {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _surface = Color(0xFFF5FBF4);

  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    _userProfile = UserService.instance.profile;
  }

  /// Checks if user can create a specific activity type
  bool _canCreateType(String activityType) {
    final level = _userProfile?.level ?? 1;
    
    if (level == 1) return false; // Level 1: cannot create anything
    if (level == 2 && activityType == 'group') return false; // Level 2: no groups
    return true; // Level 2+: single activities, Level 3+: both
  }

  /// Gets the error message for why a type is disabled
  String _getDisabledReason(String activityType) {
    final level = _userProfile?.level ?? 1;
    
    if (level == 1) {
      return 'Reach Level 2 (Sprout) to create activities';
    }
    if (level == 2 && activityType == 'group') {
      return 'Reach Level 3 (Sapling) to create group events';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final userLevel = _userProfile?.level ?? 1;
    final canCreateSingle = _canCreateType('single');
    final canCreateGroup = _canCreateType('group');
    
    // Level 1 can't create anything
    if (userLevel == 1) {
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
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Create Activity',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: _deepGreen,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.orange, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Level 2 Required',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'You must reach Level 2 (Sprout) to create activities.\nComplete some validation votes to gain XP!',
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 12,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Current Level: ${_userProfile?.levelTitle} (${_userProfile?.xp ?? 0} XP)',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
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

          // Cards row (or single card for level 2)
          if (canCreateSingle && canCreateGroup)
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
            )
          else if (canCreateSingle)
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
                    sublabel: 'Locked - Reach Level 3',
                    color: Colors.grey,
                    gradientColors: const [Color(0xFFBDBDBD), Color(0xFF9E9E9E)],
                    onTap: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _getDisabledReason('group'),
                          ),
                          backgroundColor: Colors.orange.shade700,
                        ),
                      );
                    },
                    disabled: true,
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
  final bool disabled;

  const _TypeCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.gradientColors,
    required this.onTap,
    this.disabled = false,
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
      onTapDown: widget.disabled ? null : (_) => _ctrl.forward(),
      onTapUp: widget.disabled
          ? null
          : (_) {
              _ctrl.reverse();
              widget.onTap();
            },
      onTapCancel: widget.disabled ? null : () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Opacity(
          opacity: widget.disabled ? 0.6 : 1.0,
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
                  color: widget.color.withValues(
                    alpha: widget.disabled ? 0.15 : 0.35,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.icon,
                        color: Colors.white,
                        size: 34,
                      ),
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
                if (widget.disabled)
                  Positioned.fill(
                    child: Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.lock,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
