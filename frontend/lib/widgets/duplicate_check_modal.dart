import 'package:flutter/material.dart';
import '../services/activity_duplicate_service.dart';

// ─── Return value from the modal ─────────────────────────────────────────────

enum DuplicateAction { proceedCreate, joinExisting, cancel }

class DuplicateCheckResult2 {
  final DuplicateAction action;
  final NearbyActivity? selectedActivity; // set when action == joinExisting

  const DuplicateCheckResult2({
    required this.action,
    this.selectedActivity,
  });
}

// ─── Entry point ─────────────────────────────────────────────────────────────

/// Shows the duplicate-check bottom sheet.
/// Returns a [DuplicateCheckResult2] describing what the user chose.
Future<DuplicateCheckResult2?> showDuplicateCheckModal(
  BuildContext context, {
  required DuplicateCheckResult checkResult,
}) {
  return showModalBottomSheet<DuplicateCheckResult2>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DuplicateCheckModal(checkResult: checkResult),
  );
}

// ─── Modal widget ─────────────────────────────────────────────────────────────

class _DuplicateCheckModal extends StatelessWidget {
  static const Color _deepGreen  = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);
  static const Color _softGreen  = Color(0xFFA5D6A7);
  static const Color _surface    = Color(0xFFF5FBF4);

  final DuplicateCheckResult checkResult;
  const _DuplicateCheckModal({required this.checkResult});

  @override
  Widget build(BuildContext context) {
    final isHardBlock = checkResult.isHardBlock;

    return DraggableScrollableSheet(
      initialChildSize: 0.60,
      maxChildSize: 0.92,
      minChildSize: 0.40,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Icon(
                    isHardBlock ? Icons.block : Icons.warning_amber_rounded,
                    color: isHardBlock ? Colors.red.shade700 : Colors.orange.shade700,
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isHardBlock
                          ? 'Duplicate Activity Detected'
                          : 'Similar Activities Nearby',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _deepGreen,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black45),
                    onPressed: () => Navigator.of(context).pop(
                      const DuplicateCheckResult2(action: DuplicateAction.cancel),
                    ),
                  ),
                ],
              ),
            ),
            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Text(
                isHardBlock
                    ? 'An identical activity already exists at this location. Creating a duplicate is not allowed.'
                    : 'We found ${checkResult.nearby.length} similar activit${checkResult.nearby.length == 1 ? 'y' : 'ies'} nearby. Review before creating a new one.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ),
            const Divider(height: 16),
            // List of nearby activities
            Expanded(
              child: ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: checkResult.nearby.length,
                itemBuilder: (_, i) =>
                    _NearbyActivityCard(activity: checkResult.nearby[i]),
              ),
            ),
            // Action buttons
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isHardBlock)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(
                            const DuplicateCheckResult2(
                              action: DuplicateAction.proceedCreate,
                            ),
                          ),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Create Anyway (Different Activity)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _deepGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(
                          const DuplicateCheckResult2(action: DuplicateAction.cancel),
                        ),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Cancel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _deepGreen,
                          side: const BorderSide(color: _deepGreen),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Nearby activity card ─────────────────────────────────────────────────────

class _NearbyActivityCard extends StatelessWidget {
  static const Color _deepGreen  = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);
  static const Color _softGreen  = Color(0xFFA5D6A7);

  final NearbyActivity activity;
  const _NearbyActivityCard({required this.activity});

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(activity.status);
    final canJoin     = activity.isAvailableToJoin;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _lightGreen, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Expanded(
                  child: Text(
                    activity.titre,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: _deepGreen,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(activity.status),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Location & distance
            Row(
              children: [
                const Icon(Icons.place_outlined, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    activity.localisation ?? 'Unknown location',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  activity.distanceLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: _deepGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            // Worker / similarity info
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  activity.hasAssignedWorker
                      ? Icons.person
                      : Icons.person_outline,
                  size: 14,
                  color: activity.hasAssignedWorker ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  activity.hasAssignedWorker
                      ? 'Already taken by a worker'
                      : 'Available — no worker yet',
                  style: TextStyle(
                    fontSize: 12,
                    color: activity.hasAssignedWorker ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (activity.similarityScore > 0.4) ...[
                  const Spacer(),
                  Text(
                    '${(activity.similarityScore * 100).round()}% match',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            // Join button
            if (canJoin) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(
                    DuplicateCheckResult2(
                      action: DuplicateAction.joinExisting,
                      selectedActivity: activity,
                    ),
                  ),
                  icon: const Icon(Icons.handshake_outlined, size: 18),
                  label: const Text('Participate in this activity instead'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _softGreen,
                    foregroundColor: _deepGreen,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String s) => switch (s) {
        'open'    => const Color(0xFF2E7D32),
        'waiting' => Colors.orange,
        'in_progress' => Colors.blue,
        _         => Colors.grey,
      };

  String _statusLabel(String s) => switch (s) {
        'open'        => 'Open',
        'waiting'     => 'Pending',
        'in_progress' => 'In Progress',
        _             => s,
      };
}
