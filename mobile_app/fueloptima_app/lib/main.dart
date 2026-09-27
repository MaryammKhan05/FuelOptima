import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

// Google-style colors
class GColors {
  static const blue = Color(0xFF4285F4);
  static const green = Color(0xFF34A853);
  static const red = Color(0xFFEA4335);
  static const yellow = Color(0xFFFBBC04);
  static const grey = Color(0xFF5F6368);
  static const lightGrey = Color(0xFFE8EAED);
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

  // -------- Point this at your FastAPI backend --------
  // When you deploy the backend later, change this to your real URL.
  static const String _backendBase = 'http://127.0.0.1:8000';

  @override
  void dispose() {
    _sourceController.dispose();
    _destinationController.dispose();
    super.dispose();
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
          onRoutesReady: (source, dest, sourceName, destName) {
            setState(() {
              _sourceLatLng = source;
              _destinationLatLng = dest;
              _sourceName = sourceName;
              _destinationName = destName;
            });
            _mapController.move(
              LatLng(
                (source.latitude + dest.latitude) / 2,
                (source.longitude + dest.longitude) / 2,
              ),
              10,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.fueloptima',
              ),
              if (_sourceLatLng != null || _destinationLatLng != null)
                MarkerLayer(
                  markers: [
                    if (_sourceLatLng != null)
                      Marker(
                        point: _sourceLatLng!,
                        width: 30,
                        height: 30,
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
                        ),
                      ),
                    if (_destinationLatLng != null)
                      Marker(
                        point: _destinationLatLng!,
                        width: 30,
                        height: 30,
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
                        ),
                      ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 3,
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
                            color:
                                _sourceName.isEmpty ? GColors.grey : Colors.black,
                            fontSize: 16,
                            fontWeight: _sourceName.isEmpty
                                ? FontWeight.w400
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openSearchSheet,
        backgroundColor: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: const Icon(Icons.directions, color: GColors.blue),
      ),
    );
  }
}

// ==================== SEARCH BOTTOM SHEET ====================
class _SearchSheet extends StatefulWidget {
  final String backendBase;
  final TextEditingController sourceController;
  final TextEditingController destinationController;
  final Function(LatLng source, LatLng dest, String sourceName, String destName)
      onRoutesReady;

  const _SearchSheet({
    required this.backendBase,
    required this.sourceController,
    required this.destinationController,
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

  LatLng? _sourceLatLng;
  LatLng? _destinationLatLng;

  @override
  void initState() {
    super.initState();
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
    // 1. Try coordinate parse first (e.g. "24.86, 67.00")
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

    // 2. Don't hit the API for very short inputs
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

    // 3. Call OUR backend (which proxies Google)
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

        // New Places API response shape:
        // { suggestions: [ { placePrediction: { placeId, text, structuredFormat } } ] }
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
        debugPrint('Autocomplete failed: ${response.statusCode} ${response.body}');
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
        // New Places API returns { location: { latitude, longitude } }
        final loc = data['location'];
        if (loc != null && loc['latitude'] != null && loc['longitude'] != null) {
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

  Future<void> _handleGetRoutes() async {
    // Ensure both endpoints are resolved
    if (_sourceLatLng == null) {
      final s = await _searchText(widget.sourceController.text);
      if (s == null) {
        _showError('Source not found');
        return;
      }
      _sourceLatLng = s;
    }

    if (_destinationLatLng == null) {
      final d = await _searchText(widget.destinationController.text);
      if (d == null) {
        _showError('Destination not found');
        return;
      }
      _destinationLatLng = d;
    }

    widget.onRoutesReady(
      _sourceLatLng!,
      _destinationLatLng!,
      widget.sourceController.text,
      widget.destinationController.text,
    );

    if (mounted) Navigator.pop(context);
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
        // New Places API: { places: [ { location: { latitude, longitude }, ... } ] }
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
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Plan your trip',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
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
                onPressed: _handleGetRoutes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GColors.blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Get Routes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ),
        ],
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
      separatorBuilder: (_, __) => const Divider(height: 1),
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