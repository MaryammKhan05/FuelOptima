import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

// Google-style colors
class GColors {
  static const blue = Color(0xFF4285F4);
  static const green = Color(0xFF34A853);
  static const red = Color(0xFFEA4335);
  static const yellow = Color(0xFFFBBC04);
  static const grey = Color(0xFF5F6368);
  static const lightGrey = Color(0xFFE8EAED);
}

class RouteInfo {
  final List<LatLng> points;
  final double distanceKm;
  final int durationSeconds;
  final String durationText;
  final String? description;
  final double fuelLiters;
  final double costPkr;

  RouteInfo({
    required this.points,
    required this.distanceKm,
    required this.durationSeconds,
    required this.durationText,
    this.description,
    required this.fuelLiters,
    required this.costPkr,
  });
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelOptima',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: GColors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  LatLng? _sourceLatLng;
  LatLng? _destinationLatLng;
  String _sourceName = '';
  String _destinationName = '';

  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  // Point this at your FastAPI backend
  static const String _backendBase = 'http://127.0.0.1:8000';

  List<RouteInfo> _routes = [];
  int _selectedRouteIndex = 0;
  String _selectedFuelType = 'petrol';
  final double _vehicleEfficiency = 12.0;

  @override
  void dispose() {
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _clearRoute() {
    setState(() {
      _routes = [];
      _selectedRouteIndex = 0;
      _sourceLatLng = null;
      _destinationLatLng = null;
      _sourceName = '';
      _destinationName = '';
      _sourceController.clear();
      _destinationController.clear();
    });
  }

  void _openSearchSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SearchSheet(
          backendBase: _backendBase,
          sourceController: _sourceController,
          destinationController: _destinationController,
          initialSource: _sourceLatLng,
          initialDest: _destinationLatLng,
          fuelType: _selectedFuelType,
          vehicleEfficiency: _vehicleEfficiency,
          onRoutesReady: (source, dest, sourceName, destName, routes) {
            setState(() {
              _sourceLatLng = source;
              _destinationLatLng = dest;
              _sourceName = sourceName;
              _destinationName = destName;
              _routes = routes;
              _selectedRouteIndex = 0;
            });

            if (routes.isNotEmpty && routes[0].points.isNotEmpty) {
              final points = routes[0].points;
              _mapController.fitCamera(
                CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(points),
                  padding: const EdgeInsets.only(
                    top: 100,
                    bottom: 240,
                    left: 50,
                    right: 50,
                  ),
                ),
              );
            } else {
              _mapController.move(
                LatLng(
                  (source.latitude + dest.latitude) / 2,
                  (source.longitude + dest.longitude) / 2,
                ),
                11,
              );
            }
          },
        );
      },
    );
  }

  void _recalculateCostForFuelType(String newFuelType) async {
    setState(() => _selectedFuelType = newFuelType);
    if (_routes.isEmpty) return;

    final updatedRoutes = <RouteInfo>[];
    for (final r in _routes) {
      try {
        final res = await http.post(
          Uri.parse('$_backendBase/fuel/trip-cost'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'distance_km': r.distanceKm,
            'vehicle_efficiency_km_per_l': _vehicleEfficiency,
            'fuel_type': newFuelType,
          }),
        );
        if (res.statusCode == 200) {
          final costData = json.decode(res.body);
          updatedRoutes.add(RouteInfo(
            points: r.points,
            distanceKm: r.distanceKm,
            durationSeconds: r.durationSeconds,
            durationText: r.durationText,
            description: r.description,
            fuelLiters: (costData['final_fuel_l'] as num).toDouble(),
            costPkr: (costData['total_cost_pkr'] as num).toDouble(),
          ));
        } else {
          updatedRoutes.add(r);
        }
      } catch (_) {
        updatedRoutes.add(r);
      }
    }
    if (mounted) {
      setState(() => _routes = updatedRoutes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeRoute =
        _routes.isNotEmpty ? _routes[_selectedRouteIndex] : null;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(30.3753, 69.3451),
              initialZoom: 5.5,
              maxZoom: 18,
              minZoom: 4,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.example.fueloptima',
              ),
              // Route Polylines
              if (_routes.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    // Inactive alternative routes (grey)
                    for (int i = 0; i < _routes.length; i++)
                      if (i != _selectedRouteIndex)
                        Polyline(
                          points: _routes[i].points,
                          strokeWidth: 4.5,
                          color: Colors.grey.withValues(alpha: 0.7),
                        ),
                    // Active selected route (blue)
                    Polyline(
                      points: _routes[_selectedRouteIndex].points,
                      strokeWidth: 6.0,
                      color: GColors.blue,
                    ),
                  ],
                ),
              // Markers for Source & Destination
              if (_sourceLatLng != null || _destinationLatLng != null)
                MarkerLayer(
                  markers: [
                    if (_sourceLatLng != null)
                      Marker(
                        point: _sourceLatLng!,
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: GColors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.trip_origin,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    if (_destinationLatLng != null)
                      Marker(
                        point: _destinationLatLng!,
                        width: 32,
                        height: 32,
                        child: Container(
                          decoration: BoxDecoration(
                            color: GColors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),

          // Top Search Bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(28),
              color: Colors.white,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _openSearchSheet,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: GColors.grey, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _sourceName.isEmpty
                              ? 'Where do you want to go?'
                              : '$_sourceName → $_destinationName',
                          style: TextStyle(
                            color: _sourceName.isEmpty
                                ? GColors.grey
                                : Colors.black87,
                            fontSize: 15,
                            fontWeight: _sourceName.isEmpty
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_routes.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: _clearRoute,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom Fuel Cost & Route Summary Card
          if (activeRoute != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 24,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(20),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with Route selector chips
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${activeRoute.distanceKm.toStringAsFixed(1)} km  •  ${activeRoute.durationText}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          // Fuel Type Toggle (Petrol / Diesel)
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'petrol',
                                label: Text('Petrol',
                                    style: TextStyle(fontSize: 12)),
                              ),
                              ButtonSegment(
                                value: 'diesel',
                                label: Text('Diesel',
                                    style: TextStyle(fontSize: 12)),
                              ),
                            ],
                            selected: {_selectedFuelType},
                            onSelectionChanged: (val) {
                              _recalculateCostForFuelType(val.first);
                            },
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Metrics Cards Row
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F3F4),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Est. Fuel',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: GColors.grey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${activeRoute.fuelLiters.toStringAsFixed(2)} L',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: GColors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6F4EA),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Est. Cost',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: GColors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rs. ${activeRoute.costPkr.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: GColors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Alternative Routes Switcher
                      if (_routes.length > 1) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(Icons.alt_route, size: 16, color: GColors.blue),
                            const SizedBox(width: 6),
                            Text(
                              'Suggested Routes (${_routes.length}):',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Column(
                          children: List.generate(_routes.length, (i) {
                            final r = _routes[i];
                            final isSel = i == _selectedRouteIndex;
                            final routeLabel = r.description != null && r.description!.isNotEmpty
                                ? 'via ${r.description}'
                                : (i == 0 ? 'Fastest Route' : 'Route ${i + 1}');

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  setState(() => _selectedRouteIndex = i);
                                  final pts = r.points;
                                  if (pts.isNotEmpty) {
                                    _mapController.fitCamera(
                                      CameraFit.bounds(
                                        bounds: LatLngBounds.fromPoints(pts),
                                        padding: const EdgeInsets.only(
                                          top: 100,
                                          bottom: 240,
                                          left: 50,
                                          right: 50,
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? const Color(0xFFE8F0FE)
                                        : const Color(0xFFF8F9FA),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSel
                                          ? GColors.blue
                                          : const Color(0xFFE0E0E0),
                                      width: isSel ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: isSel
                                              ? GColors.blue
                                              : Colors.grey.shade400,
                                          shape: BoxShape.circle,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              routeLabel,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSel
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: Colors.black87,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            Text(
                                              '${r.distanceKm.toStringAsFixed(1)} km  •  ${r.durationText}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        'Rs. ${r.costPkr.toStringAsFixed(0)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isSel
                                              ? GColors.green
                                              : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _routes.isEmpty
          ? FloatingActionButton(
              onPressed: _openSearchSheet,
              backgroundColor: Colors.white,
              elevation: 3,
              shape: const CircleBorder(),
              child: const Icon(Icons.directions, color: GColors.blue),
            )
          : null,
    );
  }
}

// ==================== SEARCH BOTTOM SHEET ====================
class _SearchSheet extends StatefulWidget {
  final String backendBase;
  final TextEditingController sourceController;
  final TextEditingController destinationController;
  final LatLng? initialSource;
  final LatLng? initialDest;
  final String fuelType;
  final double vehicleEfficiency;
  final Function(
    LatLng source,
    LatLng dest,
    String sourceName,
    String destName,
    List<RouteInfo> routes,
  ) onRoutesReady;

  const _SearchSheet({
    required this.backendBase,
    required this.sourceController,
    required this.destinationController,
    this.initialSource,
    this.initialDest,
    required this.fuelType,
    required this.vehicleEfficiency,
    required this.onRoutesReady,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  List<Map<String, dynamic>> _sourceSuggestions = [];
  List<Map<String, dynamic>> _destinationSuggestions = [];
  bool _loadingSource = false;
  bool _loadingDest = false;
  bool _isComputingRoute = false;

  LatLng? _sourceLatLng;
  LatLng? _destinationLatLng;

  @override
  void initState() {
    super.initState();
    _sourceLatLng = widget.initialSource;
    _destinationLatLng = widget.initialDest;
    widget.sourceController.addListener(_onSourceChanged);
    widget.destinationController.addListener(_onDestChanged);
  }

  @override
  void dispose() {
    widget.sourceController.removeListener(_onSourceChanged);
    widget.destinationController.removeListener(_onDestChanged);
    super.dispose();
  }

  void _onSourceChanged() {
    _fetchSuggestions(widget.sourceController.text, isSource: true);
  }

  void _onDestChanged() {
    _fetchSuggestions(widget.destinationController.text, isSource: false);
  }

  Future<void> _fetchSuggestions(String query, {required bool isSource}) async {
    final coords = _tryParseCoordinates(query);
    if (coords != null) {
      if (isSource) {
        _sourceLatLng = coords;
        _sourceSuggestions = [];
      } else {
        _destinationLatLng = coords;
        _destinationSuggestions = [];
      }
      if (mounted) setState(() {});
      return;
    }

    if (query.trim().length < 3) {
      if (isSource) {
        _sourceSuggestions = [];
      } else {
        _destinationSuggestions = [];
      }
      if (mounted) setState(() {});
      return;
    }

    if (isSource) {
      setState(() => _loadingSource = true);
    } else {
      setState(() => _loadingDest = true);
    }

    final url = Uri.parse('${widget.backendBase}/places/autocomplete');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'input': query}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions =
            (data['suggestions'] as List?) ?? const <dynamic>[];

        final results = predictions
            .map((p) {
              final pred = p['placePrediction'] as Map<String, dynamic>?;
              if (pred == null) return null;
              final text = pred['text']?['text'] as String? ?? '';
              final placeId = pred['placeId'] as String? ?? '';
              if (placeId.isEmpty || text.isEmpty) return null;
              return <String, dynamic>{
                'description': text,
                'place_id': placeId,
              };
            })
            .whereType<Map<String, dynamic>>()
            .toList();

        if (isSource) {
          setState(() {
            _sourceSuggestions = results;
            _loadingSource = false;
          });
        } else {
          setState(() {
            _destinationSuggestions = results;
            _loadingDest = false;
          });
        }
      } else {
        debugPrint(
            'Autocomplete failed: ${response.statusCode} ${response.body}');
        if (isSource) {
          setState(() => _loadingSource = false);
        } else {
          setState(() => _loadingDest = false);
        }
      }
    } catch (e) {
      debugPrint('Autocomplete error: $e');
      if (isSource) {
        setState(() => _loadingSource = false);
      } else {
        setState(() => _loadingDest = false);
      }
    }
  }

  LatLng? _tryParseCoordinates(String input) {
    final parts = input.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  Future<LatLng?> _getPlaceDetails(String placeId) async {
    final url = Uri.parse('${widget.backendBase}/places/details');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'place_id': placeId}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final loc = data['location'];
        if (loc != null &&
            loc['latitude'] != null &&
            loc['longitude'] != null) {
          return LatLng(
            (loc['latitude'] as num).toDouble(),
            (loc['longitude'] as num).toDouble(),
          );
        }
      } else {
        debugPrint('Details failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('Place details error: $e');
    }
    return null;
  }

  void _onSuggestionTapped(Map<String, dynamic> suggestion,
      {required bool isSource}) async {
    final latLng = await _getPlaceDetails(suggestion['place_id']);
    if (latLng == null) return;

    if (isSource) {
      widget.sourceController.text = suggestion['description'];
      _sourceLatLng = latLng;
      setState(() => _sourceSuggestions = []);
    } else {
      widget.destinationController.text = suggestion['description'];
      _destinationLatLng = latLng;
      setState(() => _destinationSuggestions = []);
    }
  }

  int _parseDurationSeconds(dynamic d) {
    if (d is int) return d;
    if (d is String) {
      final s = d.replaceAll('s', '').trim();
      return int.tryParse(s) ?? 0;
    }
    return 0;
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes mins';
    final hours = minutes ~/ 60;
    final remMins = minutes % 60;
    return '${hours}h ${remMins}m';
  }

  Future<void> _handleGetRoutes() async {
    if (_isComputingRoute) return;

    // 1. Resolve source coordinates
    if (_sourceLatLng == null) {
      final s = await _searchText(widget.sourceController.text);
      if (s == null) {
        _showError('Starting point not found. Try selecting from suggestions.');
        return;
      }
      _sourceLatLng = s;
    }

    // 2. Resolve destination coordinates
    if (_destinationLatLng == null) {
      final d = await _searchText(widget.destinationController.text);
      if (d == null) {
        _showError('Destination not found. Try selecting from suggestions.');
        return;
      }
      _destinationLatLng = d;
    }

    setState(() => _isComputingRoute = true);

    try {
      // 3. Request routes from backend
      final computeUrl = Uri.parse('${widget.backendBase}/routes/compute');
      final routeRes = await http.post(
        computeUrl,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'source': {
            'lat': _sourceLatLng!.latitude,
            'lng': _sourceLatLng!.longitude,
          },
          'destination': {
            'lat': _destinationLatLng!.latitude,
            'lng': _destinationLatLng!.longitude,
          },
        }),
      );

      if (routeRes.statusCode != 200) {
        _showError('Routes error: ${routeRes.statusCode} - ${routeRes.body}');
        setState(() => _isComputingRoute = false);
        return;
      }

      final routeData = json.decode(routeRes.body);
      final rawRoutes = (routeData['routes'] as List?) ?? [];

      if (rawRoutes.isEmpty) {
        _showError('No driving routes found between these locations.');
        setState(() => _isComputingRoute = false);
        return;
      }

      // 4. Decode polylines and calculate fuel cost for each route
      final List<RouteInfo> computedRoutes = [];

      for (final r in rawRoutes) {
        final encodedPolyline =
            r['polyline']?['encodedPolyline'] as String? ?? '';
        if (encodedPolyline.isEmpty) continue;

        final decoded = PolylinePoints.decodePolyline(encodedPolyline);
        final points =
            decoded.map((p) => LatLng(p.latitude, p.longitude)).toList();

        final distanceMeters = (r['distanceMeters'] as num?)?.toDouble() ?? 0.0;
        final distanceKm = distanceMeters / 1000.0;

        final durationSec = _parseDurationSeconds(r['duration']);
        final durationText = _formatDuration(durationSec);

        // Fetch fuel cost estimation
        double fuelLiters = 0.0;
        double costPkr = 0.0;

        try {
          final costRes = await http.post(
            Uri.parse('${widget.backendBase}/fuel/trip-cost'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'distance_km': distanceKm,
              'vehicle_efficiency_km_per_l': widget.vehicleEfficiency,
              'fuel_type': widget.fuelType,
            }),
          );

          if (costRes.statusCode == 200) {
            final costData = json.decode(costRes.body);
            fuelLiters = (costData['final_fuel_l'] as num).toDouble();
            costPkr = (costData['total_cost_pkr'] as num).toDouble();
          }
        } catch (e) {
          debugPrint('Cost calculation error: $e');
        }

        computedRoutes.add(RouteInfo(
          points: points,
          distanceKm: distanceKm,
          durationSeconds: durationSec,
          durationText: durationText,
          description: r['description'] as String?,
          fuelLiters: fuelLiters,
          costPkr: costPkr,
        ));
      }

      if (computedRoutes.isEmpty) {
        _showError('Could not decode route geometry.');
        setState(() => _isComputingRoute = false);
        return;
      }

      widget.onRoutesReady(
        _sourceLatLng!,
        _destinationLatLng!,
        widget.sourceController.text.isNotEmpty
            ? widget.sourceController.text
            : 'Start',
        widget.destinationController.text.isNotEmpty
            ? widget.destinationController.text
            : 'Destination',
        computedRoutes,
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Failed to fetch routes: $e');
    } finally {
      if (mounted) setState(() => _isComputingRoute = false);
    }
  }

  Future<LatLng?> _searchText(String query) async {
    if (query.trim().isEmpty) return null;
    final url = Uri.parse('${widget.backendBase}/places/textsearch');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text_query': query}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final places = data['places'] as List?;
        if (places != null && places.isNotEmpty) {
          final loc = places[0]['location'];
          if (loc != null) {
            return LatLng(
              (loc['latitude'] as num).toDouble(),
              (loc['longitude'] as num).toDouble(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Text search error: $e');
    }
    return null;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Wrapping in Material fixes the ListTile assertion error on Chrome/Web
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Text(
                    'Plan your trip',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: GColors.grey),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Input Fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 14),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: GColors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Container(
                        width: 2,
                        height: 40,
                        color: GColors.lightGrey,
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: GColors.red,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F3F4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: widget.sourceController,
                            decoration: const InputDecoration(
                              hintText: 'Choose starting point',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F3F4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: TextField(
                            controller: widget.destinationController,
                            decoration: const InputDecoration(
                              hintText: 'Choose destination',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildSuggestionsArea(),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isComputingRoute ? null : _handleGetRoutes,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GColors.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: _isComputingRoute
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Get Routes',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsArea() {
    if (_destinationSuggestions.isNotEmpty || _loadingDest) {
      return _buildSuggestionList(_destinationSuggestions, isSource: false);
    }
    if (_sourceSuggestions.isNotEmpty || _loadingSource) {
      return _buildSuggestionList(_sourceSuggestions, isSource: true);
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'Enter a place name or coordinates (lat, lng)',
          style: TextStyle(color: GColors.grey),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSuggestionList(List<Map<String, dynamic>> suggestions,
      {required bool isSource}) {
    if (suggestions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: suggestions.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = suggestions[index];
        return ListTile(
          leading: const Icon(Icons.location_on_outlined, color: GColors.grey),
          title: Text(
            s['description'],
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
          onTap: () => _onSuggestionTapped(s, isSource: isSource),
        );
      },
    );
  }
}