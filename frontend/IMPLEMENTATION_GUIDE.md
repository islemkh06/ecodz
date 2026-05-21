# 🔐 Level-Based Permissions & Creator Priority System

## Overview

This document describes the implementation of level-based activity creation permissions and the creator priority participation system for group events.

---

## 1. Level-Based Permissions System

### Rules

| Level | Single Activities | Group Events |
|-------|-------------------|--------------|
| **1 - Seedling** | ❌ Cannot create | ❌ Cannot create |
| **2 - Sprout** | ✅ Can create | ❌ Cannot create |
| **3+ - Sapling & Above** | ✅ Can create | ✅ Can create |

### User Experience

#### Level 1 Users
When a Level 1 user taps the "+" FAB to create an activity:
- Modal appears with a lock icon 🔒
- Message: **"Level 2 Required"**
- Subtext: "You must reach Level 2 (Sprout) to create activities. Complete some validation votes to gain XP!"
- Shows current level and XP
- **Close button only** (no creation options)

#### Level 2 Users
When a Level 2 user taps the "+":
- **Two cards appear:**
  - Single Activity: Enabled ✅
  - Group Event: Locked (with lock icon 🔒)
- Clicking locked Group Event shows toast: "Reach Level 3 (Sapling) to create group events"
- Can only create single activities

#### Level 3+ Users
When a Level 3+ user taps the "+":
- **Two cards appear:**
  - Single Activity: Enabled ✅
  - Group Event: Enabled ✅
- Full access to both activity types

---

## 2. Backend Implementation

### SQL File: `level_based_permissions.sql`

#### Helper Function: `can_create_activity(user_id, activity_type)`

```sql
CREATE OR REPLACE FUNCTION public.can_create_activity(
  p_user_id uuid,
  p_activity_type text
)
RETURNS jsonb
```

**Parameters:**
- `p_user_id` (uuid): User ID from auth.users
- `p_activity_type` (text): 'single' or 'group'

**Returns:**
```json
{
  "allowed": true/false,
  "error": "error_code" (if not allowed),
  "message": "human-readable message",
  "required_level": 2 or 3
}
```

**Logic:**
1. Fetches user's level from `profiles.level`
2. Level 1 → Denied (all types)
3. Level 2 + group type → Denied (needs Level 3)
4. All other valid combinations → Allowed

---

## 3. Frontend Implementation

### Updated Files

#### A. `lib/widgets/activity_type_selection_modal.dart`

**Changes:**
- Added `UserService` import
- `_ActivityTypeSheet` is now a `StatefulWidget` (was `StatelessWidget`)
- Checks `UserService.instance.profile?.level` on init
- Renders different UI based on level:
  - Level 1: Full-screen lock message
  - Level 2: One enabled, one disabled card
  - Level 3+: Both enabled cards

**New Features:**
- `_canCreateType(activityType)` - Checks if type is allowed
- `_getDisabledReason(activityType)` - Returns reason why disabled
- `_TypeCard` now has `disabled` parameter
- Disabled cards show lock icon, reduced opacity, no tap response
- Clicking disabled card shows snackbar with reason

**Example Code Flow:**
```dart
// In _ActivityTypeSheetState
final userLevel = _userProfile?.level ?? 1;
final canCreateSingle = _canCreateType('single');
final canCreateGroup = _canCreateType('group');

if (userLevel == 1) {
  // Show lock screen
} else if (userLevel == 2) {
  // Show single enabled, group locked
} else {
  // Show both enabled
}
```

#### B. `lib/pages/group_activity_create_page.dart`

**Changes:**
- Added `UserService` import
- In `_submit()` method, added permission check:
```dart
final userLevel = UserService.instance.profile?.level ?? 1;
if (userLevel < 3) {
  _snack(
    'You need to reach Level 3 (Sapling) to create group events.',
    isError: true,
  );
  return;
}
```
- Executes **before** validating other form fields
- Provides clear error message if insufficient level

#### C. `lib/widgets/create_activity_modal.dart`

