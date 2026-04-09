import 'dart:ui';
import 'package:flutter/material.dart';
import 'activity.dart';
import 'activity_detail.dart';
import 'profile.dart';
import 'search.dart';

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

  final List<Map<String, dynamic>> categories = [
    {"icon": Icons.park, "title": "Afforestation"},
    {"icon": Icons.cleaning_services, "title": "Cleaning"},
    {"icon": Icons.recycling, "title": "Recycling"},
    {"icon": Icons.water_drop, "title": "Water"},
    {"icon": Icons.energy_savings_leaf, "title": "Energy"},
    {"icon": Icons.eco, "title": "Awareness"},
    {"icon": Icons.forest, "title": "Nature"},
    {"icon": Icons.public, "title": "Climate"},
    {"icon": Icons.solar_power, "title": "Solar"},
    {"icon": Icons.compost, "title": "Compost"},
    {"icon": Icons.grass, "title": "Green Parks"},
    {"icon": Icons.bolt, "title": "Eco Tech"},
    {"icon": Icons.electric_bike, "title": "Mobility"},
    {"icon": Icons.agriculture, "title": "Farming"},
    {"icon": Icons.pets, "title": "Wildlife"},
    {"icon": Icons.volunteer_activism, "title": "Volunteering"},
    {"icon": Icons.factory_outlined, "title": "Pollution"},
    {"icon": Icons.wb_sunny_outlined, "title": "Heat Action"},
  ];

  final List<Map<String, String>> activities = [
    {
      "title": "Tree Plantation",
      "location": "Bejaia",
      "date": "12 Apr 2026",
      "exp": "+50 XP",
    },
    {
      "title": "Beach Cleaning",
      "location": "Algiers",
      "date": "15 Apr 2026",
      "exp": "+30 XP",
    },
    {
      "title": "Recycle Mission",
      "location": "Setif",
      "date": "18 Apr 2026",
      "exp": "+20 XP",
    },
    {
      "title": "River Protection",
      "location": "Constantine",
      "date": "20 Apr 2026",
      "exp": "+45 XP",
    },
    {
      "title": "Solar Camp",
      "location": "Oran",
      "date": "23 Apr 2026",
      "exp": "+60 XP",
    },
    {
      "title": "Eco Awareness Day",
      "location": "Tizi Ouzou",
      "date": "26 Apr 2026",
      "exp": "+25 XP",
    },
    {
      "title": "City Bike Challenge",
      "location": "Blida",
      "date": "29 Apr 2026",
      "exp": "+40 XP",
    },
    {
      "title": "School Recycling",
      "location": "Annaba",
      "date": "02 May 2026",
      "exp": "+35 XP",
    },
  ];

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  List<Map<String, dynamic>> get _filteredCategories {
    if (_searchQuery.isEmpty) {
      return categories;
    }
    return categories
        .where(
          (item) =>
              item["title"].toString().toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  List<Map<String, String>> get _filteredActivities {
    if (_searchQuery.isEmpty) {
      return activities;
    }
    return activities.where((act) {
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Categories",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                _searchQuery.isEmpty ? "Swipe ->" : "Results",
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (filteredCategories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text("No categories found"),
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
                return Container(
                  width: 120,
                  margin: const EdgeInsets.only(left: 16),
                  decoration: BoxDecoration(
                    color: _lightGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item["icon"], size: 40, color: _deepGreen),
                      const SizedBox(height: 10),
                      Text(item["title"]),
                    ],
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
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "The Closest Activities",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        if (filteredActivities.isEmpty)
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
                    pageBuilder: (_, __, ___) => const ActivityDetailPage(),
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
                    image: const DecorationImage(
                      image: AssetImage("assets/images.jfif"),
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
                            Text(
                              act["location"]!,
                              style: const TextStyle(color: Colors.white70),
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
                            Text(
                              act["date"]!,
                              style: const TextStyle(color: Colors.white70),
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
