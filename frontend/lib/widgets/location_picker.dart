import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Holds a resolved location: human-readable address + coordinates.
class LocationResult {
  final String address;
  final double latitude;
  final double longitude;

  const LocationResult({
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  /// "lat,lng" string useful for display fallback.
  String get coordString =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

/// Full-screen map screen.  The user taps to drop a pin; Nominatim is used
/// to reverse-geocode the address.  Resolves to a [LocationResult] on confirm.
class LocationPickerPage extends StatefulWidget {
  final LocationResult? initial;

  const LocationPickerPage({super.key, this.initial});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const _defaultCenter = LatLng(36.7525, 5.0843);

  final _mapController = MapController();
  LatLng? _picked;
  String? _address;
  bool _geocoding = false;
  bool _gettingLocation = false;

  // ── Search state ─────────────────────────────────────────────
  final _searchController = TextEditingController();
  final List<Map<String, dynamic>> _suggestions = [];
  bool _searching = false;
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _picked = LatLng(widget.initial!.latitude, widget.initial!.longitude);
      _address = widget.initial!.address;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── GPS location ─────────────────────────────────────────────

  Future<void> _useMyLocation() async {
    setState(() => _gettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Location permission denied. Enable it in device settings.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final point = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _picked = point;
        _address = null;
        _showSuggestions = false;
      });
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _mapController.move(point, 15.0));
      await _reverseGeocode(point);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not get location: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  // ── Nominatim forward geocoding (search) ─────────────────────

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 2) {
      setState(() {
        _suggestions.clear();
        _showSuggestions = false;
      });
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _searching = true);
      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/search'
          '?q=${Uri.encodeComponent(query.trim())}'
          '&format=json&limit=5&addressdetails=1',
        );
        final resp = await http
            .get(uri, headers: {
              'Accept': 'application/json',
              'User-Agent': 'ecodz-app/1.0',
            })
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200 && mounted) {
          final results = jsonDecode(resp.body) as List;
          setState(() {
            _suggestions
              ..clear()
              ..addAll(results.cast<Map<String, dynamic>>());
            _showSuggestions = _suggestions.isNotEmpty;
          });
        }
      } catch (_) {
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  void _selectSuggestion(Map<String, dynamic> suggestion) {
    final lat = double.tryParse(suggestion['lat'] as String? ?? '') ?? 0;
    final lon = double.tryParse(suggestion['lon'] as String? ?? '') ?? 0;
    final displayName = suggestion['display_name'] as String? ?? '';
    final point = LatLng(lat, lon);
    final shortName =
        displayName.split(',').first.trim();
    setState(() {
      _picked = point;
      _address = displayName;
      _showSuggestions = false;
      _searchController.text = shortName;
    });
    // Move map to the selected location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(point, 14.0);
    });
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _geocoding = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${point.latitude}&lon=${point.longitude}&format=json',
      );
      final resp = await http
          .get(uri, headers: {
            'Accept': 'application/json',
            'User-Agent': 'ecodz-app/1.0',
          })
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final display = data['display_name'] as String?;
        if (mounted) setState(() => _address = display ?? point.coordString);
      } else {
        if (mounted) setState(() => _address = point.coordString);
      }
    } catch (_) {
      if (mounted) setState(() => _address = point.coordString);
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _onConfirm() {
    if (_picked == null) return;
    Navigator.of(context).pop(
      LocationResult(
        address: _address ?? _picked!.coordString,
        latitude: _picked!.latitude,
        longitude: _picked!.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        backgroundColor: _deepGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_gettingLocation)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.my_location_rounded, color: Colors.white),
              tooltip: 'Use my location',
              onPressed: _useMyLocation,
            ),
          if (_picked != null && !_geocoding)
            TextButton(
              onPressed: _onConfirm,
              child: const Text(
                'Confirm',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _picked ?? _defaultCenter,
              initialZoom: 12.0,
              onTap: (_, point) async {
                setState(() {
                  _picked = point;
                  _address = null;
                });
                await _reverseGeocode(point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.ecodz',
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 42,
                      height: 42,
                      child: const Icon(
                        Icons.location_pin,
                        color: _deepGreen,
                        size: 42,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Search bar + autocomplete suggestions ──────────────
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _searchPlaces,
                    decoration: InputDecoration(
                      prefixIcon:
                          const Icon(Icons.search, color: _deepGreen),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: _deepGreen,
                                ),
                              ),
                            )
                          : _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear,
                                      color: Colors.black45),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _suggestions.clear();
                                      _showSuggestions = false;
                                    });
                                  },
                                )
                              : null,
                      hintText: 'Search for a place…',
                      hintStyle:
                          const TextStyle(color: Colors.black38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 14),
                    ),
                  ),
                ),
                if (_showSuggestions)
                  Material(
                    elevation: 4,
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxHeight: 230),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final s = _suggestions[i];
                          final name =
                              s['display_name'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.place_outlined,
                              color: _deepGreen,
                              size: 20,
                            ),
                            title: Text(
                              name
                                  .split(',')
                                  .take(3)
                                  .join(','),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            onTap: () => _selectSuggestion(s),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Address card at the bottom ────────────────────────
          if (_picked != null)
            Positioned(
              bottom: 28,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: _geocoding
                    ? const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF1B5E20),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Getting address…',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: _deepGreen,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _address ?? _picked!.coordString,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton(
                              onPressed: _onConfirm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _deepGreen,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Use this location',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// Small extension so LatLng can produce a coord string.
extension _LatLngCoord on LatLng {
  String get coordString =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}
