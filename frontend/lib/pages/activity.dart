import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home.dart';
import 'profile.dart';
import 'search.dart';
import 'work_completion_page.dart';
import '../widgets/create_activity_modal.dart';
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
      );
}

class _ValidationItem {
  final int id;
  final String workerId;
  final String title;
  final String description;
  final String location;
  final String date;
  final int xpFinal;
  final String imageUrl;
  final String categoryName;
  final int approveCount;
  final int rejectCount;
  final bool? myVote;

  const _ValidationItem({
    required this.id,
    required this.workerId,
    required this.title,
    required this.description,
    required this.location,
    required this.date,
    required this.xpFinal,
    required this.imageUrl,
    required this.categoryName,
    required this.approveCount,
    required this.rejectCount,
    this.myVote,
  });

  int get totalVotes => approveCount + rejectCount;
  bool get hasVoted => myVote != null;
  bool isWorker(String? uid) => uid != null && workerId == uid;
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
  });

  Duration get timeLeft =>
      priorityDeadline != null
          ? priorityDeadline!.difference(DateTime.now())
          : Duration.zero;
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

  // ── Community tabs ──────────────────────────────────────────────────────────
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

  // ── My Work tabs ────────────────────────────────────────────────────────────
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

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _communityTabController = TabController(length: 3, vsync: this);
    _communityTabController.addListener(_onCommunityTabChange);
    _workTabController = TabController(length: 4, vsync: this);
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
            'datecreation, xpfinal, type_activite(nom), '
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
            'id_act, assigned_worker_id, titre, description, localisation, '
            'datecreation, xpfinal, type_activite(nom), preuve(url)',
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
        final pl = act['preuve'] as List? ?? [];
        final td = act['type_activite'] as Map<String, dynamic>?;
        return _ValidationItem(
          id: id,
          workerId: act['assigned_worker_id'] as String? ?? '',
          title: act['titre'] as String? ?? '',
          description: act['description'] as String? ?? '',
          location: act['localisation'] as String? ?? '',
          date: _fmtDate(act['datecreation'] as String?),
          xpFinal: (act['xpfinal'] as num?)?.toInt() ?? 0,
          imageUrl: pl.isNotEmpty ? (pl.last['url'] as String? ?? '') : '',
          categoryName: td?['nom'] as String? ?? '',
          approveCount: appC[id] ?? 0,
          rejectCount: rejC[id] ?? 0,
          myVote: myV[id],
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
            'xpfinal, status, type_activite(nom), preuve(url)',
          )
          .inFilter('status', ['open', 'approved'])
          .neq('id_utilisateur', uid)
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
    );
  }

  Future<int?> _askXpProposal(int suggestedXp) async {
    final ctrl = TextEditingController(text: suggestedXp.toString());
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'XP Proposal',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixText: 'XP',
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
            style: FilledButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              Navigator.pop(context, val);
            },
            child: const Text('Confirm'),
          ),
        ],
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

    return _card(
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
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: _buildValidationCard(_validationItems[i]),
                  ),
                ),
    );
  }

  Widget _buildValidationCard(_ValidationItem item) {
    final isWorker = item.isWorker(_myId);
    final isValidating = _validating.contains(item.id);

    return _card(
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
                const SizedBox(height: 14),
                _voteProgress(item.approveCount, item.rejectCount, 2),
                const SizedBox(height: 14),
                if (isWorker)
                  _infoBanner(
                    Icons.work_rounded,
                    'This is your submitted work.',
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
                          final xp = await _askXpProposal(item.xpFinal);
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
                    child: _buildWorkCard(_myHistory[i], showStatus: true),
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
          tabs: const ['Priority', 'Available', 'Active', 'Done'],
        ),
        Expanded(
          child: TabBarView(
            controller: _workTabController,
            children: [
              _buildPriorityTab(),
              _buildAvailableTab(),
              _buildActiveTab(),
              _buildDoneTab(),
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
    final expired =
        remaining.isNegative || remaining.inSeconds == 0;
    final minutes = remaining.inMinutes.abs();
    final seconds = remaining.inSeconds.abs() % 60;
    final timerText =
        expired ? 'EXPIRED' : '${minutes}m ${seconds.toString().padLeft(2, '0')}s left';
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
                    child: _buildWorkCard(_doneItems[i], showStatus: true),
                  ),
                ),
    );
  }

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
        'open' || 'approved' => const Color(0xFF00897B),
        'priority_pending' => const Color(0xFF7B1FA2),
        _ => Colors.grey,
      };

  String _statusLabel(String status) => switch (status) {
        'completed' => 'Completed',
        'rejected' => 'Rejected',
        'in_progress' => 'In Progress',
        'pending_validation' => 'Under Review',
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
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => CreateActivityModal(onActivityCreated: () {}),
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
                color: Color(0x4427502E), blurRadius: 20, offset: Offset(0, 8))
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
          color: isActive
              ? const Color(0xFFA5D6A7)
              : Colors.transparent,
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
