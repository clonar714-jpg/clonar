import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/AppColors.dart';
import '../services/GeocodingService.dart';

class GoogleMapWidget extends StatefulWidget {
  final double? latitude;
  final double? longitude;
  final String? address;
  final String? title;
  final double height;
  final bool showMarker;
  final bool interactive;

  const GoogleMapWidget({
    super.key,
    this.latitude,
    this.longitude,
    this.address,
    this.title,
    this.height = 200,
    this.showMarker = true,
    this.interactive = true,
  });

  @override
  State<GoogleMapWidget> createState() => _GoogleMapWidgetState();
}

class _GoogleMapWidgetState extends State<GoogleMapWidget> {
  GoogleMapController? _mapController;
  LatLng? _targetLocation;
  bool _isGeocoding = false;

  @override
  void initState() {
    super.initState();
    _initializeLocation();
  }

  // Default location: Salt Lake City, UT
  static const LatLng _defaultLocation = LatLng(40.7608, -111.8910);

  Future<void> _initializeLocation() async {
    if (widget.latitude != null && widget.longitude != null) {
      // Validate coordinates (not 0,0)
      if (widget.latitude != 0.0 && widget.longitude != 0.0) {
        setState(() {
          _targetLocation = LatLng(widget.latitude!, widget.longitude!);
        });
        return;
      }
    }
    
    // Try to geocode the address (only if coordinates not provided)
    if (widget.address != null && widget.address!.isNotEmpty && widget.latitude == null && widget.longitude == null) {
      setState(() {
        _isGeocoding = true;
      });
      
      print('📍 GoogleMapWidget: Geocoding address: ${widget.address}');
      try {
        final coords = await GeocodingService.geocodeAddress(widget.address!)
            .timeout(const Duration(seconds: 10)); // Increased timeout
        
        if (coords != null && mounted) {
          final lat = coords['latitude']!;
          final lng = coords['longitude']!;
          
          // Validate coordinates
          if (lat != 0.0 && lng != 0.0) {
            print('✅ GoogleMapWidget: Geocoded successfully: $lat, $lng');
            setState(() {
              _targetLocation = LatLng(lat, lng);
              _isGeocoding = false;
            });
            return;
          } else {
            print('⚠️ GoogleMapWidget: Geocoded to 0,0 - invalid');
          }
        } else {
          print('⚠️ GoogleMapWidget: Geocoding returned null');
        }
      } catch (e) {
        print('❌ GoogleMapWidget: Geocoding error: $e');
      }
      
      // ✅ REMOVED: Don't fallback to city-level geocoding for places
      // This was causing city-level maps instead of specific locations
      // If geocoding fails, we'll use default location
    }
    
    // Fallback to default location (Salt Lake City)
    if (mounted) {
      setState(() {
        _targetLocation = _defaultLocation;
        _isGeocoding = false;
      });
    }
  }

  // Extract city name from address string (e.g., "Salt Lake City" from "hotels in salt lake city")
  String? _extractCityFromAddress(String address) {
    // Common patterns: "in [City]", "[City]", "hotels in [City]"
    final patterns = [
      RegExp(r'in\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
      RegExp(r'([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)', caseSensitive: false),
    ];
    
    for (final pattern in patterns) {
      final match = pattern.firstMatch(address);
      if (match != null) {
        final city = match.group(1)?.trim();
        if (city != null && city.length > 2) {
          return city;
        }
      }
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Always show a map with a valid location
    final location = _targetLocation ?? _defaultLocation;
    final isValidLocation = location.latitude != 0.0 && location.longitude != 0.0;
    final showMarker = widget.showMarker && isValidLocation && 
                       _targetLocation != null &&
                       _targetLocation != _defaultLocation;
    
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: location,
                // ✅ FIX: Higher zoom for specific locations (15-16), lower for city-level (12)
                zoom: isValidLocation && _targetLocation != _defaultLocation ? 15.5 : 12.0,
              ),
              markers: showMarker && _targetLocation != null && _targetLocation != _defaultLocation
                  ? {
                      Marker(
                        markerId: const MarkerId('location'),
                        position: _targetLocation!,
                        infoWindow: widget.title != null
                            ? InfoWindow(title: widget.title!)
                            : const InfoWindow(),
                      ),
                    }
                  : {},
              zoomControlsEnabled: widget.interactive,
              zoomGesturesEnabled: widget.interactive,
              scrollGesturesEnabled: widget.interactive,
              rotateGesturesEnabled: widget.interactive,
              tiltGesturesEnabled: widget.interactive,
              mapType: MapType.normal,
              onMapCreated: (GoogleMapController controller) {
                print('🗺️ GoogleMapWidget: Map created successfully');
                print('🗺️ Location: ${location.latitude}, ${location.longitude}');
                _mapController = controller;
                // Temporarily disable custom style to test if it's causing tile loading issues
                // _setMapStyle();
                print('🗺️ GoogleMapWidget: Using default map style (custom style disabled for testing)');
              },
              onCameraIdle: () {
                print('🗺️ GoogleMapWidget: Camera idle');
              },
              onTap: (LatLng position) {
                print('🗺️ GoogleMapWidget: Map tapped at ${position.latitude}, ${position.longitude}');
              },
              // Temporarily disable custom style to test tile loading
              // style: _getDarkMapStyle(),
            ),
            // Show loading indicator while geocoding
            if (_isGeocoding)
              Container(
                color: AppColors.surface.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
            Text(
                        'Loading map...',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
              ),
            ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _setMapStyle() {
    if (_mapController != null) {
      _mapController!.setMapStyle(_getDarkMapStyle());
    }
  }

  String _getDarkMapStyle() {
    return '''
    [
      {
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#212121"
          }
        ]
      },
      {
        "elementType": "labels.icon",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "color": "#212121"
          }
        ]
      },
      {
        "featureType": "administrative",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "featureType": "administrative.country",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#9e9e9e"
          }
        ]
      },
      {
        "featureType": "administrative.land_parcel",
        "stylers": [
          {
            "visibility": "off"
          }
        ]
      },
      {
        "featureType": "administrative.locality",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#bdbdbd"
          }
        ]
      },
      {
        "featureType": "poi",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "featureType": "poi.park",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#181818"
          }
        ]
      },
      {
        "featureType": "poi.park",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#616161"
          }
        ]
      },
      {
        "featureType": "poi.park",
        "elementType": "labels.text.stroke",
        "stylers": [
          {
            "color": "#1b1b1b"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "geometry.fill",
        "stylers": [
          {
            "color": "#2c2c2c"
          }
        ]
      },
      {
        "featureType": "road",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#8a8a8a"
          }
        ]
      },
      {
        "featureType": "road.arterial",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#373737"
          }
        ]
      },
      {
        "featureType": "road.highway",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#3c3c3c"
          }
        ]
      },
      {
        "featureType": "road.highway.controlled_access",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#4e4e4e"
          }
        ]
      },
      {
        "featureType": "road.local",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#616161"
          }
        ]
      },
      {
        "featureType": "transit",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#757575"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "geometry",
        "stylers": [
          {
            "color": "#000000"
          }
        ]
      },
      {
        "featureType": "water",
        "elementType": "labels.text.fill",
        "stylers": [
          {
            "color": "#3d3d3d"
          }
        ]
      }
    ]
    ''';
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

