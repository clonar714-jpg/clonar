import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/AppColors.dart';

// ✅ PATCH A: Add static key for stable map instance
const hotelPreviewMapKey = ValueKey("hotel_preview_static_map");

class HotelMapView extends StatefulWidget {
  final List<dynamic> points;
  final double? height;
  final VoidCallback? onTap;

  const HotelMapView({
    Key? key,
    required this.points,
    this.height,
    this.onTap,
  }) : super(key: key);

  @override
  State<HotelMapView> createState() => _HotelMapViewState();
}

class _HotelMapViewState extends State<HotelMapView> {
  GoogleMapController? _mapController;
  bool _isMapReady = false;
  Set<Marker> _markers = {};
  LatLng? _center;

  @override
  void initState() {
    super.initState();
    // ✅ PATCH C: Initialize map asynchronously using microtask (prevents blocking UI)
    Future.microtask(_initializeMap);
  }

  void _initializeMap() {
    try {
      print('🗺️ HotelMapView: Initializing with ${widget.points.length} points');
      if (widget.points.isEmpty) {
        print('⚠️ HotelMapView: No points provided');
        // ✅ PATCH D: Avoid setState if nothing changed
        if (!_isMapReady && mounted) {
          setState(() => _isMapReady = true);
        }
        return;
      }

      // Filter out invalid points
      final validPoints = widget.points.where((p) {
        final lat = p["lat"] ?? p["latitude"];
        final lng = p["lng"] ?? p["longitude"];
        return lat != null && lng != null;
      }).toList();

      print('🗺️ HotelMapView: ${validPoints.length} valid points out of ${widget.points.length}');
      if (validPoints.isEmpty) {
        print('⚠️ HotelMapView: No valid points after filtering');
        // ✅ PATCH D: Avoid setState if nothing changed
        if (!_isMapReady && mounted) {
          setState(() => _isMapReady = true);
        }
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

      print('✅ HotelMapView: Created ${_markers.length} markers, center at ${_center!.latitude}, ${_center!.longitude}');

      // ✅ PATCH D: Avoid setState if nothing changed (prevents unnecessary rebuilds)
      if (!_isMapReady && mounted) {
        setState(() => _isMapReady = true);
        print('✅ HotelMapView: Map marked as ready');
      }
    } catch (e) {
      print('❌ HotelMapView initialization error: $e');
      // ✅ PATCH D: Avoid setState if nothing changed
      if (!_isMapReady && mounted) {
        setState(() => _isMapReady = true);
      }
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always show placeholder initially to prevent blocking
    print('🗺️ HotelMapView build: isMapReady=$_isMapReady, points=${widget.points.length}, markers=${_markers.length}, center=${_center != null}');
    if (!_isMapReady || widget.points.isEmpty || _markers.isEmpty || _center == null) {
      print('⚠️ HotelMapView: Showing placeholder (not ready yet)');
      return Container(
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(
            Icons.map_outlined,
            color: AppColors.textSecondary,
            size: 48,
          ),
        ),
      );
    }

    // Show map once ready - wrapped in error boundary
    try {
      // ✅ PATCH B: Wrap map in RepaintBoundary and add stable key (prevents unnecessary rebuilds)
      Widget mapWidget = RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: widget.height ?? 220,
            child: Stack(
              children: [
                GoogleMap(
                  key: hotelPreviewMapKey, // 🔥 IMPORTANT: Stable key prevents recreation
                  initialCameraPosition: CameraPosition(
                    target: _center!,
                    zoom: 12.5,
                  ),
                  markers: _markers,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapType: MapType.normal,
                  liteModeEnabled: false, // Disable lite mode to prevent issues
                  // Disable all gestures if onTap is provided (to allow overlay to capture taps)
                  zoomGesturesEnabled: widget.onTap == null,
                  scrollGesturesEnabled: widget.onTap == null,
                  rotateGesturesEnabled: widget.onTap == null,
                  tiltGesturesEnabled: widget.onTap == null,
                  onMapCreated: (GoogleMapController controller) {
                    _mapController = controller;
                    print('✅ HotelMapView: Map created with ${_markers.length} markers');
                    print('🗺️ HotelMapView: Center at ${_center!.latitude}, ${_center!.longitude}');
                  },
                  onCameraIdle: () {
                    print('🗺️ HotelMapView: Camera idle - map should be fully loaded');
                  },
                  onTap: (LatLng position) {
                    // Trigger onTap when map is tapped (not markers)
                    if (widget.onTap != null) {
                      widget.onTap!();
                    }
                  },
                ),
                // Full transparent overlay to capture all taps when onTap is provided
                if (widget.onTap != null)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: widget.onTap,
                      behavior: HitTestBehavior.translucent,
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      // Wrap in GestureDetector if onTap is provided
      if (widget.onTap != null) {
      return GestureDetector(
          onTap: widget.onTap,
        child: mapWidget,
      );
    }

    return mapWidget;
    } catch (e) {
      print('❌ HotelMapView build error: $e');
      // Fallback to placeholder on error
      return Container(
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Icon(
            Icons.map_outlined,
            color: AppColors.textSecondary,
            size: 48,
          ),
        ),
      );
    }
  }
}

