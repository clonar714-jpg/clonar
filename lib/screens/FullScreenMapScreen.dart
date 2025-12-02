import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class FullScreenMapScreen extends StatefulWidget {
  final List<dynamic> points;
  final String? title;

  const FullScreenMapScreen({
    Key? key,
    required this.points,
    this.title,
  }) : super(key: key);

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  GoogleMapController? _mapController;
  bool _isMapReady = false;
  Set<Marker> _markers = {};
  LatLng? _center;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMap();
    });
  }

  void _initializeMap() {
    try {
      if (widget.points.isEmpty) {
        setState(() => _isMapReady = true);
        return;
      }

      // Filter out invalid points
      final validPoints = widget.points.where((p) {
        final lat = p["lat"] ?? p["latitude"];
        final lng = p["lng"] ?? p["longitude"];
        return lat != null && lng != null;
      }).toList();

      if (validPoints.isEmpty) {
        setState(() => _isMapReady = true);
        return;
      }

      // Create markers
      _markers = validPoints.map((p) {
        final lat = (p["lat"] ?? p["latitude"]) as num;
        final lng = (p["lng"] ?? p["longitude"]) as num;
        return Marker(
          markerId: MarkerId(p["name"]?.toString() ?? "marker_${validPoints.indexOf(p)}"),
          position: LatLng(
            lat.toDouble(),
            lng.toDouble(),
          ),
          infoWindow: InfoWindow(
            title: p["name"]?.toString() ?? "Hotel",
            snippet: "${p["rating"] ?? 0} ★",
          ),
        );
      }).toSet();

      // Calculate center
      final avgLat = validPoints
              .map((p) => ((p["lat"] ?? p["latitude"]) as num).toDouble())
              .reduce((a, b) => a + b) /
          validPoints.length;
      final avgLng = validPoints
              .map((p) => ((p["lng"] ?? p["longitude"]) as num).toDouble())
              .reduce((a, b) => a + b) /
          validPoints.length;

      _center = LatLng(avgLat, avgLng);

      if (mounted) {
        setState(() => _isMapReady = true);
      }
    } catch (e) {
      print('❌ FullScreenMapScreen initialization error: $e');
      if (mounted) {
        setState(() => _isMapReady = true);
      }
    }
  }

  void _fitBounds() {
    if (_markers.isEmpty || _mapController == null || _center == null) return;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    _markers.forEach((marker) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      minLat = minLat < lat ? minLat : lat;
      maxLat = maxLat > lat ? maxLat : lat;
      minLng = minLng < lng ? minLng : lng;
      maxLng = maxLng > lng ? maxLng : lng;
    });

    if (minLat != double.infinity) {
      final bounds = LatLngBounds(
        southwest: LatLng(minLat - 0.01, minLng - 0.01),
        northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
      );
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      );
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Full screen map
          if (_isMapReady && _center != null && _markers.isNotEmpty)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _center!,
                zoom: 12.5,
              ),
              markers: _markers,
              zoomControlsEnabled: true,
              myLocationButtonEnabled: false,
              mapType: MapType.normal,
              liteModeEnabled: false,
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                print('✅ FullScreenMapScreen: Map created with ${_markers.length} markers');
                // Fit bounds after a short delay to ensure map is ready
                Future.delayed(const Duration(milliseconds: 500), () {
                  _fitBounds();
                });
              },
              onCameraIdle: () {
                print('🗺️ FullScreenMapScreen: Camera idle');
              },
            )
          else
            Container(
              color: AppColors.background,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // Back button at top
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface.withOpacity(0.9),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  tooltip: 'Back',
                ),
              ),
            ),
          ),

          // Title at top (optional)
          if (widget.title != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 16, left: 72, right: 16),
                child: Text(
                  widget.title!,
                  style: AppTypography.title1.copyWith(
                    color: AppColors.textPrimary,
              ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ),
        ],
      ),
    );
  }
}

