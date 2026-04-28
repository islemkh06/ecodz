import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activity.dart';
import 'home.dart';
import 'profile.dart';
import 'search.dart';
import 'user_profile.dart';

// ---------------------------------------------------------------------------
// Data models (mirrors DB schema)
// ---------------------------------------------------------------------------

enum ActivityStatus { pending, completed, approved }

enum ActivityPhase { xp, travail }

class NiveauActivite {
  final String name;
  final int xpMin;
  final int xpMax;
  final int level; // 1=Beginner, 2=Intermediate, 3=Advanced

  const NiveauActivite({
    required this.name,
    required this.xpMin,
    required this.xpMax,
    required this.level,
  });
}

class Utilisateur {
  final String nom;
  final String avatarUrl;
  final double reputation;

  const Utilisateur({
    required this.nom,
    required this.avatarUrl,
    required this.reputation,
  });
}

class Preuve {
  final String imageUrl;
  final bool isBefore;

  const Preuve({required this.imageUrl, required this.isBefore});
}

class Vote {
  final String userName;
  final double rating;
  final String commentaire;

  const Vote({
    required this.userName,
    required this.rating,
    required this.commentaire,
  });
}

class Validation {
  final ActivityPhase phase;
  final ActivityStatus status;
  final double moyenne;

  const Validation({
    required this.phase,
    required this.status,
    required this.moyenne,
  });
}

class ActivityDetail {
  final String? organizerId;
  final String id;
  final String title;
  final String description;
  final String location;
  final int xp;
  final String type;
  final ActivityStatus status;
  final DateTime startDate;
  final DateTime expirationDate;
  final String imageUrl;
  final Utilisateur organizer;
  final NiveauActivite niveau;
  final List<Preuve> preuves;
  final List<Vote> votes;
  final Validation? validation;

  const ActivityDetail({
    this.organizerId,
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.xp,
    required this.type,
    required this.status,
    required this.startDate,
    required this.expirationDate,
    required this.imageUrl,
    required this.organizer,
    required this.niveau,
    required this.preuves,
    required this.votes,
    this.validation,
  });

