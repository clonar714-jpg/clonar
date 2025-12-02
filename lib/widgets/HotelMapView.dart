import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/AppColors.dart';

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
    // Initialize map data asynchronously to avoid blocking UI
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
      print('❌ HotelMapView initialization error: $e');
      if (mounted) {
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
    if (!_isMapReady || widget.points.isEmpty || _markers.isEmpty || _center == null) {
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
      Widget mapWidget = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: widget.height ?? 220,
          child: Stack(
          children: [
              GoogleMap(
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

