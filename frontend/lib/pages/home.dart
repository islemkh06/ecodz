import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'activity.dart';
import 'activity_detail.dart';
import 'profile.dart';
import 'search.dart';
import '../widgets/create_activity_modal.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _lightGreen = Color(0xFFDDECCF);
  static const Color _softGreen = Color(0xFFA5D6A7);
  static const Color _surface = Color(0xFFF5FBF4);
  int _currentTab = 0;
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, String>> _activities = [];
  bool _loadingActivities = false;

  // Categories loaded from type_activite table
  List<Map<String, dynamic>> _categories = [];
  bool _loadingCategories = false;
  int? _selectedCategoryId;

  // Maps icone string (stored in DB) to a Flutter IconData
  static const Map<String, IconData> _iconMap = {
    'park': Icons.park,
    'cleaning_services': Icons.cleaning_services,
    'recycling': Icons.recycling,
    'water_drop': Icons.water_drop,
    'energy_savings_leaf': Icons.energy_savings_leaf,
    'eco': Icons.eco,
    'forest': Icons.forest,
    'public': Icons.public,
    'solar_power': Icons.solar_power,
    'compost': Icons.compost,
    'grass': Icons.grass,
    'bolt': Icons.bolt,
    'electric_bike': Icons.electric_bike,
    'agriculture': Icons.agriculture,
    'pets': Icons.pets,
    'volunteer_activism': Icons.volunteer_activism,
    'factory': Icons.factory_outlined,
    'wb_sunny': Icons.wb_sunny_outlined,
    'sports_soccer': Icons.sports_soccer,
    'school': Icons.school,
    'health_and_safety': Icons.health_and_safety,
  };

  static IconData _iconFromName(String? name) =>
      _iconMap[name] ?? Icons.eco_rounded;

  @override
  void initState() {
    super.initState();
    _loadActivities();
    _loadCategories();
  }

  Future<void> _loadActivities() async {
    setState(() => _loadingActivities = true);
    try {
      final data = await Supabase.instance.client
          .from('activite')
          .select('*, preuve(url)')
          .eq('status', 'approved')
          .order('datecreation', ascending: false);

      final loaded = <Map<String, String>>[];
      for (final row in data as List) {
        final xp = row['xpfinal'];
        final dateRaw = row['datecreation'] as String?;
        String dateStr = '';
        if (dateRaw != null) {
          final dt = DateTime.tryParse(dateRaw);
          if (dt != null) {
            dateStr = '${dt.day} ${_monthAbbr(dt.month)} ${dt.year}';
          }
        }
        final preuveList = row['preuve'] as List? ?? [];
        final imageUrl = preuveList.isNotEmpty
            ? (preuveList.first['url'] as String? ?? '')
            : '';
        loaded.add({
          'id': (row['id_act'] as int? ?? 0).toString(),
          'title': row['titre'] as String? ?? '',
          'location': row['localisation'] as String? ?? '',
          'date': dateStr,
          'exp': xp != null ? '+$xp XP' : '',
          'id_type_act': (row['id_type_act'] as int? ?? 0).toString(),
          'image_url': imageUrl,
        });
      }
      if (mounted) setState(() => _activities = loaded);
    } catch (_) {
      // Keep existing list on error
    } finally {
      if (mounted) setState(() => _loadingActivities = false);
    }
  }

  String _monthAbbr(int month) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return m[month - 1];
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final data = await Supabase.instance.client
          .from('type_activite')
          .select()
          .order('id_type_act');
      if (mounted) {
        setState(() {
          _categories = (data as List)
              .map((row) => {
                    'id': row['id_type_act'],
                    'title': row['nom'] as String? ?? '',
                    'icon': _iconFromName(row['icone'] as String?),
                  })
              .toList();
        });
      }
    } catch (_) {
      // Fall back to empty list; UI handles empty state
    } finally {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  void _openCreateModal() {
    showDialog(
      context: context,
      builder: (_) => CreateActivityModal(onActivityCreated: _loadActivities),
    );
  }

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  List<Map<String, dynamic>> get _filteredCategories {
    if (_searchQuery.isEmpty) {
      return _categories;
    }
    return _categories
        .where(
          (item) =>
              item['title'].toString().toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  List<Map<String, String>> get _filteredActivities {
    var list = _activities;
    if (_selectedCategoryId != null) {
      list = list
          .where((a) => a['id_type_act'] == _selectedCategoryId.toString())
          .toList();
    }
    if (_searchQuery.isEmpty) return list;
    return list.where((act) {
      final title = act["title"]?.toLowerCase() ?? "";
      final location = act["location"]?.toLowerCase() ?? "";
      final date = act["date"]?.toLowerCase() ?? "";
      final exp = act["exp"]?.toLowerCase() ?? "";
      return title.contains(_searchQuery) ||
          location.contains(_searchQuery) ||
          date.contains(_searchQuery) ||
          exp.contains(_searchQuery);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildSearch(),
              _buildCategories(),
              _buildActivities(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFab() {
    return GestureDetector(
      onTap: _openCreateModal,
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
    final bool active = _currentTab == index;

    return GestureDetector(
      onTap: () {
        if (index == 1) {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              transitionDuration: const Duration(milliseconds: 350),
              pageBuilder: (_, __, ___) => const ActivityPage(),
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
          return;
        }
        if (index == 2) {
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
          return;
        }
        if (index == 3) {
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
          return;
        }
        setState(() => _currentTab = index);
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 118,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0x22FFFFFF),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/level1.png', fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hi, Khaled',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Level 1',
                  style: TextStyle(
                    color: Color(0xFFE6F5E6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(
                    value: 1567 / 2000,
                    minHeight: 8,
                    color: Colors.white,
                    backgroundColor: Color(0x55FFFFFF),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '1567 / 2000 XP',
                  style: TextStyle(
                    color: Color(0xFFE6F5E6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatChip(
                        label: 'Activity Completed',
                        value: '1',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatChip(
                        label: 'Activity to Complete',
                        value: '1',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({required String label, required String value}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0x22FFFFFF),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                style: const TextStyle(
                  color: Color(0xFFE8F8E8),
                  fontSize: 10,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ SEARCH
  Widget _buildSearch() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _lightGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          icon: Icon(Icons.search),
          hintText: "Search Places",
          border: InputBorder.none,
        ),
      ),
    );
  }

  // ✅ SCROLL HORIZONTAL (MORE CATEGORIES)
  Widget _buildCategories() {
    final filteredCategories = _filteredCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Categories",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                "Swipe ->",
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (_selectedCategoryId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.filter_list,
                    size: 16, color: Color(0xFF1B5E20)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Filtered: ${_categories.firstWhere((c) => c['id'] == _selectedCategoryId, orElse: () => {'title': ''})['title']}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1B5E20),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selectedCategoryId = null),
                  child: const Row(
                    children: [
                      Icon(Icons.clear, size: 14, color: Colors.black54),
                      SizedBox(width: 2),
                      Text(
                        'Clear',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_loadingCategories)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
              ),
            )
          else if (filteredCategories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No categories found'),
            )
          else
            SizedBox(
              height: 140,
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 16),
                itemCount: filteredCategories.length,
                itemBuilder: (context, i) {
                  final item = filteredCategories[i];
                  final isSelected = _selectedCategoryId == item['id'];
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedCategoryId =
                          isSelected ? null : item['id'] as int?;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 120,
                      margin: const EdgeInsets.only(left: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? _deepGreen : _lightGreen,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: isSelected
                            ? const [
                                BoxShadow(
                                  color: Color(0x3327502E),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 40,
                            color: isSelected ? Colors.white : _deepGreen,
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              item['title'] as String,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      ],
    );
  }

  // ✅ ACTIVITIES WITH IMAGE + TEXT OVERLAY
  Widget _buildActivities() {
    final filteredActivities = _filteredActivities;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedCategoryId == null
                    ? 'The Closest Activities'
                    : 'Activities Found',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_selectedCategoryId != null)
                Text(
                  '${_filteredActivities.length} result${_filteredActivities.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1B5E20),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),

        if (_loadingActivities)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
            ),
          )
        else if (filteredActivities.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text("No activities found"),
          )
        else
          Column(
            children: filteredActivities.map((act) {
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 350),
                    pageBuilder: (_, __, ___) => ActivityDetailPage(
                      activityId: int.tryParse(act['id'] ?? '0'),
                    ),
                    transitionsBuilder: (_, animation, __, child) {
                      final slide =
                          Tween<Offset>(
                            begin: const Offset(0, 0.06),
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
                ),
                child: Container(
                  height: 230,
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    image: DecorationImage(
                      image: (act['image_url']?.isNotEmpty == true)
                          ? NetworkImage(act['image_url']!) as ImageProvider
                          : const AssetImage('assets/images.jfif'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black54],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          act["title"]!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                act["location"]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_month,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                act["date"]!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          act["exp"]!,
                          style: const TextStyle(
                            color: Colors.lightGreenAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}
