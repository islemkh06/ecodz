import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home.dart';
import 'profile.dart';
import 'search.dart';
import '../widgets/create_activity_modal.dart';

// ─── Data classes ─────────────────────────────────────────────────────────────

class _VotingItem {
  final int id;
  final String creatorId;
  final String title;
  final String description;
  final String location;
  final String date;
  final String xpLabel;
  final String imageUrl;
  final String categoryName;
  final String levelName;
  final int approveCount;
  final int rejectCount;
  final int? myVote;

  const _VotingItem({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.location,
    required this.date,
    required this.xpLabel,
    required this.imageUrl,
    required this.categoryName,
    required this.levelName,
    required this.approveCount,
    required this.rejectCount,
    this.myVote,
  });

  int get totalVotes => approveCount + rejectCount;
  bool get votingClosed => totalVotes >= 2;
  bool get hasVoted => myVote != null;
  bool isOwner(String? userId) => userId != null && creatorId == userId;

  _VotingItem copyWithVote(int valeur) => _VotingItem(
    id: id,
    creatorId: creatorId,
    title: title,
    description: description,
    location: location,
    date: date,
    xpLabel: xpLabel,
    imageUrl: imageUrl,
    categoryName: categoryName,
    levelName: levelName,
    approveCount: valeur == 1 ? approveCount + 1 : approveCount,
    rejectCount: valeur == -1 ? rejectCount + 1 : rejectCount,
    myVote: valeur,
  );
}

class _SimpleActivity {
  final int id;
  final String title;
  final String location;
  final String date;
  final String xpLabel;
  final String imageUrl;
  final String categoryName;

  const _SimpleActivity({
    required this.id,
    required this.title,
    required this.location,
    required this.date,
    required this.xpLabel,
    required this.imageUrl,
    required this.categoryName,
  });
}

