import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/features/auth/screens/login_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model for a selected shop destination
// ─────────────────────────────────────────────────────────────────────────────
class _ShopDestination {
  final String id;
  final String name;
  final String city;
  final String imageUrl;
  final LatLng location;

  const _ShopDestination({
    required this.id,
    required this.name,
    required this.city,
    required this.imageUrl,
    required this.location,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// LandingScreen
// ─────────────────────────────────────────────────────────────────────────────
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<Position>? _positionSubscription;

  Position? _userPosition;
  String _searchQuery = '';
  bool _locationLoading = false;
  bool _showMap = false;

  // Navigation state
  _ShopDestination? _selectedShop;
  List<LatLng> _routePoints = [];
  double? _routeDistanceKm;
  int? _routeMinutes;
  bool _routeLoading = false;

  static const _kigaliLat = -1.9441;
  static const _kigaliLng = 30.0619;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _requestLocation();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Location ────────────────────────────────────────────────────────────────

  void _startLocationUpdates() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() => _userPosition = pos);
      // Only auto-pan if we have no active route (don't interrupt navigation)
      if (_showMap && _selectedShop == null) {
        _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
      }
      // If navigating, refresh route distance (straight-line update)
      if (_selectedShop != null) {
        final dist = Geolocator.distanceBetween(
          pos.latitude, pos.longitude,
          _selectedShop!.location.latitude,
          _selectedShop!.location.longitude,
        );
        setState(() => _routeDistanceKm = dist / 1000);
      }
    });
  }

  Future<void> _requestLocation() async {
    setState(() => _locationLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) setState(() => _userPosition = pos);
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  // ── Routing (OSRM — free, no API key) ──────────────────────────────────────

  Future<void> _fetchRoute(_ShopDestination shop) async {
    if (_userPosition == null) {
      _showSnack('Enable location to get directions');
      return;
    }

    setState(() {
      _selectedShop = shop;
      _routeLoading = true;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeMinutes = null;
    });

    // Zoom map to show both points
    _showMap = true;
    final userLatLng = LatLng(_userPosition!.latitude, _userPosition!.longitude);
    _fitMapToBounds(userLatLng, shop.location);

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${_userPosition!.longitude},${_userPosition!.latitude};'
        '${shop.location.longitude},${shop.location.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final routes = json['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final distMeters = (route['distance'] as num).toDouble();
          final durationSecs = (route['duration'] as num).toDouble();
          final coords = route['geometry']['coordinates'] as List;

          final points = coords
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();

          if (mounted) {
            setState(() {
              _routePoints = points;
              _routeDistanceKm = distMeters / 1000;
              _routeMinutes = (durationSecs / 60).ceil();
              _routeLoading = false;
            });
          }
          return;
        }
      }
    } catch (_) {
      // Fall through to straight-line fallback
    }

    // Fallback: straight-line distance if OSRM fails
    if (mounted) {
      final dist = Geolocator.distanceBetween(
        _userPosition!.latitude, _userPosition!.longitude,
        shop.location.latitude, shop.location.longitude,
      );
      setState(() {
        _routePoints = [userLatLng, shop.location];
        _routeDistanceKm = dist / 1000;
        _routeMinutes = (dist / 1000 / 5 * 60).ceil(); // ~5 km/h walking
        _routeLoading = false;
      });
    }
  }

  void _fitMapToBounds(LatLng a, LatLng b) {
    final minLat = a.latitude < b.latitude ? a.latitude : b.latitude;
    final maxLat = a.latitude > b.latitude ? a.latitude : b.latitude;
    final minLng = a.longitude < b.longitude ? a.longitude : b.longitude;
    final maxLng = a.longitude > b.longitude ? a.longitude : b.longitude;

    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;

    // Rough zoom estimation
    final latDiff = (maxLat - minLat).abs();
    final lngDiff = (maxLng - minLng).abs();
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    double zoom = 14;
    if (maxDiff > 0.1) zoom = 12;
    if (maxDiff > 0.5) zoom = 10;
    if (maxDiff > 1.0) zoom = 9;

    _mapController.move(LatLng(centerLat, centerLng), zoom);
  }

  void _clearRoute() {
    setState(() {
      _selectedShop = null;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeMinutes = null;
      _routeLoading = false;
    });
  }

  Future<void> _openInMaps(_ShopDestination shop) async {
    final lat = shop.location.latitude;
    final lng = shop.location.longitude;
    final name = Uri.encodeComponent(shop.name);

    // Try Google Maps first, fall back to OSM
    final googleUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&destination_place_id=$name&travelmode=driving');
    final osmUri = Uri.parse('https://www.openstreetmap.org/directions?from=&to=$lat,$lng');

    if (await canLaunchUrl(googleUri)) {
      await launchUrl(googleUri, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(osmUri)) {
      await launchUrl(osmUri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('Could not open maps app');
    }
  }

  // ── Shop tap handler ────────────────────────────────────────────────────────

  void _onShopMarkerTapped(QueryDocumentSnapshot doc, bool isDark) {
    final data = doc.data() as Map<String, dynamic>;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      _showShopPreview(context, doc, isDark);
      return;
    }

    final destination = _ShopDestination(
      id: doc.id,
      name: data['name'] ?? 'Café',
      city: data['city'] ?? '',
      imageUrl: data['shopImageUrl'] ?? '',
      location: LatLng(lat, lng),
    );

    _fetchRoute(destination);
    _showNavigationSheet(destination, isDark);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (_, __) => [_buildSliverAppBar(isDark, theme)],
        body: Column(
          children: [
            _buildSearchBar(isDark, theme),
            _buildViewToggle(isDark, theme),
            Expanded(
              child: _showMap
                  ? _buildMapView(isDark, context)
                  : _buildShopList(isDark, theme),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ─────────────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar(bool isDark, ThemeData theme) {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      stretch: true,
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primary,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [AppTheme.primary, const Color(0xFF3E2010)]
                      : [AppTheme.primary, const Color(0xFF4A2E1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Image.asset(
              'assets/images/coffee_bg.jpeg',
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.45),
              colorBlendMode: BlendMode.darken,
              errorBuilder: (_, __, ___) => const SizedBox(),
            ),
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/images/logo-white.png',
                        height: 32,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.local_cafe_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'KoffiLoop',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Georgia',
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Great coffee, nearby.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Georgia',
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Explore cafés and order ahead — no account needed',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text(
            'Sign In',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ],
    );
  }

  // ── Search Bar ──────────────────────────────────────────────────────────────

  Widget _buildSearchBar(bool isDark, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
          style: TextStyle(
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Search cafés...',
            hintStyle: TextStyle(
              color: isDark ? AppTheme.darkTextSecondary : Colors.grey.shade400,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? AppTheme.secondary : AppTheme.primary,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    color: Colors.grey,
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : _locationLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.my_location_rounded,
                          color: _userPosition != null
                              ? AppTheme.primary
                              : Colors.grey,
                        ),
                        onPressed: _requestLocation,
                        tooltip: 'Use my location',
                      ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          ),
        ),
      ),
    );
  }

  // ── View Toggle ─────────────────────────────────────────────────────────────

  Widget _buildViewToggle(bool isDark, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _ToggleButton(
              label: 'List View',
              icon: Icons.view_list_rounded,
              isSelected: !_showMap,
              isDark: isDark,
              onTap: () => setState(() => _showMap = false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ToggleButton(
              label: 'Map View',
              icon: Icons.map_rounded,
              isSelected: _showMap,
              isDark: isDark,
              onTap: () => setState(() => _showMap = true),
            ),
          ),
        ],
      ),
    );
  }

  // ── Map View ────────────────────────────────────────────────────────────────

  Widget _buildMapView(bool isDark, BuildContext context) {
    final center = _userPosition != null
        ? LatLng(_userPosition!.latitude, _userPosition!.longitude)
        : const LatLng(_kigaliLat, _kigaliLng);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .where('isOpen', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Stack(
          children: [
            // ── Flutter Map ────────────────────────────────────────────
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (_, __) {
                  // Tapping empty map clears route
                  if (_selectedShop != null) _clearRoute();
                },
              ),
              children: [
                // Tile layer
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.koffiloop',
                  retinaMode: RetinaMode.isHighDensity(context),
                  maxNativeZoom: 19,
                  tileProvider: NetworkTileProvider(),
                ),

                // Route polyline
                if (_routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePoints,
                        strokeWidth: 5,
                        color: AppTheme.primary,
                        borderStrokeWidth: 2,
                        borderColor: Colors.white,
                      ),
                    ],
                  ),

                // Markers
                MarkerLayer(
                  markers: [
                    // User position marker
                    if (_userPosition != null)
                      Marker(
                        point: LatLng(
                            _userPosition!.latitude, _userPosition!.longitude),
                        width: 48,
                        height: 48,
                        child: _UserMarker(),
                      ),

                    // Shop markers — only from Firestore registered shops
                    ...docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final lat = (data['latitude'] as num?)?.toDouble();
                      final lng = (data['longitude'] as num?)?.toDouble();
                      if (lat == null || lng == null) return null;

                      final isSelected = _selectedShop?.id == doc.id;

                      return Marker(
                        point: LatLng(lat, lng),
                        width: isSelected ? 56 : 44,
                        height: isSelected ? 56 : 44,
                        child: GestureDetector(
                          onTap: () => _onShopMarkerTapped(doc, isDark),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? AppTheme.warning
                                  : AppTheme.primary,
                              border: Border.all(
                                color: Colors.white,
                                width: isSelected ? 3 : 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isSelected
                                          ? AppTheme.warning
                                          : AppTheme.primary)
                                      .withValues(alpha: 0.4),
                                  blurRadius: isSelected ? 12 : 8,
                                  spreadRadius: isSelected ? 2 : 0,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.local_cafe_rounded,
                              color: Colors.white,
                              size: isSelected ? 26 : 20,
                            ),
                          ),
                        ),
                      );
                    }).whereType<Marker>(),
                  ],
                ),
              ],
            ),

            // ── Route loading indicator ────────────────────────────────
            if (_routeLoading)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                        SizedBox(width: 8),
                        Text('Calculating route…',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Location loading indicator ─────────────────────────────
            if (_locationLoading && !_routeLoading)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                        SizedBox(width: 8),
                        Text('Finding location…',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Active route mini-panel (bottom of map) ────────────────
            if (_selectedShop != null && !_routeLoading)
              Positioned(
                bottom: 80,
                left: 16,
                right: 16,
                child: _RouteInfoBanner(
                  shop: _selectedShop!,
                  distanceKm: _routeDistanceKm,
                  minutes: _routeMinutes,
                  isDark: isDark,
                  onNavigate: () => _openInMaps(_selectedShop!),
                  onDismiss: _clearRoute,
                  onDetails: () => _showNavigationSheet(_selectedShop!, isDark),
                ),
              ),

            // ── FABs ───────────────────────────────────────────────────
            Positioned(
              bottom: _selectedShop != null ? 148 : 20,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedShop != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: FloatingActionButton.small(
                        heroTag: 'clearroute',
                        backgroundColor: Colors.white,
                        onPressed: _clearRoute,
                        tooltip: 'Clear route',
                        child: const Icon(Icons.close_rounded,
                            color: Colors.red),
                      ),
                    ),
                  FloatingActionButton.small(
                    heroTag: 'recenter',
                    backgroundColor: Colors.white,
                    onPressed: () {
                      if (_userPosition != null) {
                        _mapController.move(
                          LatLng(_userPosition!.latitude,
                              _userPosition!.longitude),
                          15,
                        );
                      }
                    },
                    tooltip: 'My location',
                    child: const Icon(Icons.my_location_rounded,
                        color: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Navigation Bottom Sheet ─────────────────────────────────────────────────

  void _showNavigationSheet(_ShopDestination shop, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NavigationSheet(
        shop: shop,
        userPosition: _userPosition,
        distanceKm: _routeDistanceKm,
        minutes: _routeMinutes,
        isDark: isDark,
        onNavigateExternal: () => _openInMaps(shop),
        onShowOnMap: () {
          Navigator.pop(context);
          setState(() => _showMap = true);
          _fitMapToBounds(
            LatLng(_userPosition!.latitude, _userPosition!.longitude),
            shop.location,
          );
        },
        onViewShop: () {
          Navigator.pop(context);
          // Find the doc from the stream — re-query for preview
          FirebaseFirestore.instance
              .collection('shops')
              .doc(shop.id)
              .get()
              .then((doc) {
            if (doc.exists && mounted) {
              _showShopPreview(context, doc, isDark);
            }
          });
        },
      ),
    );
  }

  // ── Shop Preview (list tap) ─────────────────────────────────────────────────

  void _showShopPreview(
      BuildContext context, DocumentSnapshot shop, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShopBottomSheet(shop: shop, isDark: isDark),
    );
  }

  // ── Shop List ───────────────────────────────────────────────────────────────

  Widget _buildShopList(bool isDark, ThemeData theme) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .where('isOpen', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmer(isDark);
        }
        if (snapshot.hasError) return _buildErrorState(isDark);

        var docs = snapshot.data?.docs ?? [];

        if (_searchQuery.isNotEmpty) {
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final name = (data['name'] ?? '').toString().toLowerCase();
            final city = (data['city'] ?? '').toString().toLowerCase();
            return name.contains(_searchQuery) ||
                city.contains(_searchQuery);
          }).toList();
        }

        if (docs.isEmpty) return _buildEmptyState(isDark);

        // Sort by distance if available
        if (_userPosition != null) {
          docs.sort((a, b) {
            final ad = a.data() as Map<String, dynamic>;
            final bd = b.data() as Map<String, dynamic>;
            final aLat = (ad['latitude'] as num?)?.toDouble();
            final aLng = (ad['longitude'] as num?)?.toDouble();
            final bLat = (bd['latitude'] as num?)?.toDouble();
            final bLng = (bd['longitude'] as num?)?.toDouble();
            if (aLat == null || aLng == null) return 1;
            if (bLat == null || bLng == null) return -1;
            final aDist = Geolocator.distanceBetween(
                _userPosition!.latitude, _userPosition!.longitude, aLat, aLng);
            final bDist = Geolocator.distanceBetween(
                _userPosition!.latitude, _userPosition!.longitude, bLat, bLng);
            return aDist.compareTo(bDist);
          });
        }

        return RefreshIndicator(
          onRefresh: _requestLocation,
          color: AppTheme.primary,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            itemCount: docs.length,
            itemBuilder: (context, index) => _ShopCard(
              shop: docs[index],
              isDark: isDark,
              userPosition: _userPosition,
              onTap: () => _showShopPreview(context, docs[index], isDark),
              onNavigate: () {
                final data = docs[index].data() as Map<String, dynamic>;
                final lat = (data['latitude'] as num?)?.toDouble();
                final lng = (data['longitude'] as num?)?.toDouble();
                if (lat == null || lng == null) {
                  _showSnack('This café has no location set yet');
                  return;
                }
                final dest = _ShopDestination(
                  id: docs[index].id,
                  name: data['name'] ?? 'Café',
                  city: data['city'] ?? '',
                  imageUrl: data['shopImageUrl'] ?? '',
                  location: LatLng(lat, lng),
                );
                _fetchRoute(dest);
                _showNavigationSheet(dest, isDark);
              },
            ),
          ),
        );
      },
    );
  }

  // ── Shimmer / Error / Empty ─────────────────────────────────────────────────

  Widget _buildShimmer(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: 4,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: isDark ? AppTheme.darkCard : Colors.grey.shade200,
        highlightColor:
            isDark ? AppTheme.darkSurface : Colors.grey.shade100,
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 130,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 56,
              color:
                  isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('Could not load cafés',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Text('Check your connection and try again',
              style: TextStyle(
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_cafe_outlined,
              size: 72,
              color:
                  isDark ? Colors.grey.shade600 : Colors.grey.shade300),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty
                ? 'No cafés match "$_searchQuery"'
                : 'No cafés listed yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text('Check back soon — more are coming!',
              style: TextStyle(
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User location marker
// ─────────────────────────────────────────────────────────────────────────────
class _UserMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.withValues(alpha: 0.15),
          ),
        ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blue.shade600,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Route info banner — shown at bottom of map when route is active
// ─────────────────────────────────────────────────────────────────────────────
class _RouteInfoBanner extends StatelessWidget {
  final _ShopDestination shop;
  final double? distanceKm;
  final int? minutes;
  final bool isDark;
  final VoidCallback onNavigate;
  final VoidCallback onDismiss;
  final VoidCallback onDetails;

  const _RouteInfoBanner({
    required this.shop,
    required this.distanceKm,
    required this.minutes,
    required this.isDark,
    required this.onNavigate,
    required this.onDismiss,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Shop icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_cafe_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: GestureDetector(
              onTap: onDetails,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shop.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Georgia',
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (distanceKm != null) ...[
                        const Icon(Icons.straighten_rounded,
                            size: 12, color: AppTheme.primary),
                        const SizedBox(width: 3),
                        Text(
                          distanceKm! < 1
                              ? '${(distanceKm! * 1000).toInt()} m'
                              : '${distanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary),
                        ),
                      ],
                      if (minutes != null) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.access_time_rounded,
                            size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 3),
                        Text(
                          '~$minutes min',
                          style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Navigate button
          GestureDetector(
            onTap: onNavigate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryDark]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.navigation_rounded,
                      color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('Go',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation bottom sheet — full details when tapping a shop
// ─────────────────────────────────────────────────────────────────────────────
class _NavigationSheet extends StatelessWidget {
  final _ShopDestination shop;
  final Position? userPosition;
  final double? distanceKm;
  final int? minutes;
  final bool isDark;
  final VoidCallback onNavigateExternal;
  final VoidCallback onShowOnMap;
  final VoidCallback onViewShop;

  const _NavigationSheet({
    required this.shop,
    required this.userPosition,
    required this.distanceKm,
    required this.minutes,
    required this.isDark,
    required this.onNavigateExternal,
    required this.onShowOnMap,
    required this.onViewShop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkDivider : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Shop header
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.primary.withValues(alpha: 0.1),
                ),
                child: shop.imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: CachedNetworkImage(
                          imageUrl: shop.imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(
                              Icons.local_cafe_rounded,
                              color: AppTheme.primary),
                        ),
                      )
                    : const Icon(Icons.local_cafe_rounded,
                        color: AppTheme.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Georgia',
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 13,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : Colors.grey.shade500),
                        const SizedBox(width: 3),
                        Text(
                          shop.city,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(
                      color: AppTheme.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Distance / Time row
          if (distanceKm != null || minutes != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkElevated
                    : AppTheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.straighten_rounded,
                      label: 'Distance',
                      value: distanceKm == null
                          ? '—'
                          : distanceKm! < 1
                              ? '${(distanceKm! * 1000).toInt()} m'
                              : '${distanceKm!.toStringAsFixed(2)} km',
                      isDark: isDark,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: isDark
                        ? AppTheme.darkDivider
                        : Colors.grey.shade200,
                  ),
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.access_time_rounded,
                      label: 'Est. time',
                      value:
                          minutes == null ? '—' : '~$minutes min',
                      isDark: isDark,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: isDark
                        ? AppTheme.darkDivider
                        : Colors.grey.shade200,
                  ),
                  Expanded(
                    child: _InfoTile(
                      icon: Icons.directions_car_rounded,
                      label: 'By car',
                      value: userPosition == null ? '—' : 'via road',
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          // Action buttons
          Row(
            children: [
              // View on map
              Expanded(
                child: _ActionButton(
                  label: 'View on Map',
                  icon: Icons.map_rounded,
                  isPrimary: false,
                  isDark: isDark,
                  onTap: onShowOnMap,
                ),
              ),
              const SizedBox(width: 10),
              // View shop
              Expanded(
                child: _ActionButton(
                  label: 'View Menu',
                  icon: Icons.menu_book_rounded,
                  isPrimary: false,
                  isDark: isDark,
                  onTap: onViewShop,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Main navigate button — opens Google Maps / OSM
          _ActionButton(
            label: userPosition == null
                ? 'Enable location to navigate'
                : 'Open in Maps App',
            icon: Icons.navigation_rounded,
            isPrimary: true,
            isDark: isDark,
            onTap: userPosition == null ? null : onNavigateExternal,
          ),

          if (userPosition == null) ...[
            const SizedBox(height: 8),
            Text(
              'Location permission needed for navigation',
              style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small info tile used inside navigation sheet
// ─────────────────────────────────────────────────────────────────────────────
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primary, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color:
                isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final bool isDark;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isPrimary && onTap != null
              ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark])
              : null,
          color: isPrimary && onTap != null
              ? null
              : (isDark ? AppTheme.darkElevated : AppTheme.surfaceVariant),
          borderRadius: BorderRadius.circular(14),
          boxShadow: isPrimary && onTap != null ? AppTheme.buttonShadow : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isPrimary && onTap != null
                  ? Colors.white
                  : (isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isPrimary && onTap != null
                    ? Colors.white
                    : (isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle button
// ─────────────────────────────────────────────────────────────────────────────
class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : (isDark ? AppTheme.darkDivider : Colors.grey.shade200),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : (isDark
                      ? AppTheme.darkTextSecondary
                      : Colors.grey.shade500),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? AppTheme.darkTextSecondary
                        : Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shop card in list view — now has a Navigate button
// ─────────────────────────────────────────────────────────────────────────────
class _ShopCard extends StatelessWidget {
  final QueryDocumentSnapshot shop;
  final bool isDark;
  final Position? userPosition;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

  const _ShopCard({
    required this.shop,
    required this.isDark,
    required this.userPosition,
    required this.onTap,
    required this.onNavigate,
  });

  String? _distanceLabel() {
    if (userPosition == null) return null;
    final data = shop.data() as Map<String, dynamic>;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final d = Geolocator.distanceBetween(
        userPosition!.latitude, userPosition!.longitude, lat, lng);
    return d < 1000
        ? '${d.toInt()} m away'
        : '${(d / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final data = shop.data() as Map<String, dynamic>;
    final imageUrl = data['shopImageUrl'] ?? '';
    final name = data['name'] ?? 'Unknown Café';
    final city = data['city'] ?? '';
    final distance = _distanceLabel();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Shimmer.fromColors(
                            baseColor: isDark
                                ? AppTheme.darkSurface
                                : Colors.grey.shade200,
                            highlightColor: isDark
                                ? AppTheme.darkCard
                                : Colors.grey.shade100,
                            child:
                                Container(height: 140, color: Colors.white),
                          ),
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Open',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + distance
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Georgia',
                            color: isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (distance != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            distance,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // City
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text(city,
                          style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Product chips
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('shops')
                        .doc(shop.id)
                        .collection('products')
                        .where('inStock', isEqualTo: true)
                        .limit(3)
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const SizedBox();
                      final products = snap.data!.docs
                          .map((d) => d.data() as Map<String, dynamic>)
                          .toList();
                      if (products.isEmpty) return const SizedBox();
                      return Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: products.map((p) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.secondary.withValues(
                                  alpha: isDark ? 0.2 : 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${p['name']}  \$${((p['price'] ?? 0) as num).toStringAsFixed(2)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.textPrimary),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Action buttons row
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onTap,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.menu_book_rounded,
                                    size: 15, color: Colors.white),
                                SizedBox(width: 6),
                                Text('View Menu',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: onNavigate,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkElevated
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppTheme.primary
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.navigation_rounded,
                                    size: 15, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text('Navigate',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isDark
                                            ? AppTheme.darkTextPrimary
                                            : AppTheme.primary)),
                              ],
                            ),
                          ),
                        ),
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

  Widget _placeholder() {
    return Container(
      height: 140,
      width: double.infinity,
      color: AppTheme.secondary.withValues(alpha: 0.12),
      child: const Icon(Icons.local_cafe_rounded,
          size: 48, color: AppTheme.primary),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shop bottom sheet — read-only preview for unauthenticated users
// ─────────────────────────────────────────────────────────────────────────────
class _ShopBottomSheet extends StatelessWidget {
  final DocumentSnapshot shop;
  final bool isDark;

  const _ShopBottomSheet({required this.shop, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final data = shop.data() as Map<String, dynamic>;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBackground : AppTheme.background,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: data['shopImageUrl'] != null &&
                            (data['shopImageUrl'] as String).isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedNetworkImage(
                              imageUrl: data['shopImageUrl'],
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.storefront_rounded,
                                  color: Colors.white),
                            ),
                          )
                        : const Icon(Icons.storefront_rounded,
                            color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name'] ?? 'Café',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Georgia',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded,
                                color: Colors.white70, size: 13),
                            const SizedBox(width: 3),
                            Text(data['city'] ?? '',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Product list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('shops')
                    .doc(shop.id)
                    .collection('products')
                    .where('inStock', isEqualTo: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppTheme.primary));
                  }
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return Center(
                      child: Text('No products available yet',
                          style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.textSecondary)),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: snap.data!.docs.length,
                    separatorBuilder: (_, __) => Divider(
                      color: isDark
                          ? AppTheme.darkDivider
                          : Colors.grey.shade100,
                      height: 1,
                    ),
                    itemBuilder: (context, i) {
                      final p = snap.data!.docs[i].data()
                          as Map<String, dynamic>;
                      final imgUrl = p['imageUrl'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: AppTheme.secondary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: imgUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(14),
                                      child: CachedNetworkImage(
                                        imageUrl: imgUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.coffee_rounded,
                                                color: AppTheme.primary),
                                      ),
                                    )
                                  : const Icon(Icons.coffee_rounded,
                                      color: AppTheme.primary, size: 26),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p['name'] ?? 'Item',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? AppTheme.darkTextPrimary
                                              : AppTheme.textPrimary)),
                                  if ((p['description'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Text(
                                      p['description'],
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? AppTheme.darkTextSecondary
                                              : AppTheme.textSecondary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '\$${((p['price'] ?? 0) as num).toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Sign in footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppTheme.darkDivider
                        : Colors.grey.shade100,
                  ),
                ),
              ),
              child: Column(
                children: [
                  Text('Sign in to place an order',
                      style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.textSecondary)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        );
                      },
                      child: const Text('Sign In to Order'),
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
}