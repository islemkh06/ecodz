import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'activity_detail.dart';
import 'group_activity_detail_page.dart';
import 'home.dart';
import 'profile.dart';
import 'search.dart';
import 'work_completion_page.dart';
import '../widgets/global_fab.dart';
import '../services/user_service.dart';

// ─── Data classes ─────────────────────────────────────────────────────────────

class _ApprovalItem {
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
  final String activityMode;

  const _ApprovalItem({
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
    this.activityMode = 'single',
  });

  int get totalVotes => approveCount + rejectCount;
  bool get votingClosed => totalVotes >= 2;
  bool get hasVoted => myVote != null;
  bool isOwner(String? uid) => uid != null && creatorId == uid;

  _ApprovalItem copyWithVote(int v) => _ApprovalItem(
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
        approveCount: v == 1 ? approveCount + 1 : approveCount,
        rejectCount: v == -1 ? rejectCount + 1 : rejectCount,
        myVote: v,
        activityMode: activityMode,
      );
}

class _ValidationItem {
  final int id;
  final String workerId;
  final String creatorId;
  final String activityMode;
  final String title;
  final String description;
  final String location;
  final String date;
  final int xpFinal;
  final int xpMin;
  final int xpMax;
  final String imageUrl;
  final String categoryName;
  final int approveCount;
  final int rejectCount;
  final bool? myVote;
  final List<String> beforeUrls;
  final List<String> afterUrls;

  const _ValidationItem({
    required this.id,
    required this.workerId,
    this.creatorId = '',
    this.activityMode = 'single',
    required this.title,
    required this.description,
    required this.location,
    required this.date,
    required this.xpFinal,
    this.xpMin = 0,
    this.xpMax = 100,
    required this.imageUrl,
    required this.categoryName,
    required this.approveCount,
    required this.rejectCount,
    this.myVote,
    this.beforeUrls = const [],
    this.afterUrls = const [],
  });

  int get totalVotes => approveCount + rejectCount;
  bool get hasVoted => myVote != null;
  bool isWorker(String? uid) => uid != null && workerId == uid;
  bool isCreator(String? uid) => uid != null && creatorId == uid;
  bool get isGroupEvent => activityMode == 'group';
}

class _WorkItem {
  final int id;
  final String creatorId;
  final String title;
  final String location;
  final String date;
  final String xpLabel;
  final String imageUrl;
  final String categoryName;
  final String status;
  final DateTime? priorityDeadline;
  final String activityMode;
  final DateTime? eventDate;

  const _WorkItem({
    required this.id,
    required this.creatorId,
    required this.title,
    required this.location,
    required this.date,
    required this.xpLabel,
    required this.imageUrl,
    required this.categoryName,
    required this.status,
    this.priorityDeadline,
    this.activityMode = 'single',
    this.eventDate,
  });

  Duration get timeLeft =>
      priorityDeadline != null
          ? priorityDeadline!.difference(DateTime.now())
          : Duration.zero;

  Duration get timeUntilEvent =>
      eventDate != null
          ? eventDate!.difference(DateTime.now())
          : Duration.zero;

  bool get eventHasStarted =>
      eventDate != null && DateTime.now().isAfter(eventDate!);
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

  int _sectionIndex = 0;

  late TabController _communityTabController;

  List<_ApprovalItem> _approvalItems = [];
  bool _loadingApproval = true;
  String? _approvalError;
  final Set<int> _voting = {};

  List<_ValidationItem> _validationItems = [];
  bool _loadingValidation = false;
  bool _validationLoaded = false;
  final Set<int> _validating = {};

  List<_WorkItem> _myHistory = [];
  bool _loadingHistory = false;
  bool _historyLoaded = false;

  late TabController _workTabController;

  List<_WorkItem> _priorityItems = [];
  bool _loadingPriority = false;
  bool _priorityLoaded = false;
  Timer? _priorityTimer;

  List<_WorkItem> _availableItems = [];
  bool _loadingAvailable = false;
  bool _availableLoaded = false;
  final Set<int> _joining = {};

  List<_WorkItem> _activeItems = [];
  bool _loadingActive = false;
  bool _activeLoaded = false;

  List<_WorkItem> _doneItems = [];
  bool _loadingDone = false;
  bool _doneLoaded = false;