// ─── Page ─────────────────────────────────────────────────────────────────────

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage>
    with TickerProviderStateMixin {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _surface = Color(0xFFF5FBF4);
  static const Color _approveColor = Color(0xFF2E7D32);
  static const Color _rejectColor = Color(0xFFB71C1C);

  late final TabController _tabController;
  int _currentIndex = 1;

  // Tab 0 – Voting feed
  List<_VotingItem> _items = [];
  bool _loadingFeed = true;
  String? _feedError;
  final Set<int> _voting = {};

  // Tab 1 – My completed (approved) activities
  List<_SimpleActivity> _myCompleted = [];
  bool _loadingCompleted = false;
  bool _completedLoaded = false;

  // Tab 2 – Activities I voted on that were rejected
  List<_SimpleActivity> _myRejected = [];
  bool _loadingRejected = false;
  bool _rejectedLoaded = false;

  // ── My Activities section ──────────────────────────────────────────────────
  int _sectionIndex = 0;
  late final TabController _myActTabController;

  List<_SimpleActivity> _myOngoing = [];
  bool _loadingOngoing = false;
  bool _ongoingLoaded = false;

  List<_SimpleActivity> _myParticipatedCompleted = [];
  bool _loadingParticipatedCompleted = false;
  bool _participatedCompletedLoaded = false;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChange);
    _myActTabController = TabController(length: 2, vsync: this);
    _myActTabController.addListener(_onMyActTabChange);
    _loadFeed();
  }

  void _onTabChange() {
    final idx = _tabController.index;
    if (idx == 1 && !_completedLoaded && !_loadingCompleted) _loadMyCompleted();
    if (idx == 2 && !_rejectedLoaded && !_loadingRejected) _loadMyRejected();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChange);
    _tabController.dispose();
    _myActTabController.removeListener(_onMyActTabChange);
    _myActTabController.dispose();
    super.dispose();
  }

  // ── loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadFeed() async {
    setState(() {
      _loadingFeed = true;
      _feedError = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, description, localisation, '
            'datecreation, xpfinal, '
            'type_activite(nom), niveau_activite(description), preuve(url)',
          )
          .eq('status', 'waiting')
          .order('datecreation', ascending: false);

      final acts = (data as List).cast<Map<String, dynamic>>();
      if (acts.isEmpty) {
        if (mounted)
          setState(() {
            _items = [];
            _loadingFeed = false;
          });
        return;
      }

      final actIds = acts.map((a) => a['id_act'] as int).toList();
      final votesData = await Supabase.instance.client
          .from('vote_approbation')
          .select('id_act, id_utilisateur, valeur')
          .inFilter('id_act', actIds);

      final votes = (votesData as List).cast<Map<String, dynamic>>();
      final Map<int, int> appC = {};
      final Map<int, int> rejC = {};
      final Map<int, int?> myV = {};

      for (final v in votes) {
        final aid = v['id_act'] as int;
        final val = v['valeur'] as int;
        if (val == 1)
          appC[aid] = (appC[aid] ?? 0) + 1;
        else
          rejC[aid] = (rejC[aid] ?? 0) + 1;
        if ((v['id_utilisateur'] as String?) == _myId) myV[aid] = val;
      }

      final items = acts.map((act) {
        final id = act['id_act'] as int;
        final preuveList = act['preuve'] as List? ?? [];
        final typeData = act['type_activite'] as Map<String, dynamic>?;
        final niveauData = act['niveau_activite'] as Map<String, dynamic>?;
        return _VotingItem(
          id: id,
          creatorId: act['id_utilisateur'] as String? ?? '',
          title: act['titre'] as String? ?? '',
          description: act['description'] as String? ?? '',
          location: act['localisation'] as String? ?? '',
          date: _fmtDate(act['datecreation'] as String?),
          xpLabel: act['xpfinal'] != null ? '+${act['xpfinal']} XP' : '',
          imageUrl: preuveList.isNotEmpty
              ? (preuveList.first['url'] as String? ?? '')
              : '',
          categoryName: typeData?['nom'] as String? ?? '',
          levelName: niveauData?['description'] as String? ?? '',
          approveCount: appC[id] ?? 0,
          rejectCount: rejC[id] ?? 0,
          myVote: myV[id],
        );
      }).toList();

      if (mounted)
        setState(() {
          _items = items;
          _loadingFeed = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _feedError = 'Failed to load voting feed.';
          _loadingFeed = false;
        });
    }
  }

  Future<void> _loadMyCompleted() async {
    setState(() => _loadingCompleted = true);
    final uid = _myId;
    if (uid == null) {
      setState(() => _loadingCompleted = false);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, titre, localisation, datecreation, xpfinal, type_activite(nom), preuve(url)',
          )
          .eq('status', 'approved')
          .eq('id_utilisateur', uid)
          .order('datecreation', ascending: false);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map(_parseSimple)
          .toList();
      if (mounted)
        setState(() {
          _myCompleted = list;
          _loadingCompleted = false;
          _completedLoaded = true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingCompleted = false;
          _completedLoaded = true;
        });
    }
  }

  Future<void> _loadMyRejected() async {
    setState(() => _loadingRejected = true);
    final uid = _myId;
    if (uid == null) {
      setState(() => _loadingRejected = false);
      return;
    }
    try {
      final voteData = await Supabase.instance.client
          .from('vote_approbation')
          .select('id_act')
          .eq('id_utilisateur', uid);

      final actIds = (voteData as List).map((v) => v['id_act'] as int).toList();
      if (actIds.isEmpty) {
        if (mounted)
          setState(() {
            _myRejected = [];
            _loadingRejected = false;
            _rejectedLoaded = true;
          });
        return;
      }

      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, titre, localisation, datecreation, xpfinal, type_activite(nom), preuve(url)',
          )
          .inFilter('id_act', actIds)
          .eq('status', 'rejected')
          .order('datecreation', ascending: false);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map(_parseSimple)
          .toList();
      if (mounted)
        setState(() {
          _myRejected = list;
          _loadingRejected = false;
          _rejectedLoaded = true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingRejected = false;
          _rejectedLoaded = true;
        });
    }
  }

  Future<void> _castVote(int actId, int valeur) async {
    final userId = _myId;
    if (userId == null) return;
    setState(() => _voting.add(actId));
    try {
      final result = await Supabase.instance.client.rpc(
        'cast_approval_vote',
        params: {'p_act_id': actId, 'p_user_id': userId, 'p_valeur': valeur},
      );
      final res = result as Map<String, dynamic>;
      if (res['error'] != null) {
        if (mounted) {
          final msg = switch (res['error'] as String) {
            'already_voted' => 'You already voted on this activity.',
            'voting_closed' => 'Voting is already closed for this activity.',
            'own_activity' => 'You cannot vote on your own activity.',
            'activity_not_found' => 'Activity not found.',
            _ => 'Could not cast vote. Please try again.',
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadFeed();
        return;
      }
      final decided = res['decided'] as bool? ?? false;
      if (mounted) {
        setState(() {
          if (decided) {
            _items.removeWhere((e) => e.id == actId);
            // Invalidate the rejected tab so it refreshes next visit
            _rejectedLoaded = false;
          } else {
            final idx = _items.indexWhere((e) => e.id == actId);
            if (idx >= 0) _items[idx] = _items[idx].copyWithVote(valeur);
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('An error occurred. Please try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _voting.remove(actId));
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  String _fmtDate(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  _SimpleActivity _parseSimple(Map<String, dynamic> act) {
    final preuveList = act['preuve'] as List? ?? [];
    final typeData = act['type_activite'] as Map<String, dynamic>?;
    return _SimpleActivity(
      id: act['id_act'] as int,
      title: act['titre'] as String? ?? '',
      location: act['localisation'] as String? ?? '',
      date: _fmtDate(act['datecreation'] as String?),
      xpLabel: act['xpfinal'] != null ? '+${act['xpfinal']} XP' : '',
      imageUrl: preuveList.isNotEmpty
          ? (preuveList.first['url'] as String? ?? '')
          : '',
      categoryName: typeData?['nom'] as String? ?? '',
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildFab(),
      bottomNavigationBar: _buildBottomBar(),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildHeader(),
            ),
            const SizedBox(height: 10),
            _buildSectionToggle(),
            const SizedBox(height: 6),
            Expanded(
              child: _sectionIndex == 0
                  ? _buildCommunityVotingPage()
                  : _buildMyActivitiesPage(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section pages ───────────────────────────────────────────────────────────

  Widget _buildCommunityVotingPage() {
    return Column(
      children: [
        _buildTabBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildVotingTab(),
              _buildSimpleTab(
                loading: _loadingCompleted,
                items: _myCompleted,
                emptyIcon: Icons.check_circle_outline_rounded,
                emptyMsg: 'None of your activities have been approved yet.',
                rejected: false,
                onRefresh: () async {
                  _completedLoaded = false;
                  await _loadMyCompleted();
                },
              ),
              _buildSimpleTab(
                loading: _loadingRejected,
                items: _myRejected,
                emptyIcon: Icons.thumb_down_off_alt_outlined,
                emptyMsg: 'No activities you voted on have been rejected.',
                rejected: true,
                onRefresh: () async {
                  _rejectedLoaded = false;
                  await _loadMyRejected();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMyActivitiesPage() {
    return Column(
      children: [
        _buildMyActivitiesTabBar(),
        Expanded(
          child: TabBarView(
            controller: _myActTabController,
            children: [
              _buildMyActivitiesSimpleTab(
                loading: _loadingOngoing,
                items: _myOngoing,
                emptyIcon: Icons.directions_run_rounded,
                emptyMsg:
                    'You are not participating in any ongoing activities.',
                badgeLabel: 'Ongoing',
                badgeColor: const Color(0xFF2E7D32),
                onRefresh: () async {
                  _ongoingLoaded = false;
                  await _loadMyOngoing();
                },
              ),
              _buildMyActivitiesSimpleTab(
                loading: _loadingParticipatedCompleted,
                items: _myParticipatedCompleted,
                emptyIcon: Icons.task_alt_rounded,
                emptyMsg: 'You have not completed any activities yet.',
                badgeLabel: 'Completed',
                badgeColor: const Color(0xFF2E7D32),
                onRefresh: () async {
                  _participatedCompletedLoaded = false;
                  await _loadMyParticipatedCompleted();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF2E7D32),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Vote'),
            Tab(text: 'Completed'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
    );
  }

  // ── Tab 0: Voting feed ─────────────────────────────────────────────────────

  Widget _buildVotingTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: _loadFeed,
      child: _loadingFeed
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : _feedError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 12),
                  Text(_feedError!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadFeed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _deepGreen,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _items.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.how_to_vote_outlined,
                          color: Colors.grey.shade400,
                          size: 64,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'No activities awaiting votes.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Create an activity to get the community voting!',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              itemCount: _items.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _buildVoteCard(_items[i]),
              ),
            ),
    );
  }

  // ── Tab 1 & 2: Simple lists ────────────────────────────────────────────────

  Widget _buildSimpleTab({
    required bool loading,
    required List<_SimpleActivity> items,
    required IconData emptyIcon,
    required String emptyMsg,
    required bool rejected,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      color: _green,
      onRefresh: onRefresh,
      child: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : items.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(emptyIcon, color: Colors.grey.shade400, size: 64),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            emptyMsg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              itemCount: items.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildSimpleCard(items[i], rejected: rejected),
              ),
            ),
    );
  }

  Widget _buildSimpleCard(_SimpleActivity act, {required bool rejected}) {
    final badgeColor = rejected ? _rejectColor : _approveColor;
    final badgeLabel = rejected ? 'Rejected' : 'Approved';
    final badgeIcon = rejected
        ? Icons.thumb_down_rounded
        : Icons.check_circle_rounded;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141B5E20),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            child: SizedBox(
              width: 90,
              height: 90,
              child: act.imageUrl.startsWith('http')
                  ? Image.network(
                      act.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          act.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF163217),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, color: Colors.white, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              badgeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (act.categoryName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      act.categoryName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A7D4E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    children: [
                      if (act.location.isNotEmpty)
                        _metaChip(Icons.location_on_rounded, act.location),
                      if (act.date.isNotEmpty)
                        _metaChip(Icons.calendar_today_rounded, act.date),
                      if (act.xpLabel.isNotEmpty)
                        _metaChip(Icons.bolt_rounded, act.xpLabel),
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

  // ── Vote card (Tab 0) ──────────────────────────────────────────────────────

  Widget _buildVoteCard(_VotingItem item) {
    final isOwner = item.isOwner(_myId);
    final isVoting = _voting.contains(item.id);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141B5E20),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Stack(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: item.imageUrl.startsWith('http')
                      ? Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
                if (item.categoryName.isNotEmpty)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _badge(
                      item.categoryName,
                      const Color(0xFF1B5E20),
                      Colors.white,
                    ),
                  ),
                if (item.xpLabel.isNotEmpty)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _badge(
                      item.xpLabel,
                      const Color(0xFFFFB300),
                      const Color(0xFF4A3800),
                    ),
                  ),
                if (item.votingClosed)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0x99000000),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Voting Closed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF163217),
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF607060),
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (item.location.isNotEmpty)
                      _metaChip(Icons.location_on_rounded, item.location),
                    if (item.date.isNotEmpty)
                      _metaChip(Icons.calendar_today_rounded, item.date),
                    if (item.levelName.isNotEmpty)
                      _metaChip(Icons.military_tech_rounded, item.levelName),
                  ],
                ),
                const SizedBox(height: 16),
                _buildVoteProgress(item),
                const SizedBox(height: 14),
                if (isOwner)
                  _ownerBanner()
                else if (item.votingClosed)
                  _closedBanner(item)
                else if (item.hasVoted)
                  _votedBanner(item)
                else
                  _buildVoteButtons(item, isVoting),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoteProgress(_VotingItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${item.totalVotes} / 2 votes',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A7D4E),
              ),
            ),
            const Spacer(),
            _dot(const Color(0xFF2E7D32)),
            const SizedBox(width: 4),
            Text(
              '${item.approveCount}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            const Text(
              'Approved',
              style: TextStyle(fontSize: 11, color: Color(0xFF4A7D4E)),
            ),
            const SizedBox(width: 10),
            _dot(const Color(0xFFB71C1C)),
            const SizedBox(width: 4),
            Text(
              '${item.rejectCount}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB71C1C),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            const Text(
              'Rejected',
              style: TextStyle(fontSize: 11, color: Color(0xFF8B4040)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (_, constraints) {
            final full = constraints.maxWidth;
            final appW = (item.approveCount / 2) * full;
            final rejW = (item.rejectCount / 2) * full;
            return ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                width: full,
                child: Stack(
                  children: [
                    Container(width: full, color: const Color(0xFFE0E0E0)),
                    if (appW > 0)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: appW,
                          color: const Color(0xFF2E7D32),
                        ),
                      ),
                    if (rejW > 0)
                      Positioned(
                        left: appW,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: rejW,
                          color: const Color(0xFFB71C1C),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildVoteButtons(_VotingItem item, bool isVoting) {
    if (isVoting) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: CircularProgressIndicator(
            color: Color(0xFF2E7D32),
            strokeWidth: 2.5,
          ),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: _voteBtn(
            label: 'Approve',
            icon: Icons.thumb_up_rounded,
            color: _approveColor,
            onTap: () => _castVote(item.id, 1),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _voteBtn(
            label: 'Reject',
            icon: Icons.thumb_down_rounded,
            color: _rejectColor,
            onTap: () => _castVote(item.id, -1),
          ),
        ),
      ],
    );
  }

  Widget _voteBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
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

  Widget _ownerBanner() => _infoBanner(
    icon: Icons.info_outline_rounded,
    text: 'This is your activity – awaiting community votes.',
    bgColor: const Color(0xFFE8F5E9),
    borderColor: const Color(0xFF4CAF50),
    textColor: const Color(0xFF1B5E20),
    iconColor: const Color(0xFF2E7D32),
  );

  Widget _votedBanner(_VotingItem item) {
    final approved = item.myVote == 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: approved ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: approved ? const Color(0xFF4CAF50) : const Color(0xFFE57373),
        ),
      ),
      child: Row(
        children: [
          Icon(
            approved ? Icons.thumb_up_rounded : Icons.thumb_down_rounded,
            color: approved ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              approved ? 'You voted: Approved' : 'You voted: Rejected',
              style: TextStyle(
                color: approved
                    ? const Color(0xFF1B5E20)
                    : const Color(0xFFB71C1C),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            'Awaiting 2nd vote',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _closedBanner(_VotingItem item) {
    final w = item.approveCount > item.rejectCount;
    return _infoBanner(
      icon: Icons.lock_rounded,
      text: w
          ? 'Voting closed – Activity Approved'
          : 'Voting closed – Activity Rejected',
      bgColor: w ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
      borderColor: w ? const Color(0xFF4CAF50) : const Color(0xFFE57373),
      textColor: w ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
      iconColor: w ? const Color(0xFF2E7D32) : const Color(0xFFB71C1C),
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required String text,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── My Activities – loaders ────────────────────────────────────────────────

  void _onMyActTabChange() {
    final idx = _myActTabController.index;
    if (idx == 0 && !_ongoingLoaded && !_loadingOngoing) _loadMyOngoing();
    if (idx == 1 &&
        !_participatedCompletedLoaded &&
        !_loadingParticipatedCompleted)
      _loadMyParticipatedCompleted();
  }

  Future<void> _loadMyOngoing() async {
    setState(() => _loadingOngoing = true);
    final uid = _myId;
    if (uid == null) {
      setState(() => _loadingOngoing = false);
      return;
    }
    try {
      final reservData = await Supabase.instance.client
          .from('reservation')
          .select('id_act')
          .eq('id_utilisateur', uid)
          .eq('status', 'active');

      final actIds = (reservData as List)
          .map((r) => r['id_act'] as int)
          .toList();
      if (actIds.isEmpty) {
        if (mounted)
          setState(() {
            _myOngoing = [];
            _loadingOngoing = false;
            _ongoingLoaded = true;
          });
        return;
      }

      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, titre, localisation, datecreation, xpfinal, type_activite(nom), preuve(url)',
          )
          .inFilter('id_act', actIds)
          .order('datecreation', ascending: false);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map(_parseSimple)
          .toList();
      if (mounted)
        setState(() {
          _myOngoing = list;
          _loadingOngoing = false;
          _ongoingLoaded = true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingOngoing = false;
          _ongoingLoaded = true;
        });
    }
  }

  Future<void> _loadMyParticipatedCompleted() async {
    setState(() => _loadingParticipatedCompleted = true);
    final uid = _myId;
    if (uid == null) {
      setState(() => _loadingParticipatedCompleted = false);
      return;
    }
    try {
      final reservData = await Supabase.instance.client
          .from('reservation')
          .select('id_act')
          .eq('id_utilisateur', uid)
          .eq('status', 'completed');

      final actIds = (reservData as List)
          .map((r) => r['id_act'] as int)
          .toList();
      if (actIds.isEmpty) {
        if (mounted)
          setState(() {
            _myParticipatedCompleted = [];
            _loadingParticipatedCompleted = false;
            _participatedCompletedLoaded = true;
          });
        return;
      }

      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, titre, localisation, datecreation, xpfinal, type_activite(nom), preuve(url)',
          )
          .inFilter('id_act', actIds)
          .order('datecreation', ascending: false);

      final list = (data as List)
          .cast<Map<String, dynamic>>()
          .map(_parseSimple)
          .toList();
      if (mounted)
        setState(() {
          _myParticipatedCompleted = list;
          _loadingParticipatedCompleted = false;
          _participatedCompletedLoaded = true;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _loadingParticipatedCompleted = false;
          _participatedCompletedLoaded = true;
        });
    }
  }

  // ── My Activities – UI ────────────────────────────────────────────────────

  Widget _buildSectionToggle() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _sectionTab(0, Icons.how_to_vote_rounded, 'Community Voting'),
          _sectionTab(1, Icons.person_pin_circle_rounded, 'My Activities'),
        ],
      ),
    ),
  );
}

Widget _sectionTab(int idx, IconData icon, String label) {
  final active = _sectionIndex == idx;
  return Expanded(
    child: GestureDetector(
      onTap: () async {
        if (_sectionIndex == idx) return;

        setState(() {
          _sectionIndex = idx;
        });

        if (idx == 1) {
          await _loadMyOngoing();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2E7D32) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : const Color(0xFF2E7D32),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildMyActivitiesTabBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: _myActTabController,
          indicator: BoxDecoration(
            color: const Color(0xFF2E7D32),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF2E7D32),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(text: 'Ongoing'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
    );
  }

  Widget _buildMyActivitiesSimpleTab({
    required bool loading,
    required List<_SimpleActivity> items,
    required IconData emptyIcon,
    required String emptyMsg,
    required String badgeLabel,
    required Color badgeColor,
    required Future<void> Function() onRefresh,
  }) {
    return RefreshIndicator(
      color: const Color(0xFF2E7D32),
      onRefresh: onRefresh,
      child: loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            )
          : items.isEmpty
          ? ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(emptyIcon, color: Colors.grey.shade400, size: 64),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            emptyMsg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              itemCount: items.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildMyActivitiesCard(
                  items[i],
                  badgeLabel: badgeLabel,
                  badgeColor: badgeColor,
                ),
              ),
            ),
    );
  }

  Widget _buildMyActivitiesCard(
    _SimpleActivity act, {
    required String badgeLabel,
    required Color badgeColor,
  }) {
    final badgeIcon = badgeLabel == 'Ongoing'
        ? Icons.directions_run_rounded
        : Icons.task_alt_rounded;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14163476),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(20),
            ),
            child: SizedBox(
              width: 90,
              height: 90,
              child: act.imageUrl.startsWith('http')
                  ? Image.network(
                      act.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          act.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0D1B4A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, color: Colors.white, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              badgeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (act.categoryName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      act.categoryName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1565C0),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    children: [
                      if (act.location.isNotEmpty)
                        _metaChip(Icons.location_on_rounded, act.location),
                      if (act.date.isNotEmpty)
                        _metaChip(Icons.calendar_today_rounded, act.date),
                      if (act.xpLabel.isNotEmpty)
                        _metaChip(Icons.bolt_rounded, act.xpLabel),
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

  // ── Shared widgets ─────────────────────────────────────────────────────────

  Widget _imagePlaceholder() => Container(
    color: const Color(0xFFE8F5E9),
    child: const Center(
      child: Icon(Icons.eco_rounded, color: Color(0xFF4CAF50), size: 40),
    ),
  );

  Widget _badge(String label, Color bg, Color textColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: textColor,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _metaChip(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: const Color(0xFF607060)),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF607060),
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );

  Widget _dot(Color color) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  // ── Nav ────────────────────────────────────────────────────────────────────

  // Remplacez la méthode _buildHeader() par celle-ci :

Widget _buildHeader() {
  final isCommunityVoting = _sectionIndex == 0;
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        colors: isCommunityVoting
            ? [const Color(0xFF2E7D32), const Color(0xFF1B5E20)]
            : [const Color(0xFF2E7D32), const Color(0xFF2E7D32)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33244D2B),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x22FFFFFF),
            border: Border.all(color: const Color(0x44FFFFFF), width: 2),
          ),
          child: Icon(
            isCommunityVoting
                ? Icons.how_to_vote_rounded
                : Icons.person_pin_circle_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCommunityVoting ? 'Community Voting' : 'My Activities',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isCommunityVoting
                    ? 'Review & approve new eco activities'
                    : 'Track your ongoing & completed activities',
                style: const TextStyle(color: Color(0xFFB8DFB8), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildFab() {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => CreateActivityModal(onActivityCreated: _loadFeed),
      ),
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

  Widget _buildBottomBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 9,
      color: const Color(0xFF1B5E20),
      child: SizedBox(
        height: 72,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navItem(Icons.home_rounded, 0),
            _navItem(Icons.how_to_vote_rounded, 1),
            const SizedBox(width: 56),
            _navItem(Icons.search_rounded, 2),
            _navItem(Icons.person_rounded, 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index) {
    final bool active = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const HomePage(),
              transitionsBuilder: (_, anim, __, child) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(-1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              ),
            ),
          );
          return;
        }
        if (index == 2) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const SearchPage(),
              transitionsBuilder: (_, anim, __, child) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              ),
            ),
          );
          return;
        }
        if (index == 3) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const ProfilePage(),
              transitionsBuilder: (_, anim, __, child) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: child,
                ),
              ),
            ),
          );
          return;
        }
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: active ? const Color(0xFFA5D6A7) : Colors.transparent,
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
