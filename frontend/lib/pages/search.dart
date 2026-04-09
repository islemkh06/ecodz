import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'activity.dart';
import 'home.dart';
import 'profile.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _green = Color(0xFF2E7D32);
  static const Color _softGreen = Color(0xFFA5D6A7);
  static const Color _surface = Color(0xFFF5FBF4);

  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  final List<Map<String, dynamic>> _activities = [
    {
      'title': 'Afforestation',
      'category': 'Nature',
      'location': 'Bejaia Forest',
      'distance': '1.2 km',
      'point': LatLng(36.7525, 5.0843),
    },
    {
      'title': 'Beach Cleaning',
      'category': 'Cleaning',
      'location': 'Tichy Beach',
      'distance': '3.8 km',
      'point': LatLng(36.6718, 5.1517),
    },
    {
      'title': 'Recycling Drop',
      'category': 'Recycling',
      'location': 'Ihaddaden',
      'distance': '2.1 km',
      'point': LatLng(36.7443, 5.0631),
    },
    {
      'title': 'Water Protection',
      'category': 'Water',
      'location': 'Soummam River',
      'distance': '4.5 km',
      'point': LatLng(36.7205, 4.9998),
    },
  ];

  int _currentIndex = 2;
  String _selectedFilter = 'All';
  bool _showNearbySheet = true;

  String get _query => _searchController.text.trim().toLowerCase();

  List<String> get _filters => [
    'All',
    'Nature',
    'Cleaning',
    'Recycling',
    'Water',
  ];

  List<Map<String, dynamic>> get _filteredActivities {
    return _activities.where((activity) {
      final matchesQuery =
          _query.isEmpty ||
          activity['title'].toString().toLowerCase().contains(_query) ||
          activity['location'].toString().toLowerCase().contains(_query);
      final matchesFilter =
          _selectedFilter == 'All' || activity['category'] == _selectedFilter;
      return matchesQuery && matchesFilter;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredActivities = _filteredActivities;

    return Scaffold(
      backgroundColor: _surface,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _buildFab(),
      bottomNavigationBar: _buildBottomBar(),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(36.7525, 5.0843),
              initialZoom: 11.8,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ecodz',
              ),
              MarkerLayer(
                markers: filteredActivities.map((activity) {
                  return Marker(
                    point: activity['point'] as LatLng,
                    width: 88,
                    height: 88,
                    child: _buildMarker(activity['title'] as String),
                  );
                }).toList(),
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                children: [
                  _buildTopSearchBar(),
                  const Spacer(),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, animation) {
                      return SizeTransition(
                        sizeFactor: animation,
                        axisAlignment: -1,
                        child: FadeTransition(opacity: animation, child: child),
                      );
                    },
                    child: _showNearbySheet
                        ? _buildNearbySheet(filteredActivities)
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 96),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A234A29),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                icon: Icon(Icons.search_rounded),
                hintText: 'Search activities near you',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => setState(() => _showNearbySheet = !_showNearbySheet),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _green,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F214728),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              _showNearbySheet
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openFilterSheet,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _deepGreen,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F214728),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.tune_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildNearbySheet(List<Map<String, dynamic>> activities) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F234629),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nearby Activities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF173D1B),
                ),
              ),
              Text(
                '${activities.length} found',
                style: const TextStyle(
                  color: Color(0xFF507258),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No activity matches your search or filter.',
                style: TextStyle(color: Color(0xFF507258)),
              ),
            )
          else
            ...activities.map(_buildNearbyItem),
        ],
      ),
    );
  }

  Widget _buildNearbyItem(Map<String, dynamic> activity) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8F1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.eco_rounded, color: _deepGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity['title'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF173D1B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  activity['location'] as String,
                  style: const TextStyle(color: Color(0xFF507258)),
                ),
              ],
            ),
          ),
          Text(
            activity['distance'] as String,
            style: const TextStyle(
              color: Color(0xFF1F6D2D),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarker(String title) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F24472A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF173D1B),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.location_on_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
      ],
    );
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter activities',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _filters.map((filter) {
                  final selected = filter == _selectedFilter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedFilter = filter);
                      Navigator.pop(context);
                    },
                    selectedColor: _softGreen,
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
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
          return;
        }
        if (index == 1) {
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
        setState(() => _currentIndex = index);
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
