import 'package:flutter/material.dart';

import '../pages/group_activity_create_page.dart';
import '../widgets/activity_type_selection_modal.dart';
import '../widgets/create_activity_modal.dart';

/// Opens the activity-type bottom sheet and routes to the correct creation flow.
/// Returns true if an activity was successfully created.
Future<bool> openCreateActivitySheet(
  BuildContext context, {
  VoidCallback? onCreated,
}) async {
  final choice = await showActivityTypeSelectionModal(context);
  if (!context.mounted || choice == null) return false;

  if (choice == ActivityTypeChoice.single) {
    await showDialog<void>(
      context: context,
      builder: (_) => CreateActivityModal(
        onActivityCreated: onCreated ?? () {},
      ),
    );
    return true;
  } else {
    // Group event creation page
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const GroupActivityCreatePage()),
    );
    if (created == true) onCreated?.call();
    return created ?? false;
  }
}

/// Builds the standardized green "+" FAB used across all pages.
Widget buildGlobalFab(BuildContext context, {VoidCallback? onCreated}) {
  return GestureDetector(
    onTap: () => openCreateActivitySheet(context, onCreated: onCreated),
    child: Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFFE8F7E7), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4427502E),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 34),
    ),
  );
}