  List<_WorkItem> _eventItems = [];
  bool _loadingEvents = false;
  bool _eventsLoaded = false;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _communityTabController = TabController(length: 3, vsync: this);
    _communityTabController.addListener(_onCommunityTabChange);
    _workTabController = TabController(length: 5, vsync: this);
    _workTabController.addListener(_onWorkTabChange);
    _loadApprovalFeed();
    Supabase.instance.client
        .rpc('expire_priority_assignments')
        .catchError((_) {});
  }

  void _onCommunityTabChange() {
    final i = _communityTabController.index;
    if (i == 1 && !_validationLoaded && !_loadingValidation) _loadValidation();
    if (i == 2 && !_historyLoaded && !_loadingHistory) _loadMyHistory();
  }

  void _onWorkTabChange() {
    final i = _workTabController.index;
    if (i == 0 && !_priorityLoaded && !_loadingPriority) _loadPriority();
    if (i == 1 && !_availableLoaded && !_loadingAvailable) _loadAvailable();
    if (i == 2 && !_activeLoaded && !_loadingActive) _loadActive();
    if (i == 3 && !_doneLoaded && !_loadingDone) _loadDone();
    if (i == 4 && !_eventsLoaded && !_loadingEvents) _loadEvents();
  }

  @override
  void dispose() {
    _communityTabController.removeListener(_onCommunityTabChange);
    _communityTabController.dispose();
    _workTabController.removeListener(_onWorkTabChange);
    _workTabController.dispose();
    _priorityTimer?.cancel();
    super.dispose();
  }

  // ── Loaders ────────────────────────────────────────────────────────────────

  Future<void> _loadApprovalFeed() async {
    setState(() {
      _loadingApproval = true;
      _approvalError = null;
    });
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, description, localisation, '
            'datecreation, xpfinal, activity_mode, type_activite(nom), '
            'niveau_activite(description), preuve(url)',
          )
          .eq('status', 'waiting')
          .order('datecreation', ascending: false);

      final acts = (data as List).cast<Map<String, dynamic>>();
      if (acts.isEmpty) {
        if (mounted) {
          setState(() {
            _approvalItems = [];
            _loadingApproval = false;
          });
        }
        return;
      }

      final actIds = acts.map((a) => a['id_act'] as int).toList();
      final votesData = await Supabase.instance.client
          .from('vote_approbation')
          .select('id_act, id_utilisateur, valeur')
          .inFilter('id_act', actIds);

      final votes = (votesData as List).cast<Map<String, dynamic>>();
      final Map<int, int> appC = {}, rejC = {};
      final Map<int, int?> myV = {};

      for (final v in votes) {
        final aid = v['id_act'] as int;
        final val = v['valeur'] as int;
        if (val == 1) {
          appC[aid] = (appC[aid] ?? 0) + 1;
        } else {
          rejC[aid] = (rejC[aid] ?? 0) + 1;
        }
        if ((v['id_utilisateur'] as String?) == _myId) myV[aid] = val;
      }

      final items = acts.map((act) {
        final id = act['id_act'] as int;
        final pl = act['preuve'] as List? ?? [];
        final td = act['type_activite'] as Map<String, dynamic>?;
        final nd = act['niveau_activite'] as Map<String, dynamic>?;
        return _ApprovalItem(
          id: id,
          creatorId: act['id_utilisateur'] as String? ?? '',
          title: act['titre'] as String? ?? '',
          description: act['description'] as String? ?? '',
          location: act['localisation'] as String? ?? '',
          date: _fmtDate(act['datecreation'] as String?),
          xpLabel: act['xpfinal'] != null ? '+${act['xpfinal']} XP' : '',
          imageUrl: pl.isNotEmpty ? (pl.first['url'] as String? ?? '') : '',
          categoryName: td?['nom'] as String? ?? '',
          levelName: nd?['description'] as String? ?? '',
          approveCount: appC[id] ?? 0,
          rejectCount: rejC[id] ?? 0,
          myVote: myV[id],
          activityMode: act['activity_mode'] as String? ?? 'single',
        );
      }).toList();

      if (mounted) {
        setState(() {
          _approvalItems = items;
          _loadingApproval = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _approvalError = 'Failed to load approval feed.';
          _loadingApproval = false;
        });
      }
    }
  }

  Future<void> _loadValidation() async {
    setState(() => _loadingValidation = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, assigned_worker_id, id_utilisateur, activity_mode, '
            'titre, description, localisation, '
            'datecreation, xpfinal, type_activite(nom), '
            'niveau_activite(xpmin, xpmax), '
            'preuve(url, type)',
          )
          .eq('status', 'pending_validation')
          .order('completed_at', ascending: false);

      final acts = (data as List).cast<Map<String, dynamic>>();
      if (acts.isEmpty) {
        if (mounted) {
          setState(() {
            _validationItems = [];
            _loadingValidation = false;
            _validationLoaded = true;
          });
        }
        return;
      }

      final actIds = acts.map((a) => a['id_act'] as int).toList();
      final votesData = await Supabase.instance.client
          .from('vote_completion')
          .select('id_act, id_utilisateur, approve')
          .inFilter('id_act', actIds);

      final votes = (votesData as List).cast<Map<String, dynamic>>();
      final Map<int, int> appC = {}, rejC = {};
      final Map<int, bool?> myV = {};

      for (final v in votes) {
        final aid = v['id_act'] as int;
        final approve = v['approve'] as bool;
        if (approve) {
          appC[aid] = (appC[aid] ?? 0) + 1;
        } else {
          rejC[aid] = (rejC[aid] ?? 0) + 1;
        }
        if ((v['id_utilisateur'] as String?) == _myId) myV[aid] = approve;
      }

      final items = acts.map((act) {
        final id = act['id_act'] as int;
        final pl = (act['preuve'] as List? ?? []).cast<Map<String, dynamic>>();
        final td = act['type_activite'] as Map<String, dynamic>?;
        final beforeUrls = pl
            .where((p) => (p['type'] as String?) == 'avant')
            .map((p) => p['url'] as String? ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        final afterUrls = pl
            .where((p) => (p['type'] as String?) == 'apres')
            .map((p) => p['url'] as String? ?? '')
            .where((u) => u.isNotEmpty)
            .toList();
        final heroUrl = afterUrls.isNotEmpty
            ? afterUrls.first
            : (beforeUrls.isNotEmpty ? beforeUrls.first : '');

        final nd = act['niveau_activite'] as Map<String, dynamic>?;
        final xpMin = (nd?['xpmin'] as num?)?.toInt() ?? 0;
        final xpMax = (nd?['xpmax'] as num?)?.toInt() ?? 100;

        return _ValidationItem(
          id: id,
          workerId: act['assigned_worker_id'] as String? ?? '',
          creatorId: act['id_utilisateur'] as String? ?? '',
          activityMode: act['activity_mode'] as String? ?? 'single',
          title: act['titre'] as String? ?? '',
          description: act['description'] as String? ?? '',
          location: act['localisation'] as String? ?? '',
          date: _fmtDate(act['datecreation'] as String?),
          xpFinal: (act['xpfinal'] as num?)?.toInt() ?? 0,
          xpMin: xpMin,
          xpMax: xpMax,
          imageUrl: heroUrl,
          categoryName: td?['nom'] as String? ?? '',
          approveCount: appC[id] ?? 0,
          rejectCount: rejC[id] ?? 0,
          myVote: myV[id],
          beforeUrls: beforeUrls,
          afterUrls: afterUrls,
        );
      }).toList();

      if (mounted) {
        setState(() {
          _validationItems = items;
          _loadingValidation = false;
          _validationLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingValidation = false;
          _validationLoaded = true;
        });
      }
    }
  }

  Future<void> _loadMyHistory() async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _loadingHistory = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, localisation, datecreation, '
            'xpfinal, status, type_activite(nom), preuve(url)',
          )
          .eq('id_utilisateur', uid)
          .inFilter('status', [
            'completed', 'approved', 'rejected', 'open',
            'in_progress', 'pending_validation', 'waiting', 'priority_pending'
          ])
          .order('datecreation', ascending: false);

      final list = (data as List).cast<Map<String, dynamic>>().map(_parseWork).toList();
      if (mounted) {
        setState(() {
          _myHistory = list;
          _loadingHistory = false;
          _historyLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _historyLoaded = true;
        });
      }
    }
  }

  Future<void> _loadPriority() async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _loadingPriority = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, localisation, datecreation, '
            'xpfinal, status, priority_deadline, type_activite(nom), preuve(url)',
          )
          .eq('id_utilisateur', uid)
          .eq('status', 'priority_pending')
          .order('priority_deadline');

      final list = (data as List).cast<Map<String, dynamic>>().map(_parseWork).toList();
      if (mounted) {
        setState(() {
          _priorityItems = list;
          _loadingPriority = false;
          _priorityLoaded = true;
        });
        _priorityTimer?.cancel();
        if (list.isNotEmpty) {
          _priorityTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingPriority = false;
          _priorityLoaded = true;
        });
      }
    }
  }

  Future<void> _loadAvailable() async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _loadingAvailable = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, localisation, datecreation, '
            'xpfinal, status, activity_mode, type_activite(nom), preuve(url)',
          )
          .inFilter('status', ['open', 'approved'])
          .neq('id_utilisateur', uid)
          .eq('activity_mode', 'single')
          .order('datecreation', ascending: false);

      final list = (data as List).cast<Map<String, dynamic>>().map(_parseWork).toList();
      if (mounted) {
        setState(() {
          _availableItems = list;
          _loadingAvailable = false;
          _availableLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingAvailable = false;
          _availableLoaded = true;
        });
      }
    }
  }

  Future<void> _loadActive() async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _loadingActive = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, localisation, datecreation, '
            'xpfinal, status, type_activite(nom), preuve(url)',
          )
          .eq('assigned_worker_id', uid)
          .eq('status', 'in_progress')
          .order('datecreation', ascending: false);

      final list = (data as List).cast<Map<String, dynamic>>().map(_parseWork).toList();
      if (mounted) {
        setState(() {
          _activeItems = list;
          _loadingActive = false;
          _activeLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingActive = false;
          _activeLoaded = true;
        });
      }
    }
  }

  Future<void> _loadDone() async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _loadingDone = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, localisation, datecreation, '
            'xpfinal, status, type_activite(nom), preuve(url)',
          )
          .eq('assigned_worker_id', uid)
          .eq('status', 'completed')
          .order('datecreation', ascending: false);

      final list = (data as List).cast<Map<String, dynamic>>().map(_parseWork).toList();
      if (mounted) {
        setState(() {
          _doneItems = list;
          _loadingDone = false;
          _doneLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingDone = false;
          _doneLoaded = true;
        });
      }
    }
  }

  Future<void> _loadEvents() async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _loadingEvents = true);

    Supabase.instance.client.rpc('lock_due_group_events').catchError((_) {});
    Supabase.instance.client.rpc('start_due_group_events').catchError((_) {});

    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select(
            'id_act, id_utilisateur, titre, localisation, datecreation, '
            'xpfinal, status, activity_mode, event_date, '
            'max_participants, current_participants_count, '
            'type_activite(nom), preuve(url)',
          )
          .eq('activity_mode', 'group')
          .or(
            'status.in.(open,approved,locked,in_progress),'
            'and(status.eq.priority_pending,id_utilisateur.eq.$uid)',
          )
          .order('event_date', ascending: true)
          .limit(50);

      final list = (data as List).cast<Map<String, dynamic>>().map(_parseWork).toList();
      if (mounted) {
        setState(() {
          _eventItems = list;
          _loadingEvents = false;
          _eventsLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingEvents = false;
          _eventsLoaded = true;
        });
      }
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _castApprovalVote(int actId, int valeur) async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _voting.add(actId));
    try {
      final dynamic rpcResult = await Supabase.instance.client.rpc(
        'cast_approval_vote',
        params: {'p_act_id': actId, 'p_user_id': uid, 'p_valeur': valeur},
      );
      final res = (rpcResult as Map?)?.cast<String, dynamic>() ?? {};
      debugPrint('[ApprovalVote] result: $res');

      if (rpcResult == null || res.isEmpty) {
        _showError('Vote failed: no response from server. Make sure the database migration has been run.');
        return;
      }

      if (res['error'] != null) {
        _showError(_approvalErrorMsg(res['error'] as String));
        await _loadApprovalFeed();
        return;
      }
      final decided = res['decided'] as bool? ?? false;
      if (mounted) {
        setState(() {
          if (decided) {
            _approvalItems.removeWhere((e) => e.id == actId);
            _priorityLoaded = false;
          } else {
            final idx = _approvalItems.indexWhere((e) => e.id == actId);
            if (idx >= 0) {
              _approvalItems[idx] = _approvalItems[idx].copyWithVote(valeur);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[ApprovalVote] error: $e');
      _showError('Could not cast vote. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _voting.remove(actId));
    }
  }

  Future<void> _acceptPriority(int actId) async {
    final uid = _myId;
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client.rpc(
        'accept_priority_assignment',
        params: {'p_act_id': actId, 'p_user_id': uid},
      ) as Map<String, dynamic>;

      if (res['error'] != null) {
        _showError(res['error'] == 'deadline_expired'
            ? 'Time expired – activity is now open to all.'
            : 'Could not accept. Please try again.');
      } else {
        _showSuccess('You are now the assigned worker!');
      }
      setState(() {
        _priorityLoaded = false;
        _activeLoaded = false;
      });
      await _loadPriority();
      _loadActive();
      UserService.instance.refresh();
    } catch (_) {
      _showError('An error occurred. Please try again.');
    }
  }

  Future<void> _declinePriority(int actId) async {
    final uid = _myId;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc(
        'decline_priority_assignment',
        params: {'p_act_id': actId, 'p_user_id': uid},
      );
      _showSuccess('Activity is now open to all users.');
      setState(() => _priorityLoaded = false);
      await _loadPriority();
    } catch (_) {
      _showError('An error occurred. Please try again.');
    }
  }

  Future<void> _joinActivity(int actId) async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _joining.add(actId));
    try {
      final res = await Supabase.instance.client.rpc(
        'join_open_activity',
        params: {'p_act_id': actId, 'p_user_id': uid},
      ) as Map<String, dynamic>;

      if (res['error'] != null) {
        _showError(res['error'] == 'not_available'
            ? 'This activity is no longer available.'
            : 'Could not join. Please try again.');
      } else {
        _showSuccess('You joined the activity! Start working.');
        setState(() {
          _availableLoaded = false;
          _activeLoaded = false;
        });
        _loadAvailable();
        _loadActive();
      }
    } catch (_) {
      _showError('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _joining.remove(actId));
    }
  }

  Future<void> _castCompletionVote(
      int actId, bool approve, int? xpProposal) async {
    final uid = _myId;
    if (uid == null) return;
    setState(() => _validating.add(actId));
    try {
      final dynamic rpcResult = await Supabase.instance.client.rpc(
        'cast_completion_vote',
        params: {
          'p_act_id': actId,
          'p_user_id': uid,
          'p_approve': approve,
          'p_xp_proposal': xpProposal,
        },
      );
      final res = (rpcResult as Map?)?.cast<String, dynamic>() ?? {};
      debugPrint('[CompletionVote] result: $res');

      if (rpcResult == null || res.isEmpty) {
        _showError('Vote failed: no response from server. Make sure the database migration has been run.');
        return;
      }

      if (res['error'] != null) {
        _showError(_completionErrorMsg(res['error'] as String));
        await _loadValidation();
        return;
      }
      final decided = res['decided'] as bool? ?? false;
      if (decided) {
        final newStatus = res['new_status'] as String?;
        if (newStatus == 'completed') {
          final xp = res['xp_awarded'] as int? ?? 0;
          _showSuccess('Work approved! Worker earned $xp XP.');
        } else {
          _showError('Work rejected – activity returned to open pool.');
        }
        if (mounted) {
          setState(() => _validationItems.removeWhere((e) => e.id == actId));
        }
        UserService.instance.refresh();
      } else {
        _showSuccess(approve ? 'Approved ✓' : 'Rejected ✓');
        await _loadValidation();
      }
    } catch (e) {
      debugPrint('[CompletionVote] error: $e');
      _showError('Could not cast vote. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _validating.remove(actId));
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _approvalErrorMsg(String code) => switch (code) {
        'already_voted' => 'You already voted on this activity.',
        'voting_closed' => 'Voting is already closed.',
        'own_activity' => 'You cannot vote on your own activity.',
        _ => 'Could not cast vote. Please try again.',
      };

  String _completionErrorMsg(String code) => switch (code) {
        'already_voted' => 'You already validated this work.',
        'voting_closed' => 'Validation is already closed.',
        'own_work' => 'You cannot validate your own submitted work.',
        'xp_below_min' => 'Your XP proposal is below the minimum for this level.',
        'xp_above_max' => 'Your XP proposal exceeds the maximum for this level.',
        'event_not_started_yet' => 'The event has not started yet. Validation will open once the event begins.',
        _ => 'Could not cast vote. Please try again.',
      };

  String _fmtDate(String? raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  _WorkItem _parseWork(Map<String, dynamic> act) {
    final pl = act['preuve'] as List? ?? [];
    final td = act['type_activite'] as Map<String, dynamic>?;
    final deadlineRaw = act['priority_deadline'] as String?;
    final eventDateRaw = act['event_date'] as String?;
    return _WorkItem(
      id: act['id_act'] as int,
      creatorId: act['id_utilisateur'] as String? ?? '',
      title: act['titre'] as String? ?? '',
      location: act['localisation'] as String? ?? '',
      date: _fmtDate(act['datecreation'] as String?),
      xpLabel: act['xpfinal'] != null ? '+${act['xpfinal']} XP' : '',
      imageUrl: pl.isNotEmpty ? (pl.last['url'] as String? ?? '') : '',
      categoryName: td?['nom'] as String? ?? '',
      status: act['status'] as String? ?? '',
      priorityDeadline:
          deadlineRaw != null ? DateTime.tryParse(deadlineRaw) : null,
      activityMode: act['activity_mode'] as String? ?? 'single',
      eventDate: eventDateRaw != null
          ? DateTime.tryParse(eventDateRaw)?.toLocal()
          : null,
    );
  }

  // ── FIX: capture xpMin/xpMax/xpFinal from item BEFORE entering showDialog
  Future<int?> _askXpProposal(_ValidationItem item) async {
    final xpMin = item.xpMin;
    final xpMax = item.xpMax;
    final xpFinal = item.xpFinal;

    final ctrl = TextEditingController(text: xpFinal.toString());

    return showDialog<int>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;
          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Propose XP Reward',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: StatefulBuilder(
              builder: (context, setInnerState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'How many XP should the worker earn?\n'
                      'The final reward is the average of all YES votes.',
                      style: TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF2E7D32), width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.info_outline,
                              color: Color(0xFF2E7D32), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Allowed XP: $xpMin – $xpMax XP',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        setInnerState(() => errorText = null);
                      },
                      decoration: InputDecoration(
                        labelText: 'XP Proposal',
                        hintText: 'Enter XP between $xpMin and $xpMax',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixText: 'XP',
                        errorText: errorText,
                        errorStyle: const TextStyle(
                            color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () {
                  final val = int.tryParse(ctrl.text.trim());
                  if (val == null) {
                    setDialogState(() => errorText = 'Enter a valid number');
                    return;
                  }
                  if (val < xpMin) {
                    setDialogState(() =>
                        errorText = 'XP cannot be less than $xpMin');
                    return;
                  }
                  if (val > xpMax) {
                    setDialogState(() =>
                        errorText = 'XP cannot exceed $xpMax');
                    return;
                  }
                  Navigator.pop(context, val);
                },
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
              child: _buildPageHeader(),
            ),
            const SizedBox(height: 10),
            _buildSectionToggle(),
            const SizedBox(height: 6),
            Expanded(
              child: _sectionIndex == 0
                  ? _buildCommunitySection()
                  : _buildMyWorkSection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageHeader() {
    return Row(
      children: [
        const Icon(Icons.bar_chart_rounded, color: _deepGreen, size: 28),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Activities',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF163217),
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              _approvalItems = [];
              _loadingApproval = true;
              _validationLoaded = false;
              _historyLoaded = false;
              _priorityLoaded = false;
              _availableLoaded = false;
              _activeLoaded = false;
              _doneLoaded = false;
            });
            _loadApprovalFeed();
          },
          icon: const Icon(Icons.refresh_rounded, color: _deepGreen),
        ),
      ],
    );
  }

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
            _sectionBtn('Community', 0),
            _sectionBtn('My Work', 1),
          ],
        ),
      ),
    );
  }

  Widget _sectionBtn(String label, int idx) {
    final active = _sectionIndex == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_sectionIndex == idx) return;
          setState(() => _sectionIndex = idx);
          if (idx == 1 && !_priorityLoaded) _loadPriority();
          if (idx == 1 && !_availableLoaded) _loadAvailable();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? _deepGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : _deepGreen,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  // ─── Community Section ──────────────────────────────────────────────────────

  Widget _buildCommunitySection() {
    return Column(
      children: [
        _buildTabBar(
          controller: _communityTabController,
          tabs: const ['Approve', 'Validate', 'History'],
        ),
        Expanded(
          child: TabBarView(
            controller: _communityTabController,
            children: [
              _buildApprovalTab(),
              _buildValidationTab(),
              _buildHistoryTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Approval Tab ────────────────────────────────────────────────────────────

  Widget _buildApprovalTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: _loadApprovalFeed,
      child: _loadingApproval
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _approvalError != null
              ? _errorView(_approvalError!, _loadApprovalFeed)
              : _approvalItems.isEmpty
                  ? _emptyView(
                      Icons.how_to_vote_outlined,
                      'No activities awaiting approval.',
                      'Create an activity to get the community voting!',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                      itemCount: _approvalItems.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _buildApprovalCard(_approvalItems[i]),
                      ),
                    ),
    );
  }

  Widget _buildApprovalCard(_ApprovalItem item) {
    final isOwner = item.isOwner(_myId);
    final isVoting = _voting.contains(item.id);

    return GestureDetector(
      onTap: () {
        if (item.activityMode == 'group') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupActivityDetailPage(activityId: item.id),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ActivityDetailPage(activityId: item.id),
            ),
          );
        }
      },
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardImage(
              item.imageUrl,
              item.categoryName,
              item.xpLabel,
              closed: item.votingClosed,
              closedLabel: 'Voting Closed',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: _titleStyle),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _subStyle,
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    if (item.location.isNotEmpty)
                      _chip(Icons.location_on_rounded, item.location),
                    if (item.date.isNotEmpty)
                      _chip(Icons.calendar_today_rounded, item.date),
                    if (item.levelName.isNotEmpty)
                      _chip(Icons.military_tech_rounded, item.levelName),
                  ]),
                  const SizedBox(height: 14),
                  _voteProgress(item.approveCount, item.rejectCount, 2),
                  const SizedBox(height: 14),
                  if (isOwner)
                    _infoBanner(
                      Icons.person_rounded,
                      'This is your activity – you cannot vote on it.',
                      _deepGreen,
                    )
                  else if (item.votingClosed)
                    _infoBanner(
                      Icons.lock_rounded,
                      'Voting closed (${item.approveCount > item.rejectCount ? "Approved" : "Rejected"}).',
                      Colors.grey.shade600,
                    )
                  else if (item.hasVoted)
                    _infoBanner(
                      Icons.check_circle_rounded,
                      'You voted ${item.myVote == 1 ? "Approve" : "Reject"}.',
                      _green,
                    )
                  else if (isVoting)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: CircularProgressIndicator(
                            color: _green, strokeWidth: 2.5),
                      ),
                    )
                  else
                    Row(children: [
                      Expanded(
                        child: _actionBtn(
                          'Approve',
                          Icons.thumb_up_rounded,
                          _approveColor,
                          () => _castApprovalVote(item.id, 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionBtn(
                          'Reject',
                          Icons.thumb_down_rounded,
                          _rejectColor,
                          () => _castApprovalVote(item.id, -1),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Validation Tab ──────────────────────────────────────────────────────────

  Widget _buildValidationTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _validationLoaded = false;
        await _loadValidation();
      },
      child: _loadingValidation
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _validationItems.isEmpty
              ? _emptyView(
                  Icons.verified_outlined,
                  'No work awaiting validation.',
                  'Submitted completions will appear here for the community to review.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _validationItems.length,
                  itemBuilder: (_, i) {
                    final item = _validationItems[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ValidationDetailPage(
                              item: item,
                              myId: _myId,
                            ),
                          ),
                        ).then((voted) {
                          if (voted == true) {
                            _validationLoaded = false;
                            _loadValidation();
                          }
                        }),
                        child: _buildValidationCard(item),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildValidationCard(_ValidationItem item) {
    final isWorker = item.isWorker(_myId);
    final isCreator = item.isCreator(_myId);
    final cannotVote = isWorker || (item.isGroupEvent && isCreator);
    final isValidating = _validating.contains(item.id);

    return GestureDetector(
      onTap: item.isGroupEvent
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      GroupActivityDetailPage(activityId: item.id),
                ),
              ).then((_) {
                _validationLoaded = false;
                _loadValidation();
              })
          : null,
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardImage(
              item.imageUrl,
              item.categoryName,
              item.xpFinal > 0 ? '+${item.xpFinal} XP' : '',
              closed: false,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(item.title, style: _titleStyle)),
                    if (item.isGroupEvent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Group Event',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1565C0),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'Needs Validation',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ]),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _subStyle),
                  ],
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    if (item.location.isNotEmpty)
                      _chip(Icons.location_on_rounded, item.location),
                    if (item.date.isNotEmpty)
                      _chip(Icons.calendar_today_rounded, item.date),
                    if (item.categoryName.isNotEmpty)
                      _chip(Icons.category_rounded, item.categoryName),
                  ]),
                  if (item.beforeUrls.isNotEmpty ||
                      item.afterUrls.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _buildBeforeAfterPhotos(
                        item.beforeUrls, item.afterUrls),
                  ],
                  const SizedBox(height: 14),
                  _voteProgress(item.approveCount, item.rejectCount, 2),
                  const SizedBox(height: 14),
                  if (cannotVote)
                    _infoBanner(
                      isWorker
                          ? Icons.work_rounded
                          : Icons.groups_rounded,
                      isWorker
                          ? 'This is your submitted work.'
                          : 'You organised this event \u2014 you cannot vote on it.',
                      _deepGreen,
                    )
                  else if (item.hasVoted)
                    _infoBanner(
                      Icons.check_circle_rounded,
                      'You voted ${item.myVote == true ? "Approve" : "Reject"}.',
                      _green,
                    )
                  else if (isValidating)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: CircularProgressIndicator(
                            color: _green, strokeWidth: 2.5),
                      ),
                    )
                  else
                    Row(children: [
                      Expanded(
                        child: _actionBtn(
                          'Approve',
                          Icons.thumb_up_rounded,
                          _approveColor,
                          () async {
                            // Pass the item so xpMin/xpMax are captured safely
                            final xp = await _askXpProposal(item);
                            if (xp != null) {
                              _castCompletionVote(item.id, true, xp);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _actionBtn(
                          'Reject',
                          Icons.thumb_down_rounded,
                          _rejectColor,
                          () => _castCompletionVote(item.id, false, null),
                        ),
                      ),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeforeAfterPhotos(List<String> before, List<String> after) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (before.isNotEmpty) ...[
          Row(children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: _deepGreen,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Before',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B5E20),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          _photoRow(before, isAfter: false),
        ],
        if (after.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'After',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1565C0),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          _photoRow(after, isAfter: true),
        ],
      ],
    );
  }

  Widget _photoRow(List<String> urls, {required bool isAfter}) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final url = urls[i];
          return GestureDetector(
            onTap: () => _showFullscreenImage(ctx, url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Image.network(
                    url,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 90,
                      height: 90,
                      color: const Color(0xFFE8F5E9),
                      child: const Icon(Icons.broken_image_outlined,
                          color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xAA000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.zoom_in_rounded,
                          color: Colors.white, size: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFullscreenImage(BuildContext ctx, String url) {
    Navigator.push(
      ctx,
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, __, ___) => _FullscreenImage(url: url),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  // ── History Tab ─────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _historyLoaded = false;
        await _loadMyHistory();
      },
      child: _loadingHistory
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _myHistory.isEmpty
              ? _emptyView(
                  Icons.history_rounded,
                  'No activity history yet.',
                  'Create activities to see them here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _myHistory.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActivityDetailPage(
                              activityId: _myHistory[i].id),
                        ),
                      ),
                      child: _buildWorkCard(_myHistory[i], showStatus: true),
                    ),
                  ),
                ),
    );
  }

  // ─── My Work Section ────────────────────────────────────────────────────────

  Widget _buildMyWorkSection() {
    return Column(
      children: [
        _buildTabBar(
          controller: _workTabController,
          tabs: const ['Priority', 'Available', 'Active', 'Done', 'Events'],
        ),
        Expanded(
          child: TabBarView(
            controller: _workTabController,
            children: [
              _buildPriorityTab(),
              _buildAvailableTab(),
              _buildActiveTab(),
              _buildDoneTab(),
              _buildEventsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Priority Tab ────────────────────────────────────────────────────────────

  Widget _buildPriorityTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _priorityLoaded = false;
        await _loadPriority();
      },
      child: _loadingPriority
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _priorityItems.isEmpty
              ? _emptyView(
                  Icons.timer_outlined,
                  'No priority assignments.',
                  'When your activities are approved, you get first pick!',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _priorityItems.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildPriorityCard(_priorityItems[i]),
                  ),
                ),
    );
  }

  Widget _buildPriorityCard(_WorkItem item) {
    final remaining = item.timeLeft;
    final expired = remaining.isNegative || remaining.inSeconds == 0;
    final minutes = remaining.inMinutes.abs();
    final seconds = remaining.inSeconds.abs() % 60;
    final timerText = expired
        ? 'EXPIRED'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s left';
    final timerColor = expired
        ? Colors.red
        : remaining.inSeconds < 30
            ? Colors.orange
            : _green;

    return _card(
      borderColor: timerColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: timerColor.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Row(children: [
              Icon(Icons.timer_rounded, color: timerColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PRIORITY WINDOW  •  $timerText',
                  style: TextStyle(
                    color: timerColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: _titleStyle),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  if (item.location.isNotEmpty)
                    _chip(Icons.location_on_rounded, item.location),
                  if (item.xpLabel.isNotEmpty)
                    _chip(Icons.bolt_rounded, item.xpLabel),
                ]),
                const SizedBox(height: 14),
                if (expired)
                  _infoBanner(
                    Icons.timer_off_rounded,
                    'Time expired – activity is now open to all.',
                    Colors.orange,
                  )
                else
                  Row(children: [
                    Expanded(
                      child: _actionBtn(
                        'Accept',
                        Icons.check_circle_rounded,
                        _approveColor,
                        () => _acceptPriority(item.id),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _actionBtn(
                        'Decline',
                        Icons.cancel_rounded,
                        Colors.grey.shade600,
                        () => _declinePriority(item.id),
                      ),
                    ),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Available Tab ────────────────────────────────────────────────────────────

  Widget _buildAvailableTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _availableLoaded = false;
        await _loadAvailable();
      },
      child: _loadingAvailable
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _availableItems.isEmpty
              ? _emptyView(
                  Icons.search_off_rounded,
                  'No activities available to join.',
                  'Check back soon or create a new activity!',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _availableItems.length,
                  itemBuilder: (_, i) {
                    final item = _availableItems[i];
                    final isJoining = _joining.contains(item.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ActivityDetailPage(activityId: item.id),
                          ),
                        ).then((_) {
                          _availableLoaded = false;
                          _loadAvailable();
                        }),
                        child: _buildWorkCard(
                          item,
                          trailing: isJoining
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: _green, strokeWidth: 2),
                                )
                              : _actionBtn(
                                  'Join',
                                  Icons.play_circle_rounded,
                                  _green,
                                  () => _joinActivity(item.id),
                                ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  // ── Active Tab ──────────────────────────────────────────────────────────────

  Widget _buildActiveTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _activeLoaded = false;
        await _loadActive();
      },
      child: _loadingActive
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _activeItems.isEmpty
              ? _emptyView(
                  Icons.directions_run_rounded,
                  'No active work.',
                  'Join an available activity to start working!',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _activeItems.length,
                  itemBuilder: (_, i) {
                    final item = _activeItems[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ActivityDetailPage(activityId: item.id),
                          ),
                        ).then((_) {
                          _activeLoaded = false;
                          _loadActive();
                        }),
                        child: _buildWorkCard(
                          item,
                          trailing: _actionBtn(
                            'Submit Completion',
                            Icons.camera_alt_rounded,
                            const Color(0xFF1565C0),
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => WorkCompletionPage(
                                  activityId: item.id,
                                  activityTitle: item.title,
                                ),
                              ),
                            ).then((_) {
                              _activeLoaded = false;
                              _loadActive();
                            }),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  // ── Done Tab ─────────────────────────────────────────────────────────────────

  Widget _buildDoneTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _doneLoaded = false;
        await _loadDone();
      },
      child: _loadingDone
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _doneItems.isEmpty
              ? _emptyView(
                  Icons.task_alt_rounded,
                  'No completed work yet.',
                  'Finish activities to earn XP and see them here!',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _doneItems.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActivityDetailPage(
                              activityId: _doneItems[i].id),
                        ),
                      ),
                      child: _buildWorkCard(_doneItems[i], showStatus: true),
                    ),
                  ),
                ),
    );
  }

  // ── Events Tab ──────────────────────────────────────────────────────────────

  Widget _buildEventsTab() {
    return RefreshIndicator(
      color: _green,
      onRefresh: () async {
        _eventsLoaded = false;
        await _loadEvents();
      },
      child: _loadingEvents
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _eventItems.isEmpty
              ? _emptyView(
                  Icons.event_busy_outlined,
                  'No upcoming group events.',
                  'Create a group event or check back soon!',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                  itemCount: _eventItems.length,
                  itemBuilder: (_, i) {
                    final item = _eventItems[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                GroupActivityDetailPage(activityId: item.id),
                          ),
                        ).then((_) {
                          _eventsLoaded = false;
                          _loadEvents();
                        }),
                        child: _buildEventCard(item),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildEventCard(_WorkItem item) {
    final eventDate = item.eventDate;
    final timeLeft = item.timeUntilEvent;
    final hasStarted = item.eventHasStarted;

    Color timeColor;
    String timeLabel;
    if (hasStarted || item.status == 'in_progress') {
      timeLabel = 'In Progress';
      timeColor = const Color(0xFF1565C0);
    } else if (item.status == 'locked') {
      timeLabel = 'Locked – starts soon';
      timeColor = Colors.red.shade700;
    } else if (timeLeft.inMinutes <= 5) {
      timeLabel = 'Locking in ${timeLeft.inMinutes}m';
      timeColor = Colors.red.shade700;
    } else if (timeLeft.inHours < 1) {
      timeLabel = '${timeLeft.inMinutes}m remaining';
      timeColor = Colors.orange.shade700;
    } else if (timeLeft.inDays > 0) {
      timeLabel =
          '${timeLeft.inDays}d ${timeLeft.inHours.remainder(24)}h remaining';
      timeColor = _green;
    } else {
      timeLabel =
          '${timeLeft.inHours}h ${timeLeft.inMinutes.remainder(60)}m remaining';
      timeColor = _green;
    }

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dateLine = eventDate != null
        ? '${eventDate.day} ${months[eventDate.month - 1]}  '
            '${eventDate.hour.toString().padLeft(2, '0')}:'
            '${eventDate.minute.toString().padLeft(2, '0')}'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x141B5E20), blurRadius: 14, offset: Offset(0, 5)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: item.imageUrl.startsWith('http')
                      ? Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _eventGradient(),
                        )
                      : _eventGradient(),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: _badge('Group Event', _deepGreen, Colors.white),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _badge(
                    _statusLabel(item.status),
                    _statusColor(item.status),
                    Colors.white,
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    color: const Color(0xBB000000),
                    child: Row(children: [
                      Icon(
                        hasStarted || item.status == 'in_progress'
                            ? Icons.play_circle_rounded
                            : Icons.schedule_rounded,
                        color: timeColor,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          color: timeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (dateLine != null)
                        Text(
                          dateLine,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: _titleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (item.categoryName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.categoryName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A7D4E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (item.location.isNotEmpty)
                        _chip(Icons.location_on_rounded, item.location),
                      if (item.xpLabel.isNotEmpty)
                        _chip(Icons.bolt_rounded, item.xpLabel),
                      _chip(
                        Icons.arrow_forward_ios_rounded,
                        'Tap to view & join',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventGradient() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF388E3C), Color(0xFF1B5E20)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.groups_rounded, size: 52, color: Colors.white24),
        ),
      );

  // ─── Shared UI components ───────────────────────────────────────────────────

  Widget _buildWorkCard(
    _WorkItem item, {
    Widget? trailing,
    bool showStatus = false,
  }) {
    final statusColor = _statusColor(item.status);
    final statusLabel = _statusLabel(item.status);

    return _card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(22)),
            child: SizedBox(
              width: 90,
              height: trailing != null ? 110 : 90,
              child: item.imageUrl.startsWith('http')
                  ? Image.network(
                      item.imageUrl,
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
                  Row(children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _titleStyle,
                      ),
                    ),
                    if (showStatus) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ]),
                  if (item.categoryName.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.categoryName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4A7D4E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(spacing: 10, children: [
                    if (item.location.isNotEmpty)
                      _chip(Icons.location_on_rounded, item.location),
                    if (item.xpLabel.isNotEmpty)
                      _chip(Icons.bolt_rounded, item.xpLabel),
                  ]),
                  if (trailing != null) ...[
                    const SizedBox(height: 10),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'completed' => _approveColor,
        'rejected' => _rejectColor,
        'in_progress' => const Color(0xFF1565C0),
        'pending_validation' => const Color(0xFFF57F17),
        'locked' => Colors.red.shade700,
        'open' || 'approved' => const Color(0xFF00897B),
        'priority_pending' => const Color(0xFF7B1FA2),
        _ => Colors.grey,
      };

  String _statusLabel(String status) => switch (status) {
        'completed' => 'Completed',
        'rejected' => 'Rejected',
        'in_progress' => 'In Progress',
        'pending_validation' => 'Under Review',
        'locked' => 'Locked',
        'open' || 'approved' => 'Open',
        'priority_pending' => 'Priority',
        'waiting' => 'Pending Approval',
        _ => status,
      };

  // ── UI primitives ────────────────────────────────────────────────────────────

  static const TextStyle _titleStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: Color(0xFF163217),
  );
  static const TextStyle _subStyle = TextStyle(
    fontSize: 13,
    color: Color(0xFF607060),
    height: 1.4,
  );

  Widget _card({required Widget child, Color? borderColor}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 2)
            : null,
        boxShadow: const [
          BoxShadow(
              color: Color(0x141B5E20),
              blurRadius: 14,
              offset: Offset(0, 5)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }

  Widget _cardImage(
    String url,
    String category,
    String xpLabel, {
    required bool closed,
    String closedLabel = '',
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: Stack(
        children: [
          SizedBox(
            height: 160,
            width: double.infinity,
            child: url.startsWith('http')
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder(),
                  )
                : _imagePlaceholder(),
          ),
          if (category.isNotEmpty)
            Positioned(
              top: 10,
              left: 10,
              child: _badge(category, _deepGreen, Colors.white),
            ),
          if (xpLabel.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: _badge(xpLabel, const Color(0xFFFFB300),
                  const Color(0xFF4A3800)),
            ),
          if (closed)
            Positioned.fill(
              child: Container(
                color: const Color(0x99000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded,
                          color: Colors.white, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        closedLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
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
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFF607060)),
        const SizedBox(width: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFF607060)),
        ),
      ],
    );
  }

  Widget _voteProgress(int approve, int reject, int cap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(
            '${approve + reject} / $cap votes',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4A7D4E),
            ),
          ),
          const Spacer(),
          _dot(_approveColor),
          const SizedBox(width: 4),
          Text('$approve Approve',
              style: const TextStyle(
                  fontSize: 11,
                  color: _approveColor,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          _dot(_rejectColor),
          const SizedBox(width: 4),
          Text('$reject Reject',
              style: const TextStyle(
                  fontSize: 11,
                  color: _rejectColor,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          final aw = cap > 0 ? (approve / cap * w).clamp(0.0, w) : 0.0;
          final rw =
              cap > 0 ? (reject / cap * w).clamp(0.0, w - aw) : 0.0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              width: w,
              child: Stack(children: [
                Container(width: w, color: const Color(0xFFE0E0E0)),
                if (aw > 0)
                  Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Container(width: aw, color: _approveColor)),
                if (rw > 0)
                  Positioned(
                      left: aw,
                      top: 0,
                      bottom: 0,
                      child: Container(width: rw, color: _rejectColor)),
              ]),
            ),
          );
        }),
      ],
    );
  }

  Widget _dot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoBanner(IconData icon, String msg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            msg,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _emptyView(IconData icon, String title, String subtitle) {
    return ListView(children: [
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.grey.shade400, size: 64),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _errorView(String msg, VoidCallback retry) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        Text(msg),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: retry,
          style: ElevatedButton.styleFrom(
            backgroundColor: _deepGreen,
            foregroundColor: Colors.white,
          ),
          child: const Text('Retry'),
        ),
      ]),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: const Color(0xFFDDECCF),
      child: const Center(
        child: Icon(Icons.eco_rounded, color: Color(0xFF2E7D32), size: 36),
      ),
    );
  }

  Widget _buildTabBar({
    required TabController controller,
    required List<String> tabs,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TabBar(
          controller: controller,
          indicator: BoxDecoration(
            color: _deepGreen,
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          labelColor: Colors.white,
          unselectedLabelColor: _deepGreen,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          dividerColor: Colors.transparent,
          tabs: tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
    );
  }

  // ── Bottom navigation ────────────────────────────────────────────────────────

  Widget _buildFab() {
    return buildGlobalFab(context, onCreated: () {
      setState(() {
        _availableLoaded = false;
        _priorityLoaded = false;
      });
      _loadApprovalFeed();
    });
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
            _navItem(Icons.home_rounded, 0),
            _navItem(Icons.bar_chart_rounded, 1),
            const SizedBox(width: 56),
            _navItem(Icons.search_rounded, 2),
            _navItem(Icons.person_rounded, 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, int index) {
    final isActive = index == 1;
    return GestureDetector(
      onTap: () {
        if (index == 0) _pushPage(const HomePage());
        if (index == 2) _pushPage(const SearchPage());
        if (index == 3) _pushPage(const ProfilePage());
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isActive ? const Color(0xFFA5D6A7) : Colors.transparent,
        ),
        child: Icon(
          icon,
          color: isActive ? const Color(0xFF163D17) : Colors.white,
          size: 27,
        ),
      ),
    );
  }

  void _pushPage(Widget page) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

// ── Validation Detail Page ───────────────────────────────────────────────────

class ValidationDetailPage extends StatefulWidget {
  final _ValidationItem item;
  final String? myId;

  const ValidationDetailPage({
    super.key,
    required this.item,
    required this.myId,
  });

  @override
  State<ValidationDetailPage> createState() => _ValidationDetailPageState();
}

class _ValidationDetailPageState extends State<ValidationDetailPage> {
  static const _green = Color(0xFF2E7D32);
  static const _deepGreen = Color(0xFF1B5E20);
  static const _approveColor = Color(0xFF2E7D32);
  static const _rejectColor = Color(0xFFC62828);

  bool _voting = false;
  late bool? _myVote;
  late int _approveCount;
  late int _rejectCount;
  int _afterPage = 0;
  int _beforePage = 0;

  @override
  void initState() {
    super.initState();
    _myVote = widget.item.myVote;
    _approveCount = widget.item.approveCount;
    _rejectCount = widget.item.rejectCount;
  }

  bool get _isWorker =>
      widget.myId != null && widget.item.workerId == widget.myId;
  bool get _hasVoted => _myVote != null;

  // ── FIX: capture xpMin/xpMax/xpFinal BEFORE entering showDialog
  Future<int?> _askXpProposal() async {
    final xpMin = widget.item.xpMin;
    final xpMax = widget.item.xpMax;
    final xpFinal = widget.item.xpFinal;

    final ctrl = TextEditingController(text: xpFinal.toString());

    return showDialog<int>(
      context: context,
      builder: (_) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: const Text('Propose XP Reward',
                style: TextStyle(fontWeight: FontWeight.w800)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How many XP should the worker earn?\n'
                  'The final reward is the average of all YES votes.',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF2E7D32), width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFF2E7D32), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Allowed XP: $xpMin – $xpMax XP',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    setDialogState(() => errorText = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'XP Proposal',
                    hintText: 'Enter XP between $xpMin and $xpMax',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixText: 'XP',
                    errorText: errorText,
                    errorStyle:
                        const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () {
                  final val = int.tryParse(ctrl.text.trim());
                  if (val == null) {
                    setDialogState(
                        () => errorText = 'Enter a valid number');
                    return;
                  }
                  if (val < xpMin) {
                    setDialogState(() =>
                        errorText = 'XP cannot be less than $xpMin');
                    return;
                  }
                  if (val > xpMax) {
                    setDialogState(
                        () => errorText = 'XP cannot exceed $xpMax');
                    return;
                  }
                  Navigator.pop(context, val);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _castVote(bool approve, int? xpProposal) async {
    final uid = widget.myId;
    if (uid == null) return;
    setState(() => _voting = true);
    try {
      final dynamic rpcResult = await Supabase.instance.client.rpc(
        'cast_completion_vote',
        params: {
          'p_act_id': widget.item.id,
          'p_user_id': uid,
          'p_approve': approve,
          'p_xp_proposal': xpProposal,
        },
      );
      final res = (rpcResult as Map?)?.cast<String, dynamic>() ?? {};
      if (res['error'] != null) {
        _snack(_completionErrorMsg(res['error'] as String), isError: true);
        return;
      }
      setState(() {
        _myVote = approve;
        if (approve) {
          _approveCount++;
        } else {
          _rejectCount++;
        }
      });
      final decided = res['decided'] as bool? ?? false;
      if (decided) {
        final newStatus = res['new_status'] as String?;
        if (newStatus == 'completed') {
          final xp = res['xp_awarded'] as int? ?? 0;
          _snack('Work approved! Worker earned $xp XP.');
        } else {
          _snack('Work rejected – activity returned to open pool.',
              isError: true);
        }
        if (mounted) Navigator.pop(context, true);
      } else {
        _snack(approve
            ? 'Vote recorded: Approved ✓'
            : 'Vote recorded: Rejected ✗');
      }
    } catch (e) {
      _snack('Could not cast vote. Check your connection.', isError: true);
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : _green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _completionErrorMsg(String code) => switch (code) {
        'already_voted' => 'You already validated this work.',
        'voting_closed' => 'Validation is already closed.',
        'own_work' => 'You cannot validate your own submitted work.',
        'xp_below_min' =>
          'Your XP proposal is below the minimum for this level.',
        'xp_above_max' =>
          'Your XP proposal exceeds the maximum for this level.',
        'event_not_started_yet' =>
          'The event has not started yet. Validation will open once the event begins.',
        _ => 'Could not cast vote. Please try again.',
      };

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final totalVotes = _approveCount + _rejectCount;
    final approveRatio =
        totalVotes > 0 ? _approveCount / totalVotes : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F8F1),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: item.afterUrls.isNotEmpty ? 300 : 180,
            pinned: true,
            backgroundColor: _deepGreen,
            foregroundColor: Colors.white,
            title: const Text(
              'Validate Work',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: item.afterUrls.isNotEmpty
                  ? Stack(children: [
                      PageView.builder(
                        itemCount: item.afterUrls.length,
                        onPageChanged: (p) =>
                            setState(() => _afterPage = p),
                        itemBuilder: (_, i) => Image.network(
                          item.afterUrls[i],
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: _deepGreen,
                            child: const Icon(Icons.eco_rounded,
                                color: Colors.white38, size: 72),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.15),
                                Colors.black.withOpacity(0.55),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 90,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'AFTER',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ),
                      if (item.afterUrls.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              item.afterUrls.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 3),
                                width: _afterPage == i ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _afterPage == i
                                      ? Colors.white
                                      : Colors.white54,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ])
                  : Container(
                      color: _deepGreen,
                      child: const Center(
                        child: Icon(Icons.eco_rounded,
                            color: Colors.white24, size: 72),
                      ),
                    ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B2E1B),
                          ),
                        ),
                      ),
                      if (item.categoryName.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _deepGreen,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.categoryName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (item.location.isNotEmpty)
                      _metaChip(Icons.location_on_rounded, item.location,
                          const Color(0xFF1565C0)),
                    if (item.date.isNotEmpty)
                      _metaChip(Icons.calendar_today_rounded, item.date,
                          const Color(0xFF6A1B9A)),
                    if (item.xpFinal > 0)
                      _metaChip(Icons.star_rounded, '${item.xpFinal} XP',
                          const Color(0xFFE65100)),
                  ]),
                  if (item.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFD8EDD8)),
                      ),
                      child: Text(
                        item.description,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF3A4A3A),
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _sectionHeader('Work Evidence'),
                  const SizedBox(height: 16),
                  if (item.beforeUrls.isEmpty && item.afterUrls.isEmpty)
                    _noPhotoBanner()
                  else ...[
                    if (item.beforeUrls.isNotEmpty) ...[
                      _photoLabel('Before', const Color(0xFFB71C1C),
                          Icons.history_rounded),
                      const SizedBox(height: 10),
                      _photoGallery(
                        urls: item.beforeUrls,
                        currentPage: _beforePage,
                        onPageChanged: (p) =>
                            setState(() => _beforePage = p),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (item.afterUrls.isNotEmpty) ...[
                      _photoLabel('After', const Color(0xFF1565C0),
                          Icons.check_circle_outline_rounded),
                      const SizedBox(height: 10),
                      _photoGallery(
                        urls: item.afterUrls,
                        currentPage: _afterPage,
                        onPageChanged: (p) =>
                            setState(() => _afterPage = p),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                  _sectionHeader('Community Vote'),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: const Color(0xFFD8EDD8)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              const Icon(Icons.thumb_up_rounded,
                                  color: _approveColor, size: 16),
                              const SizedBox(width: 6),
                              Text('$_approveCount Approve',
                                  style: const TextStyle(
                                      color: _approveColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                            ]),
                            Text(
                              totalVotes == 0
                                  ? 'No votes yet'
                                  : '$totalVotes vote${totalVotes == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                            Row(children: [
                              Text('$_rejectCount Reject',
                                  style: const TextStyle(
                                      color: _rejectColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13)),
                              const SizedBox(width: 6),
                              const Icon(Icons.thumb_down_rounded,
                                  color: _rejectColor, size: 16),
                            ]),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: SizedBox(
                            height: 10,
                            child: LinearProgressIndicator(
                              value: approveRatio,
                              backgroundColor:
                                  _rejectColor.withOpacity(0.2),
                              valueColor:
                                  const AlwaysStoppedAnimation<Color>(
                                      _approveColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          totalVotes > 0
                              ? '${(approveRatio * 100).round()}% community approval'
                              : 'Be the first to vote',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isWorker)
                    _statusBanner(
                      Icons.work_rounded,
                      'This is your submitted work. You cannot vote on it.',
                      _deepGreen,
                    )
                  else if (_hasVoted)
                    _statusBanner(
                      Icons.check_circle_rounded,
                      'You voted: ${_myVote == true ? "Approve ✓" : "Reject ✗"}',
                      _myVote == true ? _green : _rejectColor,
                    )
                  else if (_voting)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(
                            color: _green, strokeWidth: 2.5),
                      ),
                    )
                  else ...[
                    _voteButton(
                      label: 'Approve Work',
                      icon: Icons.thumb_up_rounded,
                      color: _approveColor,
                      onTap: () async {
                        final xp = await _askXpProposal();
                        if (xp != null && mounted) _castVote(true, xp);
                      },
                    ),
                    const SizedBox(height: 10),
                    _voteButton(
                      label: 'Reject Work',
                      icon: Icons.thumb_down_rounded,
                      color: _rejectColor,
                      onTap: () => _castVote(false, null),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper widgets ──────────────────────────────────────────────────────────

  Widget _sectionHeader(String text) {
    return Row(children: [
      Container(
        width: 4,
        height: 20,
        decoration: BoxDecoration(
          color: _deepGreen,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 10),
      Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1B2E1B),
        ),
      ),
    ]);
  }

  Widget _photoLabel(String label, Color color, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    ]);
  }

  Widget _photoGallery({
    required List<String> urls,
    required int currentPage,
    required ValueChanged<int> onPageChanged,
  }) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 230,
            child: PageView.builder(
              itemCount: urls.length,
              onPageChanged: onPageChanged,
              itemBuilder: (ctx, i) => GestureDetector(
                onTap: () => Navigator.push(
                  ctx,
                  PageRouteBuilder(
                    opaque: false,
                    pageBuilder: (_, __, ___) =>
                        _FullscreenImage(url: urls[i]),
                    transitionsBuilder: (_, anim, __, child) =>
                        FadeTransition(opacity: anim, child: child),
                  ),
                ),
                child: Image.network(
                  urls[i],
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) =>
                      progress == null
                          ? child
                          : Container(
                              color: const Color(0xFFE8F5E9),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: _green, strokeWidth: 2),
                              ),
                            ),
                  errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFE8F5E9),
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.grey, size: 48),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              urls.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: currentPage == i ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: currentPage == i
                      ? _deepGreen
                      : const Color(0xFFB2DFDB),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner(IconData icon, String msg, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ]),
    );
  }

  Widget _noPhotoBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8EDD8)),
      ),
      child: const Column(
        children: [
          Icon(Icons.image_not_supported_outlined,
              color: Colors.grey, size: 40),
          SizedBox(height: 8),
          Text('No proof photos uploaded.',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _voteButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

// ── Fullscreen image viewer ──────────────────────────────────────────────────

class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

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
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
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
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white),
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