  factory ActivityDetail.fromSupabase(Map<String, dynamic> json) {
    final typeData = json['type_activite'] as Map<String, dynamic>?;
    final niveauData = json['niveau_activite'] as Map<String, dynamic>?;
    final profileData = json['profiles'] as Map<String, dynamic>?;
    final preuveList = (json['preuve'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final voteList = (json['vote'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final validationList = (json['validation'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final xpMin = (niveauData?['xpmin'] as num?)?.toInt() ?? 0;
    final xpMax = (niveauData?['xpmax'] as num?)?.toInt() ?? 100;

    final startDate = json['datecreation'] != null
        ? DateTime.tryParse(json['datecreation'] as String) ?? DateTime.now()
        : DateTime.now();

    // Use first 'avant' photo as hero; fall back to first photo; then asset
    final heroUrl = preuveList
        .where((p) => (p['type'] as String?) == 'avant')
        .map((p) => p['url'] as String?)
        .whereType<String>()
        .firstOrNull ??
        preuveList
            .map((p) => p['url'] as String?)
            .whereType<String>()
            .firstOrNull ??
        'assets/images.jfif';

    return ActivityDetail(
      organizerId: json['id_utilisateur'] as String?,
      id: json['id_act'].toString(),
      title: json['titre'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: json['localisation'] as String? ?? '',
      xp: (json['xpfinal'] as num?)?.toInt() ?? 0,
      type: typeData?['nom'] as String? ?? '',
      status: _parseStatus(json['status'] as String?),
      startDate: startDate,
      expirationDate: startDate.add(const Duration(days: 7)),
      imageUrl: heroUrl,
      organizer: Utilisateur(
        nom: profileData?['full_name'] as String? ?? 'Unknown',
        avatarUrl: 'assets/level1.png',
        reputation: (profileData?['reputation'] as num?)?.toDouble() ?? 0.0,
      ),
      niveau: NiveauActivite(
        name: niveauData?['description'] as String? ?? 'Unknown',
        xpMin: xpMin,
        xpMax: xpMax,
        level: xpMin >= 400 ? 3 : (xpMin >= 200 ? 2 : 1),
      ),
      preuves: preuveList
          .map((p) => Preuve(
                imageUrl: p['url'] as String? ?? 'assets/images.jfif',
                isBefore: (p['type'] as String?) == 'avant',
              ))
          .toList(),
      votes: voteList
          .map((v) => Vote(
                userName: 'Participant',
                rating: (v['valeur'] as num?)?.toDouble() ?? 0,
                commentaire: v['commentaire'] as String? ?? '',
              ))
          .toList(),
      validation: validationList.isNotEmpty
          ? Validation(
              phase: (validationList[0]['phase'] as String?) == 'XP'
                  ? ActivityPhase.xp
                  : ActivityPhase.travail,
              status: _parseStatus(validationList[0]['status'] as String?),
              moyenne:
                  (validationList[0]['moyenne'] as num?)?.toDouble() ?? 0.0,
            )
          : null,
    );
  }

  static ActivityStatus _parseStatus(String? s) => switch (s) {
        'completed' => ActivityStatus.completed,
        'approved' ||
        'pending_validation' =>
          ActivityStatus.approved,
        _ => ActivityStatus.pending,
      };
}

// ---------------------------------------------------------------------------
// Sample data (replace with real Supabase fetches)
// ---------------------------------------------------------------------------

final _sampleActivity = ActivityDetail(
  id: '1',
  title: 'Tree Plantation Drive',
  description:
      'Join us for a large-scale afforestation effort in the hills of Béjaïa. '
      'Together we will plant over 500 native tree species, restore degraded land, '
      'and create wildlife corridors. Equipment and saplings are provided. '
      'All skill levels welcome — every tree counts!',
  location: 'Béjaïa',
  xp: 400,
  type: 'Afforestation',
  status: ActivityStatus.pending,
  startDate: DateTime(2026, 4, 12, 8, 0),
  expirationDate: DateTime(2026, 4, 12, 17, 0),
  imageUrl: 'assets/images.jfif',
  organizer: const Utilisateur(
    nom: 'Yacine Aït Oufella',
    avatarUrl: 'assets/level1.png',
    reputation: 4.7,
  ),
  niveau: const NiveauActivite(
    name: 'Intermediate',
    xpMin: 300,
    xpMax: 500,
    level: 2,
  ),
  preuves: const [
    Preuve(imageUrl: 'assets/images.jfif', isBefore: true),
    Preuve(imageUrl: 'assets/images.jfif', isBefore: false),
    Preuve(imageUrl: 'assets/images.jfif', isBefore: true),
  ],
  votes: const [
    Vote(
      userName: 'Amira B.',
      rating: 5,
      commentaire: 'Amazing experience, well organised!',
    ),
    Vote(
      userName: 'Samir K.',
      rating: 4,
      commentaire: 'Great initiative, would join again.',
    ),
    Vote(
      userName: 'Lyna M.',
      rating: 5,
      commentaire: 'Very impactful — loved every minute.',
    ),
  ],
  validation: Validation(
    phase: ActivityPhase.xp,
    status: ActivityStatus.pending,
    moyenne: 4.7,
  ),
);

// ---------------------------------------------------------------------------
// Page widget
// ---------------------------------------------------------------------------

class ActivityDetailPage extends StatefulWidget {
  /// When provided, activity data is fetched from Supabase.
  /// When null, falls back to sample data (useful for static previews).
  final int? activityId;

  const ActivityDetailPage({super.key, this.activityId});

  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage>
    with TickerProviderStateMixin {
  // ---------- colours ----------
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _midGreen = Color(0xFF66BB6A);
  static const Color _paleGreen = Color(0xFFC8E6C9);
  static const Color _softGreen = Color(0xFFA5D6A7);
  static const Color _surface = Color(0xFFF5FBF4);

  // ---------- state ----------
  bool _bookmarked = false;
  int _currentIndex = 1; // Activity tab is parent

  late ActivityDetail _activity;
  bool _loading = true;
  String? _error;

  late final AnimationController _heroCtrl;
  late final Animation<double> _heroFade;
  late final AnimationController _cardCtrl;
  late final Animation<Offset> _cardSlide;

  @override
  void initState() {
    super.initState();

    _heroCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: Curves.easeOut);

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));

    if (widget.activityId != null) {
      _fetchActivity();
    } else {
      _activity = _sampleActivity;
      _loading = false;
      _heroCtrl.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _cardCtrl.forward();
      });
    }
  }

  Future<void> _fetchActivity() async {
    final id = widget.activityId;
    if (id == null || id <= 0) {
      debugPrint('[ActivityDetail] Invalid activityId: $id — falling back to sample');
      if (mounted) {
        setState(() {
          _activity = _sampleActivity;
          _loading = false;
        });
        _heroCtrl.forward();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _cardCtrl.forward();
        });
      }
      return;
    }

    debugPrint('[ActivityDetail] Fetching activity id=$id');
    try {
      // Use FK hint for profiles because activite now has TWO foreign keys
      // to profiles (id_utilisateur and assigned_worker_id). Without the hint
      // PostgREST throws an "ambiguous" error and the page never loads.
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            '*,'
            'type_activite(nom, icone),'
            'niveau_activite(id_niv_act, description, xpmin, xpmax),'
            'profiles!activite_id_utilisateur_fkey(full_name, reputation),'
            'preuve(id_preuve, url, type),'
            'vote(valeur, commentaire, id_utilisateur),'
            'validation(phase, status, moyenne)',
          )
          .eq('id_act', id)
          .maybeSingle();

      if (data == null) {
        debugPrint('[ActivityDetail] No activity found for id=$id');
        if (mounted) {
          setState(() {
            _error = 'Activity not found.';
            _loading = false;
          });
        }
        return;
      }

      debugPrint('[ActivityDetail] Data received: ${data.keys.toList()}');
      if (mounted) {
        setState(() {
          _activity = ActivityDetail.fromSupabase(data);
          _loading = false;
        });
        _heroCtrl.forward();
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _cardCtrl.forward();
        });
      }
    } catch (e, stack) {
      debugPrint('[ActivityDetail] Error fetching activity: $e\n$stack');
      if (mounted) {
        setState(() {
          _error = 'Failed to load activity details.\n$e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
  }

  // ---------- helpers ----------

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Color _statusColor(ActivityStatus s) => switch (s) {
    ActivityStatus.pending => const Color(0xFFF57F17),
    ActivityStatus.completed => const Color(0xFF1565C0),
    ActivityStatus.approved => const Color(0xFF2E7D32),
  };

  String _statusLabel(ActivityStatus s) => switch (s) {
    ActivityStatus.pending => 'Pending',
    ActivityStatus.completed => 'Completed',
    ActivityStatus.approved => 'Approved',
  };

  double get _avgRating {
    if (_activity.votes.isEmpty) return 0;
    return _activity.votes.map((v) => v.rating).reduce((a, b) => a + b) /
        _activity.votes.length;
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    if (_loading) {
      return Scaffold(
        backgroundColor: _surface,
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _deepGreen,
          foregroundColor: Colors.white,
          title: const Text('Activity'),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _fetchActivity();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _deepGreen,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _surface,
      extendBodyBehindAppBar: true,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildFab(),
      bottomNavigationBar: _buildBottomBar(),
      body: Stack(
        children: [
          // Scrollable content
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildFloatingCard()),
              SliverToBoxAdapter(
                child: SlideTransition(
                  position: _cardSlide,
                  child: FadeTransition(
                    opacity: _heroFade,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          _buildDescription(),
                          const SizedBox(height: 20),
                          _buildDateSection(),
                          const SizedBox(height: 20),
                          _buildOrganizer(),
                          const SizedBox(height: 20),
                          _buildLevel(),
                          const SizedBox(height: 20),
                          _buildProofs(),
                          const SizedBox(height: 20),
                          _buildValidation(),
                          const SizedBox(height: 20),
                          _buildVotesAndComments(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Fixed action buttons at bottom (above navbar)
          Positioned(
            bottom: 90,
            left: 16,
            right: 16,
            child: _buildActionButtons(),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // HERO SECTION
  // =========================================================

  Widget _buildHero() {
    return FadeTransition(
      opacity: _heroFade,
      child: Stack(
        children: [
          // Image
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: _activity.imageUrl.startsWith('http')
                ? Image.network(
                    _activity.imageUrl,
                    height: 270,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/images.jfif',
                      height: 270,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    _activity.imageUrl,
                    height: 270,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
          ),
          // Gradient overlay
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: Container(
              height: 270,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0xCC0D3B13),
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
          // Top bar – back + bookmark
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _heroIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  _heroIconButton(
                    icon: _bookmarked
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    onTap: () => setState(() => _bookmarked = !_bookmarked),
                    color: _bookmarked ? const Color(0xFFFFD54F) : Colors.white,
                  ),
                ],
              ),
            ),
          ),
          // Bottom overlay – title + location
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _activity.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(color: Color(0x88000000), blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Color(0xFFA5D6A7),
                        size: 17,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _activity.location,
                        style: const TextStyle(
                          color: Color(0xFFE8F5E9),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0x33FFFFFF),
              border: Border.all(color: const Color(0x44FFFFFF)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // FLOATING INFO CARD
  // =========================================================

  Widget _buildFloatingCard() {
    return SlideTransition(
      position: _cardSlide,
      child: FadeTransition(
        opacity: _heroFade,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Transform.translate(
            offset: const Offset(0, -8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1E1B5E20),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // XP Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '+${_activity.xp} XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(_activity.status).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _statusColor(_activity.status).withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      _statusLabel(_activity.status),
                      style: TextStyle(
                        color: _statusColor(_activity.status),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Activity type chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _paleGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.eco_rounded,
                          size: 15,
                          color: _deepGreen,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _activity.type,
                          style: const TextStyle(
                            color: _deepGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // SECTION HELPERS
  // =========================================================

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF163217),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141B5E20),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  // =========================================================
  // DESCRIPTION
  // =========================================================

  Widget _buildDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Description'),
        _card(
          child: Text(
            _activity.description,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.65,
              color: Color(0xFF2C4A2F),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // DATE & TIME
  // =========================================================

  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Date & Time'),
        _card(
          child: Column(
            children: [
              _dateRow(
                Icons.event_rounded,
                'Start Date',
                _formatDate(_activity.startDate),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: Color(0xFFE8F5E9)),
              ),
              _dateRow(
                Icons.event_busy_rounded,
                'Expiration Date',
                _formatDate(_activity.expirationDate),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dateRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _paleGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _deepGreen, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7A9B7D),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF163217),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // =========================================================
  // ORGANIZER
  // =========================================================

  Widget _buildOrganizer() {
    final o = _activity.organizer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Organizer'),
        _card(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: AssetImage(o.avatarUrl),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.nom,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF163217),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children:
                          List.generate(5, (i) {
                            return Icon(
                              i < o.reputation.floor()
                                  ? Icons.star_rounded
                                  : (i < o.reputation
                                        ? Icons.star_half_rounded
                                        : Icons.star_outline_rounded),
                              size: 18,
                              color: const Color(0xFFFFB300),
                            );
                          })..add(
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Text(
                                o.reputation.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFF7A9B7D),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  final id = _activity.organizerId;
                  if (id == null) return;
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      transitionDuration: const Duration(milliseconds: 350),
                      pageBuilder: (_, __, ___) =>
                          UserProfilePage(userId: id),
                      transitionsBuilder: (_, animation, __, child) =>
                          FadeTransition(opacity: animation, child: child),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _paleGreen,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'View',
                    style: TextStyle(
                      color: _deepGreen,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // LEVEL / DIFFICULTY
  // =========================================================

  Widget _buildLevel() {
    final n = _activity.niveau;
    final progress = (n.xpMin / n.xpMax).clamp(0.0, 1.0);
    final levelColor = switch (n.level) {
      1 => const Color(0xFF43A047),
      2 => const Color(0xFFFB8C00),
      _ => const Color(0xFFE53935),
    };
    final levelIcon = switch (n.level) {
      1 => Icons.eco_rounded,
      2 => Icons.bolt_rounded,
      _ => Icons.local_fire_department_rounded,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Level & Difficulty'),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: levelColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(levelIcon, color: levelColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: levelColor,
                        ),
                      ),
                      Text(
                        '${n.xpMin} – ${n.xpMax} XP',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF7A9B7D),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  color: levelColor,
                  backgroundColor: levelColor.withOpacity(0.15),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${n.xpMin} XP',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7A9B7D),
                    ),
                  ),
                  Text(
                    '${n.xpMax} XP',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF7A9B7D),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // PROOFS
  // =========================================================

  Widget _buildProofs() {
    if (_activity.preuves.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Proofs'),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _activity.preuves.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = _activity.preuves[i];
              return GestureDetector(
                onTap: () => _showFullscreenImage(context, p.imageUrl),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: p.imageUrl.startsWith('http')
                          ? Image.network(
                              p.imageUrl,
                              width: 110,
                              height: 130,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 110,
                                height: 130,
                                color: const Color(0xFFE8F5E9),
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : Image.asset(
                              p.imageUrl,
                              width: 110,
                              height: 130,
                              fit: BoxFit.cover,
                            ),
                    ),
                    // Label
                    Positioned(
                      top: 8,
                      left: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: p.isBefore
                                  ? const Color(0xCC1B5E20)
                                  : const Color(0xCC2196F3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              p.isBefore ? 'Before' : 'After',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Zoom icon
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: const Color(0xAA000000),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.zoom_in_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showFullscreenImage(BuildContext context, String url) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullscreenImageViewer(imageUrl: url),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // =========================================================
  // VALIDATION
  // =========================================================

  Widget _buildValidation() {
    final v = _activity.validation;
    if (v == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Validation'),
        _card(
          child: Column(
            children: [
              Row(
                children: [
                  _valChip(
                    'Phase',
                    v.phase == ActivityPhase.xp ? 'XP' : 'Travail',
                    Icons.layers_rounded,
                    _midGreen,
                  ),
                  const SizedBox(width: 10),
                  _valChip(
                    'Status',
                    _statusLabel(v.status),
                    Icons.verified_rounded,
                    _statusColor(v.status),
                  ),
                  const SizedBox(width: 10),
                  _valChip(
                    'Rating',
                    v.moyenne.toStringAsFixed(1),
                    Icons.star_rounded,
                    const Color(0xFFFFB300),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _valChip(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF7A9B7D),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // VOTES & COMMENTS
  // =========================================================

  Widget _buildVotesAndComments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Ratings & Comments'),
        // Summary row
        _card(
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    _avgRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF163217),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < _avgRating.floor()
                            ? Icons.star_rounded
                            : (i < _avgRating
                                  ? Icons.star_half_rounded
                                  : Icons.star_outline_rounded),
                        size: 18,
                        color: const Color(0xFFFFB300),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_activity.votes.length} votes',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A9B7D),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: List.generate(5, (i) {
                    final starVal = 5 - i;
                    final count = _activity.votes
                        .where((v) => v.rating.round() == starVal)
                        .length;
                    final ratio = _activity.votes.isEmpty
                        ? 0.0
                        : count / _activity.votes.length;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text(
                            '$starVal',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7A9B7D),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 6,
                                color: const Color(0xFFFFB300),
                                backgroundColor: const Color(0xFFE8F5E9),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7A9B7D),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Comment list
        ..._activity.votes.map((v) => _buildCommentCard(v)),
      ],
    );
  }

  Widget _buildCommentCard(Vote v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _card(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: _paleGreen,
              child: Text(
                v.userName[0],
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: _deepGreen,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        v.userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF163217),
                        ),
                      ),
                      Row(
                        children: List.generate(
                          v.rating.round(),
                          (_) => const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Color(0xFFFFB300),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    v.commentaire,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4A6B4D),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ACTION BUTTONS
  // =========================================================

  Widget _buildActionButtons() {
    return switch (_activity.status) {
      ActivityStatus.pending => _actionBtn(
        label: 'Participate',
        icon: Icons.volunteer_activism_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFF4CAF50), Color(0xFF1B5E20)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: () {},
      ),
      ActivityStatus.completed => _actionBtn(
        label: 'Waiting for Approval',
        icon: Icons.hourglass_top_rounded,
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: null,
      ),
      ActivityStatus.approved => _actionBtn(
        label: 'Approved',
        icon: Icons.check_circle_rounded,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2E7D32).withOpacity(0.6),
            const Color(0xFF1B5E20).withOpacity(0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: null,
      ),
    };
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Gradient gradient,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: onTap != null
              ? const [
                  BoxShadow(
                    color: Color(0x551B5E20),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionBtnSecondary({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _paleGreen, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x221B5E20),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _deepGreen, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: _deepGreen,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // BOTTOM NAVIGATION (same as other pages)
  // =========================================================

  Widget _buildFab() {
    return Container(
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
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 9,
      color: _deepGreen,
      child: SizedBox(
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBottomItem(Icons.home_rounded, 0),
            _buildBottomItem(Icons.bar_chart_rounded, 1),
            const SizedBox(width: 56),
            _buildBottomItem(Icons.search_rounded, 2),
            _buildBottomItem(Icons.person_rounded, 3),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomItem(IconData icon, int index) {
    final bool active = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const HomePage(),
              transitionsBuilder: (_, animation, __, child) {
                final slide =
                    Tween<Offset>(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
            ),
          );
        } else if (index == 1) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const ActivityPage(),
              transitionsBuilder: (_, animation, __, child) {
                final slide =
                    Tween<Offset>(
                      begin: const Offset(-1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
            ),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const SearchPage(),
              transitionsBuilder: (_, animation, __, child) {
                final slide =
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
            ),
          );
        } else if (index == 3) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const ProfilePage(),
              transitionsBuilder: (_, animation, __, child) {
                final slide =
                    Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? _softGreen : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFF163D17) : Colors.white,
          size: 27,
        ),
      ),
    );
  }
}

// =========================================================
// FULLSCREEN IMAGE VIEWER
// =========================================================

class _FullscreenImageViewer extends StatelessWidget {
  final String imageUrl;
  const _FullscreenImageViewer({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: imageUrl.startsWith('http')
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 64,
                        ),
                      )
                    : Image.asset(imageUrl, fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0x88000000),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
