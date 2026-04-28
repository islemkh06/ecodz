import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/create_activity_modal.dart';
import 'activity.dart';
import 'activity_detail.dart';
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

  // Loaded from Supabase
  List<Map<String, dynamic>> _allActivities = [];
  List<String> _typeFilters = ['All'];
  bool _loadingActivities = false;
  bool _loadingFilters = false;

  // GPS state
  bool _detectingLocation = false;
  String? _detectedCity;
  LatLng? _userPosition;

  int _currentIndex = 2;
  String _selectedFilter = 'All';
  bool _showNearbySheet = true;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _loadActivities();
  }

  Future<void> _loadFilters() async {
    setState(() => _loadingFilters = true);
    try {
      final data = await Supabase.instance.client
          .from('type_activite')
          .select('nom')
          .order('id_type_act');
      if (mounted) {
        setState(() {
          _typeFilters = [
            'All',
            ...(data as List).map((r) => r['nom'] as String? ?? ''),
          ];
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingFilters = false);
    }
  }

  Future<void> _loadActivities() async {
    setState(() => _loadingActivities = true);
    try {
      var query = Supabase.instance.client
          .from('activite')
          .select('id_act, titre, localisation, latitude, longitude, type_activite(nom)')
          .inFilter('status', ['open', 'approved', 'priority_pending']);

      final q = _searchController.text.trim();
      if (q.isNotEmpty) {
        query = query.or('titre.ilike.%$q%,localisation.ilike.%$q%');
      }

      final data = await query.order('datecreation', ascending: false);

      if (mounted) {
        setState(() {
          _allActivities = (data as List).map((row) {
            final typeData = row['type_activite'] as Map<String, dynamic>?;
            final lat = (row['latitude'] as num?)?.toDouble();
            final lng = (row['longitude'] as num?)?.toDouble();
            return {
              'id': row['id_act'] as int? ?? 0,
              'title': row['titre'] as String? ?? '',
              'category': typeData?['nom'] as String? ?? '',
              'location': row['localisation'] as String? ?? '',
              'point': (lat != null && lng != null)
                  ? LatLng(lat, lng)
                  : null,
            };
          }).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingActivities = false);
    }
  }

  // GPS — detect current location, reverse geocode, auto-fill search, center map
  Future<void> _detectMyLocation() async {
    setState(() => _detectingLocation = true);
    try {
      // Check & request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permission == LocationPermission.deniedForever
                    ? 'Location permission permanently denied. Enable it in app settings.'
                    : 'Location permission denied.',
              ),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Check if GPS service is enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS is disabled. Please enable location services.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // Get coordinates
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final userLatLng = LatLng(pos.latitude, pos.longitude);

      // Reverse geocode to city name
      String cityName = '';
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          cityName = p.locality?.isNotEmpty == true
              ? p.locality!
              : (p.administrativeArea ?? '');
        }
      } catch (_) {
        // Reverse geocode failure is non-fatal — keep coordinates, skip city
      }

      if (mounted) {
        setState(() {
          _userPosition = userLatLng;
          _detectedCity = cityName.isNotEmpty ? cityName : null;
        });

        // Auto-fill the search field with the detected city
        if (cityName.isNotEmpty) {
          _searchController.text = cityName;
        }

        // Center map on user
        _mapController.move(userLatLng, 13);

        // Reload activities filtered by location
        _loadActivities();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not detect location: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  // Distance in km between user and activity (null if no user position or no point)
  double? _distanceTo(Map<String, dynamic> activity) {
    final userPos = _userPosition;
    final point = activity['point'] as LatLng?;
    if (userPos == null || point == null) return null;
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, userPos, point);
  }

  List<Map<String, dynamic>> get _filteredActivities {
    var list = _allActivities.where((activity) {
      final matchesFilter = _selectedFilter == 'All' ||
          activity['category'] == _selectedFilter;
      return matchesFilter;
    }).toList();

    // If user position is known, sort nearest first
    if (_userPosition != null) {
      list.sort((a, b) {
        final da = _distanceTo(a);
        final db = _distanceTo(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    }

    return list;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────

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
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ecodz',
              ),
              MarkerLayer(
                markers: filteredActivities
                    .where((a) => a['point'] != null)
                    .map((activity) {
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

  // ── Search bar ────────────────────────────────────────────────

  Widget _buildTopSearchBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                  onChanged: (_) => _loadActivities(),
                  onSubmitted: (_) => _loadActivities(),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.search_rounded),
                    hintText: 'Search activities near you',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // GPS "Use My Location" button
            GestureDetector(
              onTap: _detectingLocation ? null : _detectMyLocation,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _userPosition != null
                      ? const Color(0xFF43A047)
                      : const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2A000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: _detectingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(
                        Icons.my_location_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () =>
                  setState(() => _showNearbySheet = !_showNearbySheet),
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
        ),
        // Detected city label shown below the search bar
        if (_detectedCity != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 14, color: Color(0xFF43A047)),
                const SizedBox(width: 4),
                Text(
                  'Using: $_detectedCity',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF43A047),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _userPosition = null;
                      _detectedCity = null;
                    });
                    _searchController.clear();
                    _loadActivities();
                  },
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Nearby sheet ─────────────────────────────────────────────

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
          if (_loadingActivities)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            )
          else if (activities.isEmpty)
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
    final dist = _distanceTo(activity);
    return GestureDetector(
      onTap: () {
        final id = activity['id'] as int?;
        if (id == null) return;
        Navigator.push(
          context,
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 350),
            pageBuilder: (_, __, ___) =>
                ActivityDetailPage(activityId: id),
            transitionsBuilder: (_, animation, __, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Container(
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
                  if (dist != null)
                    Text(
                      dist < 1
                          ? '${(dist * 1000).round()} m away'
                          : '${dist.toStringAsFixed(1)} km away',
                      style: const TextStyle(
                        color: Color(0xFF1565C0),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filters = _loadingFilters ? ['All'] : _typeFilters;
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
                    children: filters.map((filter) {
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
      },
    );
  }

  Widget _buildFab() {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => CreateActivityModal(onActivityCreated: () {
          // Optionally refresh search results here
          setState(() {});
        }),
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