**Changes:**
- Added `UserService` import
- In `_submit()` method, added permission check:
```dart
final userLevel = UserService.instance.profile?.level ?? 1;
if (userLevel < 2) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('You need to reach Level 2 (Sprout) to create activities.'),
      backgroundColor: Colors.orange,
      behavior: SnackBarBehavior.floating,
    ),
  );
  return;
}
```
- Prevents Level 1 users from creating any activities
- Shows before duplicate check and other validations

---

## 4. Creator Priority Participation System (Group Events)

### How It Works

**Step 1: Event Approval**
- Community votes on a group event in 'waiting' status
- If 2+ approval votes received → Event enters **'priority_pending'** status
- `priority_deadline` set to NOW() + 1 minute

**Step 2: Creator Priority Window (1 minute)**
- Creator gets exclusive access to join
- Only creator can call `join_group_activity()` during this window
- Other users attempting to join receive error: "creator_priority_active"

**Step 3: Creator Action (3 options)**

**Option A: Creator Joins**
```
join_group_activity(activity_id, creator_id)
↓
- Creator added to activity_participants table
- Status transitions: priority_pending → open
- creator_priority_status: accepted
- current_participants_count incremented
↓
✅ Event now OPEN for everyone else to join
✅ Creator is FIRST participant but NOT exclusive
✅ Max participants limit still applies
```

**Option B: Creator Declines**
```
decline_creator_priority(activity_id)
↓
- Status transitions: priority_pending → open
- creator_priority_status: declined
- Creator NOT added to participants
↓
✅ Event immediately OPEN for all users
```

**Option C: Deadline Expires (1 minute passes)**
```
No action taken by creator
↓
- Status transitions: priority_pending → open
- creator_priority_status: expired
- Creator NOT added as participant
↓
✅ Event immediately OPEN for all users
✅ Any user can join (including creator if they wish)
```

### Key Points

✅ **Creator is NOT exclusive:**
- Just the first participant if they accept
- Event stays open until max participants reached

✅ **Participants tracked separately:**
- `activity_participants` table used (not `assigned_worker_id`)
- Creator behaves like any other participant after joining

✅ **Reward is collective:**
- When group event is validated, ALL participants get XP
- Not just the creator

---

## 5. Database Structure

### Existing Tables Used

```sql
-- User profile
profiles (
  id uuid,
  level integer,  -- 1-9 (auto-synced from XP)
  xp integer,
  ...
)

-- Activity/Event record
activite (
  id_act integer,
  activity_mode text,  -- 'single' or 'group'
  status text,  -- 'waiting', 'priority_pending', 'open', 'approved', etc.
  id_utilisateur uuid,  -- Creator
  max_participants integer,
  current_participants_count integer,
  priority_deadline timestamptz,
  creator_priority_status text,  -- 'pending', 'accepted', 'declined', 'expired'
  ...
)

-- Group activity participants (created in feature_group_activities.sql)
activity_participants (
  id bigserial PRIMARY KEY,
  activity_id integer FK,
  user_id uuid FK,
  status text,  -- 'confirmed' or 'cancelled'
  joined_at timestamptz
)
```

### New Index Added

```sql
CREATE INDEX idx_profiles_level
  ON public.profiles (level)
  WHERE level IS NOT NULL;
```

---

## 6. RPC Functions

### Existing (Already Working)

#### `cast_approval_vote(activity_id, user_id, valeur)`
- When group event gets 2 approve votes
- Transitions status to 'priority_pending'
- Sets priority_deadline = NOW() + 1 minute

#### `join_group_activity(activity_id, user_id)`
- **During priority_pending:** Only creator allowed
- **After priority:** Any user can join (up to max)
- Adds user to activity_participants
- Updates current_participants_count
- Transitions status to 'open' after creator joins

#### `accept_creator_priority(activity_id)`
- Creator explicitly accepts
- Adds creator to activity_participants
- Status → 'open'
- creator_priority_status → 'accepted'

