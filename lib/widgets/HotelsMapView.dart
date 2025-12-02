import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math;
import '../theme/AppColors.dart';
import '../services/GeocodingService.dart';
import 'RatingBubbleMarker.dart';

class HotelsMapView extends StatefulWidget {
  final List<Map<String, dynamic>> hotels;
  final List<Map<String, dynamic>>? mapPoints; // Optional: Direct map points from backend
  final Function(Map<String, dynamic>) onHotelTap;
  final Function(Map<String, dynamic>) onDirectionsTap;

  const HotelsMapView({
    super.key,
    required this.hotels,
    this.mapPoints,
    required this.onHotelTap,
    required this.onDirectionsTap,
  });

  @override
  State<HotelsMapView> createState() => _HotelsMapViewState();
}

class _HotelsMapViewState extends State<HotelsMapView> {
  GoogleMapController? _mapController;
  Map<MarkerId, Marker> _markers = {};
  Map<String, dynamic>? _selectedHotel;
  LatLng? _userLocation;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _getUserLocation();
  }

  Future<void> _initializeMap() async {
    await _createMarkers();
    _fitBounds();
  }

  Future<void> _createMarkers() async {
    try {
      _markers.clear();
      
      // ✅ Use mapPoints if provided (from backend), otherwise extract from hotels
      if (widget.mapPoints != null && widget.mapPoints!.isNotEmpty) {
        print('📍 Creating markers from ${widget.mapPoints!.length} map points');
        
        for (int i = 0; i < widget.mapPoints!.length; i++) {
          final point = widget.mapPoints![i];
          final lat = point['lat'] ?? point['latitude'];
          final lng = point['lng'] ?? point['longitude'];
          final name = point['name']?.toString() ?? 'Unknown';
          final rating = point['rating']?.toString() ?? '0.0';
          
          if (lat != null && lng != null) {
            print('📍 Map point $i ($name): lat=$lat, lng=$lng, rating=$rating');
            
            // Format rating to show one decimal place (e.g., "4.4")
            final ratingNum = double.tryParse(rating.toString()) ?? 0.0;
            final ratingText = ratingNum.toStringAsFixed(1);
            
            // Create custom rating bubble marker (Perplexity style)
            final customIcon = await createRatingBubbleMarker(ratingText);
            
            final markerId = MarkerId('hotel_$i');
            final marker = Marker(
              markerId: markerId,
              position: LatLng(lat.toDouble(), lng.toDouble()),
              icon: customIcon,
              anchor: const Offset(0.5, 0.5), // Center the marker on the location
              onTap: () {
                // Find corresponding hotel from hotels list
                final hotel = widget.hotels.firstWhere(
                  (h) => (h['name']?.toString() ?? h['title']?.toString()) == name,
                  orElse: () => point,
                );
                setState(() {
                  _selectedHotel = hotel;
                });
              },
            );
            
            _markers[markerId] = marker;
          }
        }
      } else {
        // Fallback: Extract coordinates from hotels
        print('📍 Creating markers for ${widget.hotels.length} hotels');
        
        for (int i = 0; i < widget.hotels.length; i++) {
          final hotel = widget.hotels[i];
          final hotelName = hotel['name']?.toString() ?? hotel['title']?.toString() ?? 'Unknown';
          final coords = GeocodingService.extractCoordinates(hotel);
          
          if (coords != null && coords['latitude'] != null && coords['longitude'] != null) {
            final lat = coords['latitude']!;
            final lng = coords['longitude']!;
            final rating = hotel['rating']?.toString() ?? '0.0';
            
            print('📍 Hotel $i ($hotelName): lat=$lat, lng=$lng, rating=$rating');
            
            // Format rating to show one decimal place (e.g., "4.4")
            final ratingNum = double.tryParse(rating) ?? 0.0;
            final ratingText = ratingNum.toStringAsFixed(1);
            
            // Create custom rating bubble marker (Perplexity style)
            final customIcon = await createRatingBubbleMarker(ratingText);
            
            final markerId = MarkerId('hotel_$i');
            final marker = Marker(
              markerId: markerId,
              position: LatLng(lat, lng),
              icon: customIcon,
              anchor: const Offset(0.5, 0.5), // Center the marker on the location
              onTap: () {
                setState(() {
                  _selectedHotel = hotel;
                });
              },
            );
            
            _markers[markerId] = marker;
          } else {
            final address = hotel['address']?.toString() ?? hotel['location']?.toString() ?? 'No address';
            print('⚠️ Hotel $i ($hotelName): No coordinates found. Address: $address');
          }
        }
      }
      
      print('✅ Created ${_markers.length} markers');
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        }); // Update UI with new markers
      }
    } catch (e) {
      print('❌ Error creating markers: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading map: $e';
        });
      }
    }
  }

  void _fitBounds() {
    if (_markers.isEmpty || _mapController == null) return;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    _markers.values.forEach((marker) {
      final lat = marker.position.latitude;
      final lng = marker.position.longitude;
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
      minLng = math.min(minLng, lng);
      maxLng = math.max(maxLng, lng);
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

  Future<void> _getUserLocation() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      print('Error getting user location: $e');
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km
    final dLat = _degreesToRadians(point2.latitude - point1.latitude);
    final dLng = _degreesToRadians(point2.longitude - point1.longitude);
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(point1.latitude)) *
            math.cos(_degreesToRadians(point2.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  String _formatDistance(double distanceKm) {
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()}m';
    } else {
      return '${distanceKm.toStringAsFixed(1)}mi';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show error message if map failed to load
    if (_errorMessage != null) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.75,
        color: AppColors.surface,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Please check:\n1. Google Maps API key is configured\n2. Internet connection is active',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading indicator while markers are being created
    if (_isLoading && _markers.isEmpty) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.75,
        color: AppColors.surface,
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      );
    }
    
    return Stack(
      children: [
        // Map
        GoogleMap(
          initialCameraPosition: const CameraPosition(
            target: LatLng(40.7608, -111.8910), // Salt Lake City default
            zoom: 12.0,
          ),
          markers: Set<Marker>.from(_markers.values),
          zoomControlsEnabled: true,
          zoomGesturesEnabled: true,
          scrollGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          mapType: MapType.normal,
          onMapCreated: (GoogleMapController controller) async {
            print('🗺️ Map created successfully');
            _mapController = controller;
            // Temporarily disable custom style to test tile loading
            // try {
            //   await _setMapStyle();
            //   print('✅ Map style applied');
            // } catch (e) {
            //   print('⚠️ Error setting map style: $e');
            // }
            print('🗺️ Using default map style (custom style disabled for testing)');
            // Wait for markers to be created, then fit bounds
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (_mapController != null && _markers.isNotEmpty) {
                _fitBounds();
                print('✅ Map bounds fitted');
              }
            });
          },
          onCameraMoveStarted: () {
            print('📷 Camera move started');
          },
          onCameraIdle: () {
            print('📷 Camera idle');
          },
          // Temporarily disable custom style to test tile loading
          // style: _getDarkMapStyle(),
        ),
        
        // Hotel card overlay at bottom
        if (_selectedHotel != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildHotelCardOverlay(_selectedHotel!),
          ),
      ],
    );
  }

  Widget _buildHotelCardOverlay(Map<String, dynamic> hotel) {
    final hotelName = hotel['name']?.toString() ?? 
                     hotel['title']?.toString() ?? 
                     'Unknown Hotel';
    final rating = hotel['rating']?.toString() ?? '0.0';
    final reviewCount = hotel['reviews']?.toString() ?? hotel['reviewCount']?.toString() ?? '0';
    final address = hotel['address']?.toString() ?? 
                   hotel['location']?.toString() ?? 
                   'Address not available';
    
    // Calculate distance if user location is available
    String? distanceText;
    final coords = GeocodingService.extractCoordinates(hotel);
    if (_userLocation != null && coords != null) {
      final hotelLat = coords['latitude'];
      final hotelLng = coords['longitude'];
      if (hotelLat != null && hotelLng != null) {
        final distance = _calculateDistance(
          _userLocation!,
          LatLng(hotelLat, hotelLng),
        );
        distanceText = _formatDistance(distance);
      }
    }
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hotel name and rating
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hotelName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () {
                        setState(() {
                          _selectedHotel = null;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (distanceText != null) ...[
                      Text(
                        distanceText,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Text(
                        ' · ',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                    Text(
                      address,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '$rating ($reviewCount)',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppColors.surfaceVariant,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    'Details',
                    Icons.info_outline,
                    () => widget.onHotelTap(hotel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    'Directions',
                    Icons.directions,
                    () => widget.onDirectionsTap(hotel),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setMapStyle() async {
    if (_mapController != null) {
      await _mapController!.setMapStyle(_getDarkMapStyle());
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
}

