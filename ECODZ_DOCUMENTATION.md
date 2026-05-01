# EcoDz — Complete Application Documentation
> **Version 1.0.0** | Stack: Flutter + Supabase | Date: April 2026

---

## Table of Contents
1. [Application Overview](#1-application-overview)
2. [Technology Stack](#2-technology-stack)
3. [Application Architecture](#3-application-architecture)
4. [Screens & Navigation](#4-screens--navigation)
5. [Core Feature: Activity Lifecycle](#5-core-feature-activity-lifecycle)
6. [Map Integration](#6-map-integration)
7. [Voting System](#7-voting-system)
8. [Gamification System](#8-gamification-system)
9. [Database Schema & Relations](#9-database-schema--relations)
10. [Backend — RPC Functions](#10-backend--rpc-functions)
11. [Security Model (RLS)](#11-security-model-rls)
12. [File Storage](#12-file-storage)
13. [Notifications](#13-notifications)
14. [Questions for the Meeting](#14-questions-for-the-meeting)

---

## 1. Application Overview

**EcoDz** is a community-driven eco-action mobile application built for Algerian users. It enables citizens to:

- **Report** environmental problems (pollution, illegal dumping, degraded green spaces, etc.) by creating geo-tagged activities.
- **Volunteer** to physically resolve those problems (pick up trash, plant trees, clean water sources).
- **Validate** each other's work through a decentralized community voting system.
- **Earn XP and level up** in a gamification system that rewards real-world environmental action.

The philosophy is: *report → vote to approve → someone does the work → community validates → XP is rewarded.*

---

## 2. Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Frontend** | Flutter (Dart) | Cross-platform mobile + desktop app |
| **Backend** | Supabase (PostgreSQL) | Database, Auth, Storage, RPC functions |
| **Authentication** | Supabase Auth (email/password) | User registration & login |
| **Database** | PostgreSQL (via Supabase) | All relational data |
| **Storage** | Supabase Storage (`activity_image` bucket) | Before/after proof photos |
| **Map Tiles** | OpenStreetMap (via `flutter_map`) | Map display and navigation |
| **Geocoding** | Nominatim API (OSM) | Forward & reverse geocoding (free, no API key) |
| **Device GPS** | `geolocator` package | Detect user's physical location |
| **Image Picking** | `image_picker` package | Camera & gallery access |

**Key Flutter Packages:**
```
supabase_flutter: ^2.12.2   — Supabase client (DB, Auth, Storage)
flutter_map: ^8.2.2         — Render OpenStreetMap tiles + markers
latlong2: ^0.9.1            — LatLng coordinate model
geolocator: ^13.0.2         — GPS location
geocoding: ^3.0.0           — Device-level geocoding
http: ^1.2.0                — HTTP requests (Nominatim calls)
image_picker: ^1.1.2        — Photo upload
```

---

## 3. Application Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Flutter App (Client)               │
│                                                     │
│  main.dart ──► LoginPage ──► HomePage               │
│                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐ │
│  │  Home    │ │ Activity │ │  Search  │ │Profile │ │
│  │  Feed    │ │  Page    │ │  / Map   │ │  Page  │ │
│  └──────────┘ └──────────┘ └──────────┘ └────────┘ │
│       ▼              ▼           ▼                  │
│  ┌──────────────────────────────────────────────┐   │
│  │         Services & Models Layer              │   │
│  │  UserService (singleton)  LevelSystem        │   │
│  └──────────────────────────────────────────────┘   │
│       ▼              ▼           ▼                  │
│  ┌──────────────────────────────────────────────┐   │
│  │       Supabase Flutter SDK                   │   │
│  │  .from() queries   .rpc()   .storage         │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
              │  HTTPS  │
┌─────────────────────────────────────────────────────┐
│              Supabase Cloud (Backend)               │
│                                                     │
│  ┌────────────┐  ┌──────────┐  ┌─────────────────┐ │
│  │ PostgreSQL │  │ Auth     │  │ Storage Bucket  │ │
│  │ (Tables +  │  │ (JWT)    │  │ activity_image  │ │
│  │  RPC fns)  │  │          │  │                 │ │
│  └────────────┘  └──────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────┘
              │  HTTP  │
┌─────────────────────────────────────────────────────┐
│           Nominatim / OpenStreetMap                 │
│        (reverse & forward geocoding, free)          │
└─────────────────────────────────────────────────────┘
```

---

## 4. Screens & Navigation

The app uses a **bottom navigation bar** with 4 tabs, plus a central **FAB (Floating Action Button)** that opens the "Create Activity" modal from any tab.

### 4.1 Login Page (`login.dart`)
- Email + password form, "Remember me" toggle
- Calls `supabase.auth.signInWithPassword()`
- On success → navigates to `HomePage`
- On error → shows snackbar (email not confirmed, wrong credentials, network error)
- Links to Sign Up page

### 4.2 Sign Up Page (`signup.dart`)
- Full name, email, phone, password fields
- Calls `supabase.auth.signUp()` with metadata
- `handle_new_user` DB trigger auto-creates a `profiles` row on signup
- Users must confirm email before logging in

### 4.3 Home Page (`home.dart`) — Tab 0
- **Top Header**: User avatar, name, XP level badge + XP progress bar
- **Search bar**: Filters activities by title, location, date, XP
- **Category chips**: Horizontal scroll of all categories loaded from `type_activite` table
- **Activity cards**: Feed of activities with status `open` or `approved`, showing title, location, date, XP reward, and proof photo thumbnail
- **FAB**: Opens `CreateActivityModal`

### 4.4 Activity Page (`activity.dart`) — Tab 1
Two top-level sections: **Community** and **My Work**

**Community Section** has 3 sub-tabs:
| Sub-tab | Description |
|---|---|
| **Approval** | Activities in `waiting` status — community votes to approve/reject |
| **Validation** | Activities in `pending_validation` — community votes to confirm work was done |
| **My History** | Activities the current user has worked on (completed) |

**My Work Section** has 4 sub-tabs:
| Sub-tab | Description |
|---|---|
| **Priority** | Activity approved and user (creator) has a 2-minute window to self-accept |
| **Available** | Activities in `open` status the user can join |
| **Active** | Activities currently assigned to the user (`in_progress`) |
| **Done** | Activities the user has completed |

### 4.5 Search / Map Page (`search.dart`) — Tab 2
- Full-screen interactive map (OpenStreetMap via `flutter_map`)
- All open/approved activities shown as **map markers**
- Category filter chips at the top
- Bottom sheet listing nearby activities
- User GPS detection button to center map on current position
- Clicking a marker or list item navigates to `ActivityDetailPage`

### 4.6 Profile Page (`profile.dart`) — Tab 3
- User avatar, name, email
- XP level + progress bar
- Stats: Completed activities count, In-Progress count, Reputation score
- Account settings sections (navigation placeholders)
- Logout button

### 4.7 Activity Detail Page (`activity_detail.dart`)
- Full information: title, description, location, category, difficulty level, XP reward
- Organizer card (name + reputation)
- Proof photos gallery (before images)
- Vote/Rating display
- Validation status (if available)
- Action buttons change based on `status` and the user's role:
  - Creator on `priority_pending` → Accept / Decline priority
  - Any user on `open` → Join activity
  - Assigned worker on `in_progress` → Submit Completion
  - Community member on `pending_validation` → Cast Completion Vote

### 4.8 Create Activity Modal (`create_activity_modal.dart`)
- Title, description, XP reward fields
- Category dropdown (from `type_activite`)
- Difficulty level dropdown (from `niveau_activite`) — shows XP range
- **Location picker** (taps into full-screen map — see Section 6)
- Before-photo upload (image picker → Supabase Storage)
- On submit: inserts into `activite` table, uploads image to `activity_image` bucket, inserts into `preuve` table

### 4.9 Work Completion Page (`work_completion_page.dart`)
- Worker uploads multiple "after" photos (camera or gallery)
- Photos uploaded to `activity_image` Supabase Storage bucket
- Photo URLs inserted into `preuve` table as type `'apres'`
- Calls `submit_work_completion` RPC → sets status to `pending_validation`

### 4.10 User Profile Page (`user_profile.dart`)
- Public profile view for other users

---

## 5. Core Feature: Activity Lifecycle

Every activity passes through a strict status machine enforced by **PostgreSQL RPC functions** (SECURITY DEFINER — cannot be bypassed by the client).

```
                    ┌──────────┐
                    │  User    │
                    │ Creates  │
                    └────┬─────┘
                         │ INSERT activite (status='waiting')
                         ▼
                   ┌───────────┐
                   │  waiting  │ ◄── Community approves/rejects
                   └─────┬─────┘    (2 votes required)
               ┌─────────┴──────────┐
        Reject (majority)      Approve (majority)
               │                    │
               ▼                    ▼
         ┌──────────┐    ┌─────────────────────┐
         │ rejected │    │  priority_pending   │
         └──────────┘    │  (2-minute window)  │
                         └──────────┬──────────┘
                     ┌──────────────┴──────────────┐
               Creator Accepts              Creator Declines
               (or self-assigns)           (or timer expires)
                     │                             │
                     ▼                             ▼
              ┌─────────────┐               ┌──────────┐
              │ in_progress │               │   open   │ ◄── Any user can Join
              └──────┬──────┘               └────┬─────┘
                     │                           │ join_open_activity()
         Worker submits completion               │
         (uploads after photos)                 ▼
                     │                    ┌─────────────┐
                     ▼                    │ in_progress │
              ┌──────────────────┐        └─────────────┘
              │ pending_          │
              │ validation       │ ◄── Community validation votes
              └──────┬───────────┘    (min 2, max 5 votes)
             ┌───────┴──────────┐
         Approved            Rejected
        (majority)           (majority)
             │                    │
             ▼                    ▼
      ┌───────────┐        ┌──────────┐
      │ completed │        │   open   │ (reassigned, back to pool)
      │ + XP      │        │          │
      │ awarded   │        └──────────┘
      └───────────┘
```

### Activity Status Values

| Status | Meaning |
|---|---|
| `waiting` | Newly submitted, awaiting 2 community approval votes |
| `priority_pending` | Approved — creator has 2 minutes to self-accept as worker |
| `open` | Available for any user to join as worker |
| `in_progress` | A specific worker is assigned and working |
| `pending_validation` | Worker submitted completion — awaiting community validation |
| `completed` | Work validated, XP awarded |
| `rejected` | Community rejected the activity itself (not the work) |
| `approved` *(legacy)* | Old status, equivalent to `open` |

---

## 6. Map Integration

The map is powered by **OpenStreetMap (OSM)** tiles via the `flutter_map` package. No API key is required.

### 6.1 Search Page Map (Browsing)
**File:** `lib/pages/search.dart`

- Renders an interactive `FlutterMap` widget with OSM tile layer
- All activities with valid `latitude` + `longitude` coordinates are rendered as green `CircleMarker` points
- A `MarkerLayer` places tap-able markers with info
- The `MapController` programmatically moves the camera
- User position is detected via `Geolocator.getCurrentPosition()`
- On location detect, camera animates to `LatLng(userLat, userLng)`
- Tapping a marker opens the `ActivityDetailPage`

**Data flow:**
```
Supabase query (activite + type_activite) → List<Map<String,dynamic>>
  → Extract latitude/longitude → LatLng object
  → Render as map markers
```

### 6.2 Location Picker (Creating Activity)
**File:** `lib/widgets/location_picker.dart`

This is a **full-screen interactive map** used during activity creation.

**Features:**
1. **GPS Auto-detect**: Requests location permission → gets current position → places a pin
2. **Map Tap**: User taps anywhere on the map → pin drops at that coordinate
3. **Search Bar**: User types a place name → debounced call to **Nominatim forward geocoding** (`/search` endpoint) → shows dropdown of suggestions → user selects → map animates to that location
4. **Reverse Geocoding**: Any time a pin is placed (by tap or GPS), the app calls **Nominatim** (`/reverse` endpoint) → resolves human-readable address

**Nominatim API Calls:**
```
Forward: GET https://nominatim.openstreetmap.org/search
         ?q=<query>&format=json&limit=5&addressdetails=1

Reverse: GET https://nominatim.openstreetmap.org/reverse
         ?lat=<lat>&lon=<lon>&format=json
```
- 600ms debounce on search to avoid rate-limiting
- User-Agent header set to `ecodz-app/1.0` (required by Nominatim ToS)
- Timeouts set to 8 seconds

**Data saved to database:**
- `localisation` (text): human-readable address string (e.g., "Rue Didouche Mourad, Algiers")
- `latitude` (double): decimal degrees
- `longitude` (double): decimal degrees

**Default map center:** `LatLng(36.7525, 5.0843)` — Béjaïa, Algeria

### 6.3 Map Tile Source
```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.ecodz',
)
```
This is **completely free** and requires no API key. OSM tiles are cached locally by `flutter_map`.

---

## 7. Voting System

All votes are processed **exclusively through RPC functions** (SECURITY DEFINER). The Flutter client calls `.rpc()` and receives a JSON result. Direct table updates are blocked by RLS policies.

### 7.1 Approval Voting (`vote_approbation` table)

**Purpose:** Community decides whether a newly reported activity is legitimate.

**Rules:**
- Exactly **2 votes** are required to decide
- The **creator cannot vote** on their own activity
- Each user can vote **only once** (UNIQUE constraint)
- Vote value: `1` = approve, `-1` = reject
- Simple majority of 2 decides (1 approve + 1 reject = reject wins by default)

**RPC:** `cast_approval_vote(p_act_id, p_user_id, p_valeur)`

**Outcomes after 2nd vote:**
- Approvals > Rejections → `priority_pending` + 2-minute creator notification
- Rejections ≥ Approvals → `rejected`

### 7.2 Completion Voting (`vote_completion` table)

**Purpose:** Community verifies that work was actually done.

**Rules:**
- Minimum **2 votes**, maximum **5 votes** to decide
- The **assigned worker cannot vote** on their own completion
- Each user votes **only once** (UNIQUE constraint)
- Approving voters can optionally propose an **XP reward amount**
- If majority approves: XP = `AVG(xp_proposal)` from all YES votes → awarded to worker
- If majority rejects: activity returns to `open` status (reassigned), completion votes cleared

**RPC:** `cast_completion_vote(p_act_id, p_user_id, p_approve, p_xp_proposal?)`

**Outcomes:**
- Approve > Reject → `completed`, XP awarded to worker, `profiles.xp += avg_xp`
- Reject > Approve → `open` (reset for reassignment), `vote_completion` rows deleted

---

## 8. Gamification System

### 8.1 XP (Experience Points)
- Stored in `profiles.xp` (integer, default 0)
- Earned when work is community-validated: `profiles.xp += avg(xp_proposal)`
- XP is **never decremented**

### 8.2 Level Calculation
The `calculate_level(xp)` function exists both in **PostgreSQL** and mirrored exactly in **Dart** (`LevelSystem` class).

| Level | XP Range | Title |
|---|---|---|
| 1 | 0 – 30 | Seedling |
| 2 | 31 – 60 | Sprout |
| 3 | 61 – 120 | Sapling |
| 4 | 121 – 210 | Tree |
| 5 | 211 – 330 | Forest Guardian |
| 6 | 331 – 480 | Eco Warrior |
| 7 | 481 – 660 | Earth Defender |
| 8 | 661 – 870 | Planet Protector |
| 9+ | 871+ | Legend |

Each range grows by +30 XP after level 2 (L1/L2 = 30 each, L3 = 60, L4 = 90, etc.)

### 8.3 Auto Level Sync (Database Trigger)
```sql
TRIGGER trg_sync_level BEFORE UPDATE OF xp ON profiles
→ EXECUTE sync_level_from_xp()
→ NEW.level := calculate_level(NEW.xp)
```
Level is **always consistent** with XP — cannot be manually set.

### 8.4 Reputation
- `profiles.reputation` integer — currently stored but UI displays it
- Intended for community standing score (separate from XP)

### 8.5 Badges (`badge` table)
- Defined with `nom`, `condition_badge`, `icon`
- **Not yet linked** to profiles via a join table (future feature)

### 8.6 Priority Window (Incentive Mechanic)
When an activity is approved, the creator gets a **2-minute exclusive window** to self-assign as the worker (`priority_pending` status). If they accept: status → `in_progress`, assigned to creator. If they decline or time expires: status → `open` (any user can join). This rewards engaged reporters.

---

## 9. Database Schema & Relations

### 9.1 Entity-Relationship Overview

```
auth.users (Supabase Auth)
    │ 1:1 (trigger: handle_new_user)
    ▼
profiles (id uuid PK, full_name, email, phone_number, level, xp, reputation)
    │
    ├──< activite (id_utilisateur FK) — Activities created by user
    │       │
    │       ├── id_type_act FK ──► type_activite (category)
    │       ├── id_niv_act FK ──► niveau_activite (difficulty level)
    │       ├── assigned_worker_id FK ──► profiles (worker)
    │       │
    │       ├──< preuve (before/after photos)
    │       ├──< vote (ratings & comments)
    │       ├──< vote_approbation (approval votes)
    │       ├──< vote_completion (validation votes)
    │       ├──< validation (phase validation records)
    │       ├──< reservation (user participation records)
    │       └──< notification (user notifications)
    │
    ├──< vote (id_utilisateur FK) — Votes cast by user
    ├──< vote_approbation (id_utilisateur FK)
    ├──< vote_completion (id_utilisateur FK)
    ├──< reservation (id_utilisateur FK)
    └──< notification (id_utilisateur FK)
```

### 9.2 Table Definitions

#### `profiles`
```
id              uuid (PK, FK → auth.users.id)
full_name       text NOT NULL
email           text NOT NULL UNIQUE
phone_number    text
level           integer DEFAULT 1          ← auto-synced from xp
xp              integer NOT NULL DEFAULT 0
reputation      integer DEFAULT 0
created_at      timestamptz
```

#### `activite` (core table)
```
id_act          integer (PK, auto-increment)
titre           text                        ← activity title
description     text
localisation    text                        ← human-readable address
latitude        double precision            ← decimal degrees
longitude       double precision            ← decimal degrees
status          text                        ← see lifecycle section
xpfinal         integer                     ← proposed XP reward
datecreation    timestamp DEFAULT now()
id_type_act     integer FK → type_activite
id_utilisateur  uuid FK → profiles          ← creator
id_niv_act      integer FK → niveau_activite
assigned_worker_id uuid FK → profiles       ← worker (SET NULL on delete)
priority_deadline  timestamptz              ← 2-min creator window
completed_at    timestamptz                 ← when worker submitted
```

#### `type_activite` (categories)
```
id_type_act  integer (PK)
nom          text UNIQUE        ← e.g., "Tree Planting", "Beach Cleanup"
icone        text               ← icon name string mapped to Flutter IconData
```

#### `niveau_activite` (difficulty levels)
```
id_niv_act   integer (PK)
description  text               ← e.g., "Beginner", "Intermediate"
xpmin        integer            ← minimum XP to be at this level
xpmax        integer            ← maximum XP at this level
```

#### `preuve` (proof photos)
```
id_preuve    integer (PK)
url          text               ← Supabase Storage public URL
type         text CHECK IN ('avant', 'apres')  ← before/after
timestamp    timestamp DEFAULT now()
id_act       integer FK → activite
```

#### `vote_approbation` (approval votes)
```
id               integer (PK)
id_act           integer FK → activite (CASCADE DELETE)
id_utilisateur   uuid FK → profiles
valeur           integer CHECK IN (1, -1)    ← 1=approve, -1=reject
created_at       timestamptz
UNIQUE (id_act, id_utilisateur)              ← one vote per user per activity
```

#### `vote_completion` (work validation votes)
```
id               integer (PK)
id_act           integer FK → activite (CASCADE DELETE)
id_utilisateur   uuid FK → profiles
approve          boolean                     ← yes/no
xp_proposal      integer CHECK >= 0          ← optional XP to award
created_at       timestamptz
UNIQUE (id_act, id_utilisateur)
```

#### `vote` (ratings/comments, legacy)
```
id_vote          integer (PK)
valeur           integer
type             text CHECK IN ('estimation', 'note')
commentaire      text
id_utilisateur   uuid FK → profiles
id_act           integer FK → activite
```

#### `validation`
```
id_validation    integer (PK)
phase            text CHECK IN ('XP', 'travail')
status           text
moyenne          real
date_validation  timestamp DEFAULT now()
id_act           integer FK → activite
```

#### `reservation`
```
id_reserv        integer (PK)
datedebut        timestamp
date_exp         timestamp
status           text              ← 'active' | 'completed'
id_utilisateur   uuid FK → profiles
id_act           integer FK → activite
```

#### `notification`
```
id_message       integer (PK)
type             text              ← e.g., 'priority_assignment'
id_utilisateur   uuid FK → profiles   ← recipient
message          text
created_at       timestamp DEFAULT now()
is_read          boolean DEFAULT false
id_act           integer FK → activite
```

#### `badge`
```
id_badge         integer (PK)
nom              text
condition_badge  text
icon             text
```

---

## 10. Backend — RPC Functions

All business logic runs in **SECURITY DEFINER** PostgreSQL functions. The client can never directly modify status fields.

| Function | Trigger | Effect |
|---|---|---|
| `handle_new_user()` | AFTER INSERT on `auth.users` trigger | Auto-creates `profiles` row for every new signup |
| `calculate_level(xp)` | Called by trigger | Returns integer level from XP (immutable, pure) |
| `sync_level_from_xp()` | BEFORE UPDATE OF xp on `profiles` trigger | Auto-updates `level` whenever `xp` changes |
| `cast_approval_vote(act_id, user_id, value)` | Called from Flutter app | Validates + inserts approval vote; decides outcome after 2nd vote |
| `accept_priority_assignment(act_id, user_id)` | Called from Flutter app | Creator accepts 2-min window → `in_progress` |
| `decline_priority_assignment(act_id, user_id)` | Called from Flutter app | Creator declines → `open` |
| `join_open_activity(act_id, user_id)` | Called from Flutter app | Any user joins → `in_progress`, assigns `assigned_worker_id` |
| `submit_work_completion(act_id, user_id)` | Called from Flutter app | Worker submits → `pending_validation`, sets `completed_at` |
| `cast_completion_vote(act_id, user_id, approve, xp_proposal?)` | Called from Flutter app | Validates + inserts completion vote; on approve → XP awarded; on reject → back to `open` |
| `expire_priority_assignments()` | Called periodically | Moves expired `priority_pending` → `open` |
| `join_activity(act_id, user_id)` | Called from Flutter app | Create reservation record + join activity |

---

## 11. Security Model (RLS)

Row Level Security is enabled on all major tables. The policies are:

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `activite` | All authenticated users | Creator only (`id_utilisateur = auth.uid()`) | Via RPC only | Via RPC only |
| `profiles` | All authenticated | Via trigger (handle_new_user) | Own row only | — |
| `preuve` | All authenticated | Creator of linked activity | — | — |
| `type_activite` | All authenticated | Admin only | — | — |
| `niveau_activite` | All authenticated | Admin only | — | — |
| `vote_approbation` | All authenticated | Via RPC only | — | — |
| `vote_completion` | All authenticated | Own votes only | — | — |
| `reservation` | Own reservations | Own reservations | Own reservations | — |
| `notification` | Own notifications | Via RPC only | Own (mark read) | — |

**Key principle:** No client can directly change `activite.status` or `activite.assigned_worker_id`. All such changes must go through RPC functions which validate business rules with row-level locks to prevent race conditions.

---

## 12. File Storage

**Bucket name:** `activity_image` (public bucket)

**Upload path pattern:**
```
Before photo: {user_id}/{activity_id}_{timestamp}.{ext}
After photo:  apres_{activity_id}_{timestamp}_{index}.{ext}
```

**Flow:**
1. User picks image from gallery or camera (`image_picker`)
2. App reads bytes from file
3. Calls `supabase.storage.from('activity_image').uploadBinary(path, bytes)`
4. Gets public URL: `supabase.storage.from('activity_image').getPublicUrl(path)`
5. Inserts URL into `preuve` table with `type = 'avant'` or `'apres'`

**Retry logic (work completion):** Up to 3 upload attempts per photo with 500ms pause between retries.

---

## 13. Notifications

Notifications are sent **within RPC functions** via direct `INSERT INTO notification` statements.

**Current notification trigger:**
- When a vote makes an activity `priority_pending` → notification sent to **creator** with message: *"Your activity was approved! You have 2 minutes to accept as the assigned worker."*

**Notification record fields:** `type`, `message`, `id_utilisateur` (recipient), `id_act`, `is_read`, `created_at`

The `notification` table supports push to any user but **no real push notification service** (FCM/APNs) is currently integrated — notifications are read by polling the DB.

---

## 14. Questions for the Meeting

### Architecture & Scalability
1. Should the app target Android only, or also iOS and Web from day one? (Current build config supports all three.)
2. The map uses free Nominatim/OSM — is there a scale concern? Nominatim has a rate limit of 1 req/sec. Should we switch to a paid geocoding provider (Google Maps, Mapbox) at scale?
3. The `expire_priority_assignments()` function needs to be called periodically — currently it's called from the app at startup. Should this be automated via a `pg_cron` job on Supabase instead?
4. The 2-minute priority window — is this the right duration? What happens if the user is offline?

### Business Logic & UX
5. The approval voting requires exactly **2 votes** — is this enough to prevent spam/fake activities? Should we increase the quorum?
6. Who can create activities? Currently **any authenticated user**. Should there be a moderation role or minimum level requirement?
7. What happens if no one joins an `open` activity? Should there be an expiration / archiving mechanism?
8. The XP for completed work is determined by **community voters' proposals** — what if no voter provides an XP proposal? Currently defaults to 0 XP awarded.
9. The **creator can also be the worker** (they get priority to self-assign). Is this intended? It means one person reports AND does the work alone without real community involvement.

### Database & Data Integrity
10. The `badge` table exists but there is **no user-badge join table** — badges cannot currently be awarded to users. Is the badge feature planned for this sprint?
11. The `reservation` table exists alongside `assigned_worker_id` on `activite`. Are these parallel or redundant? `reservation` seems unused by the main activity flow (which uses `assigned_worker_id` directly).
12. The `vote` table (type: `'estimation'` | `'note'`) appears separate from `vote_approbation` and `vote_completion` — what is this table used for? Legacy or future feature?
13. The `validation` table (phase: `'XP'` | `'travail'`) also appears disconnected from the current RPC-driven flow — is this a legacy table or an upcoming feature?
14. Should `profiles.reputation` be auto-calculated from completed activities, or manually managed? Currently it is stored as a static integer.

### Security
15. The Supabase `anonKey` is **hardcoded in source code** (`supabase_config.dart`). For production, should it be injected via CI environment variables only?
16. No rate-limiting exists on vote casting from the client side beyond DB constraints. Should we add per-user cooldowns?

### Features Not Yet Implemented
17. **Notifications** — the `notification` table is populated but there is no push notification integration (FCM for Android, APNs for iOS). When is this planned?
18. **Badges** — defined in DB but not awarded or displayed on profiles.
19. **Language support** — the profile page has a "Language" option. Will the app support Arabic and French (localization)?
20. **Offline support** — currently the app requires active internet for all operations. Is offline-first a requirement?
21. **Admin panel** — who manages `type_activite` (categories) and `niveau_activite` (difficulty levels)? There is no admin UI currently.
22. **Analytics** — is there a requirement to track metrics (number of activities per city, XP distributed per month, user retention)?

---

*Documentation generated from source code analysis — April 2026*