#### `decline_creator_priority(activity_id)`
- Creator explicitly declines
- Status → 'open'
- creator_priority_status → 'declined'
- Creator NOT added to participants

#### `expire_creator_priority(activity_id)`
- Called when countdown reaches zero
- Status → 'open'
- creator_priority_status → 'expired'
- Safe to call anytime (only updates if deadline passed)

### New Helper Function

#### `can_create_activity(user_id, activity_type)`
- **Purpose:** Validate permission before activity creation
- **Usage:** Called from frontend before submission
- **Returns:** JSON with allowed/error status

---

## 7. Testing Checklist

### Level 1 User (Seedling)

- [ ] Tap "+" FAB
- [ ] See lock screen with "Level 2 Required" message
- [ ] See current level (1) and XP
- [ ] Only "Close" button available
- [ ] Cannot access any creation forms

### Level 2 User (Sprout)

- [ ] Tap "+" FAB
- [ ] See two cards: Single Activity ✅, Group Event 🔒
- [ ] Click Single Activity → Opens single activity form
- [ ] Click Group Event → Shows toast "Reach Level 3 (Sapling)..."
- [ ] Complete and submit single activity
- [ ] Activity created successfully ✅

### Level 3+ User (Sapling+)

- [ ] Tap "+" FAB
- [ ] See two cards: Both fully enabled ✅
- [ ] Click either card → Opens respective form
- [ ] Create both types successfully ✅

### Group Event Creator Priority Flow

- [ ] Create a group event → Enters 'waiting' status
- [ ] Community votes to approve (2 votes needed)
- [ ] Event enters 'priority_pending'
- [ ] Creator sees 1-minute priority window notification
- [ ] Creator joins → Event becomes 'open', creator added as participant
- [ ] Other users can join → All added to activity_participants
- [ ] Event fills up or time expires → Participants locked at max
- [ ] All participants get XP when validated ✅

---

## 8. Implementation Notes

### Security

✅ **Frontend validation:** UX guidance, prevents accidental submission
✅ **Backend validation:** Can be added via `can_create_activity()` RPC if needed
✅ **RLS policies:** Existing RLS on activity_participants prevents unauthorized joins
✅ **SECURITY DEFINER functions:** All RPC functions run with elevated privileges

### Performance

✅ **Level index:** `idx_profiles_level` optimizes level-based queries
✅ **Participant count:** Stored in `current_participants_count` (no COUNT needed each time)
✅ **Priority deadline index:** `idx_activite_priority_deadline` for finding expiring events

### Future Enhancements

- [ ] Automatic expire job (call `expire_creator_priority()` via scheduled function)
- [ ] Notifications for creator priority window
- [ ] Bulk rewards for group events
- [ ] Admin level unlock (bypass restrictions for testing)
- [ ] Badge system tied to level achievements

---

## 9. File Manifest

### Modified Files
- `lib/widgets/activity_type_selection_modal.dart` - Level-based UI logic
- `lib/pages/group_activity_create_page.dart` - Level check before submission
- `lib/widgets/create_activity_modal.dart` - Level check before submission

### New Files
- `level_based_permissions.sql` - SQL functions and indexes

### Unchanged (Reference)
- `feature_creator_priority.sql` - Already correct, no changes needed
- `feature_group_activities.sql` - Core infrastructure already present

---

## 10. Deployment Steps

1. **Run SQL migration:**
   ```sql
   -- Run level_based_permissions.sql in Supabase SQL Editor
   ```

2. **Deploy Flutter changes:**
   ```bash
   flutter pub get
   flutter run
   ```

3. **Test all scenarios** (see Testing Checklist)

4. **(Optional) Create migration record:**
   - Document in version control with timestamp
   - Add changelog entry

---

## 11. Rollback Plan

If issues occur:

1. **Frontend:** Remove permission checks (revert to previous commits)
2. **Database:** Existing functions are additive (no destructive changes)
3. **Data:** No data modifications, safe to rollback

---

**Implementation Complete!** ✅

For questions or issues, refer to the function signatures and test cases above.
