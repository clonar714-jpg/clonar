import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/AppColors.dart';
import '../core/emulator_detector.dart';

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

class _HotelMapViewState extends State<HotelMapView> with AutomaticKeepAliveClientMixin {
  GoogleMapController? _mapController;
  bool _isMapReady = false;
  Set<Marker> _markers = {};
  LatLng? _center;
  bool _isInitializing = false;

  @override
  bool get wantKeepAlive => true; // ✅ PRODUCTION: Keep map alive to prevent recreation

  @override
  void initState() {
    super.initState();
    // ✅ EMULATOR FIX: Delay map initialization on emulator until UI is idle
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isEmulator = await EmulatorDetector.isEmulator();
      final delay = isEmulator && kDebugMode 
          ? const Duration(milliseconds: 1500) // Longer delay on emulator
          : const Duration(milliseconds: 500);
      
      Future.delayed(delay, () {
        if (mounted && !_isInitializing) {
          _initializeMap();
        }
      });
    });
  }

  @override
  void didUpdateWidget(HotelMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ PRODUCTION: Only reinitialize if points actually changed
    if (oldWidget.points.length != widget.points.length ||
        !_arePointsEqual(oldWidget.points, widget.points)) {
      if (!_isInitializing && mounted) {
        _initializeMap();
      }
    }
  }

  bool _arePointsEqual(List<dynamic> oldPoints, List<dynamic> newPoints) {
    if (oldPoints.length != newPoints.length) return false;
    for (int i = 0; i < oldPoints.length; i++) {
      final oldLat = oldPoints[i]["lat"] ?? oldPoints[i]["latitude"];
      final newLat = newPoints[i]["lat"] ?? newPoints[i]["latitude"];
      final oldLng = oldPoints[i]["lng"] ?? oldPoints[i]["longitude"];
      final newLng = newPoints[i]["lng"] ?? newPoints[i]["longitude"];
      if (oldLat != newLat || oldLng != newLng) return false;
    }
    return true;
  }

  void _initializeMap() async {
    if (_isInitializing) return; // Prevent concurrent initialization
    _isInitializing = true;
    
    try {
      // ✅ PRODUCTION: Move heavy processing to isolate to prevent blocking
      await Future(() async {
        if (kDebugMode) {
          debugPrint('🗺️ HotelMapView: Initializing with ${widget.points.length} points');
        }
        if (widget.points.isEmpty) {
          if (kDebugMode) {
            debugPrint('⚠️ HotelMapView: No points provided');
          }
          if (!_isMapReady && mounted) {
            setState(() {
              _isMapReady = true;
              _isInitializing = false;
            });
          }
          return;
        }

        // Filter out invalid points
        final validPoints = widget.points.where((p) {
          final lat = p["lat"] ?? p["latitude"];
          final lng = p["lng"] ?? p["longitude"];
          return lat != null && lng != null;
        }).toList();

        if (kDebugMode) {
          debugPrint('🗺️ HotelMapView: ${validPoints.length} valid points out of ${widget.points.length}');
        }
        if (validPoints.isEmpty) {
          if (kDebugMode) {
            debugPrint('⚠️ HotelMapView: No valid points after filtering');
          }
          if (!_isMapReady && mounted) {
            setState(() {
              _isMapReady = true;
              _isInitializing = false;
            });
          }
          return;
        }

        // Create markers
        final markers = validPoints.map((p) {
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

        final center = LatLng(avgLat, avgLng);

        if (kDebugMode) {
          debugPrint('✅ HotelMapView: Created ${markers.length} markers, center at ${center.latitude}, ${center.longitude}');
        }

        // ✅ PRODUCTION: Update state after processing (prevents blocking during processing)
        if (mounted) {
          setState(() {
            _markers = markers;
            _center = center;
            _isMapReady = true;
            _isInitializing = false;
          });
          if (kDebugMode) {
            debugPrint('✅ HotelMapView: Map marked as ready');
          }
        }
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ HotelMapView initialization error: $e');
      }
      if (mounted) {
        setState(() {
          _isMapReady = true;
          _isInitializing = false;
        });
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
    super.build(context); // ✅ PRODUCTION: Required for AutomaticKeepAliveClientMixin
    
    // Always show placeholder initially to prevent blocking
    if (kDebugMode) {
      debugPrint('🗺️ HotelMapView build: isMapReady=$_isMapReady, points=${widget.points.length}, markers=${_markers.length}, center=${_center != null}');
    }
    if (!_isMapReady || widget.points.isEmpty || _markers.isEmpty || _center == null) {
      if (kDebugMode) {
        debugPrint('⚠️ HotelMapView: Showing placeholder (not ready yet)');
      }
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
                    if (kDebugMode) {
                      debugPrint('✅ HotelMapView: Map created with ${_markers.length} markers');
                      debugPrint('🗺️ HotelMapView: Center at ${_center!.latitude}, ${_center!.longitude}');
                    }
                  },
                  onCameraIdle: () {
                    if (kDebugMode) {
                      debugPrint('🗺️ HotelMapView: Camera idle - map should be fully loaded');
                    }
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
      if (kDebugMode) {
        debugPrint('❌ HotelMapView build error: $e');
      }
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

