import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../widgets/CustomDatePicker.dart' as custom;
import '../services/AgentService.dart';
import 'HotelResultsScreen.dart';

class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key});

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  String _selectedTravelType = 'Flights'; // Flights, Stays, Cruise, Packages, Things to do
  String _selectedFlightType = 'Roundtrip'; // Roundtrip, One-way, Multi-city
  
  // Independent location state for each section
  String _staysLocation = '';
  String _flightsFromLocation = '';
  String _flightsToLocation = '';
  String _cruiseLocation = '';
  String _packagesLocation = '';
  String _thingsToDoLocation = '';
  
  // Shared date state (can be made independent if needed)
  DateTime? _departureDate;
  DateTime? _returnDate;
  String _travelers = '1 traveler, Economy';
  int _numTravelers = 1;
  String _cabinClass = 'Economy';
  int _numRooms = 1;
  int _numChildren = 0;
  String _searchPrompt = '';
  String _accommodationType = 'Any'; // Any, Hotels, Home
  late TextEditingController _promptController;
  late TextEditingController _locationController;
  late FocusNode _locationFocusNode;
  List<Map<String, dynamic>> _locationSuggestions = [];
  bool _showLocationSuggestions = false;
  
  // Multi-city flights
  List<Map<String, dynamic>> _multiCityFlights = [
    {'from': '', 'to': '', 'date': null},
    {'from': '', 'to': '', 'date': null},
  ];
  
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
  
  String _formatDateShort(DateTime? date) {
    if (date == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
  }
  
  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return '';
    if (start != null && end != null) {
      return '${_formatDateShort(start)} - ${_formatDateShort(end)}';
    }
    return _formatDate(start ?? end);
  }

  // Helper methods to get/set location based on current section
  String _getCurrentLocation() {
    switch (_selectedTravelType) {
      case 'Stays':
        return _staysLocation;
      case 'Flights':
        return _flightsToLocation; // For flights, we use "to" location in the location field
      case 'Cruise':
        return _cruiseLocation;
      case 'Packages':
        return _packagesLocation;
      case 'Things to do':
        return _thingsToDoLocation;
      default:
        return '';
    }
  }

  void _setCurrentLocation(String location) {
    switch (_selectedTravelType) {
      case 'Stays':
        _staysLocation = location;
        break;
      case 'Flights':
        _flightsToLocation = location;
        break;
      case 'Cruise':
        _cruiseLocation = location;
        break;
      case 'Packages':
        _packagesLocation = location;
        break;
      case 'Things to do':
        _thingsToDoLocation = location;
        break;
    }
  }

  void _saveCurrentLocation() {
    // Save current location controller value to the appropriate section variable
    _setCurrentLocation(_locationController.text);
  }

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: _searchPrompt);
    _promptController.addListener(() {
      setState(() {
        _searchPrompt = _promptController.text;
      });
    });
    // Initialize with current section's location
    _locationController = TextEditingController(text: _getCurrentLocation());
    _locationFocusNode = FocusNode();
    _locationController.addListener(() {
      _onLocationTextChanged(_locationController.text);
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _locationController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
  }

  void _onLocationTextChanged(String query) async {
    setState(() {
      _setCurrentLocation(query);
    });

    if (query.trim().length >= 2) {
      // Debounce: wait a bit before making API call
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Check if query hasn't changed during the delay
      if (_locationController.text.trim() == query.trim() && query.trim().length >= 2) {
        try {
          final suggestions = await AgentService.getLocationAutocomplete(query);
          if (mounted) {
            setState(() {
              _locationSuggestions = suggestions;
              _showLocationSuggestions = suggestions.isNotEmpty && _locationController.text.trim().length >= 2;
            });
          }
        } catch (e) {
          print('❌ Error fetching location suggestions: $e');
          if (mounted) {
            setState(() {
              _locationSuggestions = [];
              _showLocationSuggestions = false;
            });
          }
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _locationSuggestions = [];
          _showLocationSuggestions = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Section: Logo and Account Info
            _buildTopSection(),
            
            // Main Navigation Tabs (Stays, Flights, Cars, Packages)
            _buildMainNavigationTabs(),
            
            // Flight Type Tabs (if Flights is selected)
            if (_selectedTravelType == 'Flights')
              _buildFlightTypeTabs(),
            
            // Main Content Area
            Expanded(
              child: GestureDetector(
                onTap: () {
                  // Dismiss keyboard and hide suggestions when tapping outside
                  _locationFocusNode.unfocus();
                  FocusScope.of(context).unfocus();
                  setState(() {
                    _showLocationSuggestions = false;
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Booking Form
                      _buildBookingForm(),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Clonar Logo (matching Expedia style)
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB800), // Yellow like Expedia
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Text(
                    'C',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Clonar',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          
        ],
      ),
    );
  }

  Widget _buildMainNavigationTabs() {
    final tabs = ['Stays', 'Flights', 'Cruise', 'Packages', 'Things to do'];
    final icons = [
      Icons.bed,
      Icons.flight,
      Icons.directions_boat,
      Icons.luggage,
      Icons.local_activity,
    ];

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final isSelected = _selectedTravelType == tabs[index];
          return Expanded(
            child: GestureDetector(
                onTap: () {
                  setState(() {
                    // Save current location before switching
                    _saveCurrentLocation();
                    _selectedTravelType = tabs[index];
                    // Update location controller when switching sections
                    _locationController.text = _getCurrentLocation();
                  });
                },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icons[index],
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tabs[index],
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  if (isSelected)
                    Container(
                      width: 40,
                      height: 2,
                      color: AppColors.primary,
                    )
                  else
                    const SizedBox(height: 2),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFlightTypeTabs() {
    final types = ['Roundtrip', 'One-way', 'Multi-city'];
    
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: types.map((type) {
          final isSelected = _selectedFlightType == type;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedFlightType = type;
                  // Reset multi-city flights when switching to Multi-city
                  if (type == 'Multi-city') {
                    _multiCityFlights = [
                      {'from': '', 'to': '', 'date': null},
                      {'from': '', 'to': '', 'date': null},
                    ];
                  }
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    type,
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBookingForm() {
    if (_selectedTravelType == 'Flights') {
      return _buildFlightForm();
    } else if (_selectedTravelType == 'Stays') {
      return _buildStaysForm();
    } else if (_selectedTravelType == 'Cruise') {
      return _buildCruiseForm();
    } else if (_selectedTravelType == 'Things to do') {
      return _buildThingsToDoForm();
    } else {
      return _buildPackagesForm();
    }
  }

  Widget _buildFlightForm() {
    if (_selectedFlightType == 'Multi-city') {
      return _buildMultiCityForm();
    }
    
    return Column(
      children: [
        // Stack for Leaving from and Going to with swap arrow between
        Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                // Leaving from
                _buildFormField(
                  icon: Icons.location_on,
                  label: 'Leaving from',
                  value: _flightsFromLocation.isEmpty ? null : _flightsFromLocation,
                  hint: 'Leaving from',
                  onTap: () {
                    // TODO: Open location picker
                  },
                ),
                
                // Going to - wrapped to bring it closer to first box
                Transform.translate(
                  offset: const Offset(0, -18), // Move up to overlap with arrow
                  child: _buildFormField(
                    icon: Icons.location_on,
                    label: 'Going to',
                    value: _flightsToLocation.isEmpty ? null : _flightsToLocation,
                    hint: 'Going to',
                    onTap: () {
                      // TODO: Open location picker
                    },
                  ),
                ),
              ],
            ),
            
            // Swap arrow positioned between the two boxes
            // Position it to overlap both boxes equally
            // Box height is approximately 60px (padding 14*2 + content), arrow is 36px
            // Position arrow center at the boundary between boxes (60px)
            Positioned(
              left: 0,
              right: 0,
              top: 42, // 60px (box height) - 18px (half arrow height) = 42px
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      final temp = _flightsFromLocation;
                      _flightsFromLocation = _flightsToLocation;
                      _flightsToLocation = temp;
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.border.withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.swap_vert,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // Dates
        if (_selectedFlightType == 'Roundtrip')
          _buildFormField(
            icon: Icons.calendar_today,
            label: 'Select dates',
            value: _formatDateRange(_departureDate, _returnDate).isEmpty 
                ? null 
                : _formatDateRange(_departureDate, _returnDate),
            hint: 'Select dates',
            onTap: () async {
              final result = await custom.showCustomDatePicker(
                context: context,
                mode: custom.CustomDatePickerMode.roundTrip,
                initialStartDate: _departureDate,
                initialEndDate: _returnDate,
              );
                if (result['startDate'] != null || result['endDate'] != null) {
                  setState(() {
                    _departureDate = result['startDate'];
                    _returnDate = result['endDate'];
                  });
                }
            },
          )
        else
          _buildFormField(
            icon: Icons.calendar_today,
            label: 'Select departure date',
            value: _departureDate == null ? null : _formatDate(_departureDate),
            hint: 'Select departure date',
            onTap: () async {
              final result = await custom.showCustomDatePicker(
                context: context,
                mode: custom.CustomDatePickerMode.oneWay,
                initialStartDate: _departureDate,
              );
              if (result['startDate'] != null) {
                setState(() {
                  _departureDate = result['startDate'];
                  _returnDate = null;
                });
              }
            },
          ),
        
        const SizedBox(height: 12),
        
        // Travelers and Cabin class
        _buildFormField(
          icon: Icons.person,
          label: 'Travelers, Cabin class',
          value: _travelers,
          hint: 'Travelers, Cabin class',
          onTap: () {
            _showTravelersDialog();
          },
        ),
        
        const SizedBox(height: 20),
        
        // Search Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to search results
              print('Search flights: $_flightsFromLocation to $_flightsToLocation');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiCityForm() {
    return Column(
      children: [
        // Travelers and Cabin class (at top for Multi-city)
        _buildFormField(
          icon: Icons.person,
          label: 'Travelers, Cabin class',
          value: _travelers,
          hint: 'Travelers, Cabin class',
          onTap: () {
            _showTravelersDialog();
          },
        ),
        
        const SizedBox(height: 20),
        
        // Flight segments
        ...List.generate(_multiCityFlights.length, (index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Flight number label
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Flight ${index + 1}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              
              // Leaving from
              _buildFormField(
                icon: Icons.location_on,
                label: 'Leaving from',
                value: _multiCityFlights[index]['from']?.isEmpty ?? true
                    ? null 
                    : _multiCityFlights[index]['from'],
                hint: 'Leaving from',
                onTap: () {
                  // TODO: Open location picker for flight index
                },
                trailing: GestureDetector(
                  onTap: () {
                    setState(() {
                      final temp = _multiCityFlights[index]['from'] ?? '';
                      _multiCityFlights[index]['from'] = _multiCityFlights[index]['to'] ?? '';
                      _multiCityFlights[index]['to'] = temp;
                    });
                  },
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.border.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: const Icon(
                      Icons.swap_vert,
                      color: AppColors.textPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Going to
              _buildFormField(
                icon: Icons.location_on,
                label: 'Going to',
                value: _multiCityFlights[index]['to']?.isEmpty ?? true
                    ? null 
                    : _multiCityFlights[index]['to'],
                hint: 'Going to',
                onTap: () {
                  // TODO: Open location picker for flight index
                },
              ),
              
              const SizedBox(height: 12),
              
              // Departure date
              _buildFormField(
                icon: Icons.calendar_today,
                label: 'Select departure date',
                value: _multiCityFlights[index]['date'] == null
                    ? null 
                    : _formatDate(_multiCityFlights[index]['date'] as DateTime?),
                hint: 'Select departure date',
                onTap: () async {
                  final result = await custom.showCustomDatePicker(
                    context: context,
                    mode: custom.CustomDatePickerMode.multiCity,
                    initialStartDate: _multiCityFlights[index]['date'] as DateTime?,
                  );
                  if (result['startDate'] != null) {
                    setState(() {
                      _multiCityFlights[index]['date'] = result['startDate'];
                    });
                  }
                },
              ),
              
              if (index < _multiCityFlights.length - 1) const SizedBox(height: 24),
            ],
          );
        }),
        
        const SizedBox(height: 16),
        
        // Add another flight button
        GestureDetector(
          onTap: () {
            setState(() {
              _multiCityFlights.add({'from': '', 'to': '', 'date': ''});
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.primary,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                const Icon(
                  Icons.add,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Add another flight',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Search Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to search results
              print('Search multi-city flights');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStaysForm() {
    return Column(
      children: [
        _buildLocationField(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                icon: Icons.calendar_today,
                label: 'Dates',
                value: _formatDateRange(_departureDate, _returnDate).isEmpty 
                    ? null 
                    : _formatDateRange(_departureDate, _returnDate),
                hint: 'Dates',
                onTap: () async {
                  final result = await custom.showCustomDatePicker(
                    context: context,
                    mode: custom.CustomDatePickerMode.roundTrip,
                    initialStartDate: _departureDate,
                    initialEndDate: _returnDate,
                  );
                  if (result['startDate'] != null || result['endDate'] != null) {
                    setState(() {
                      _departureDate = result['startDate'];
                      _returnDate = result['endDate'];
                    });
                    // Unfocus any text fields after date selection
                    FocusScope.of(context).unfocus();
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAccommodationTypeDropdown(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildFormField(
          icon: Icons.person,
          label: 'Travelers',
          value: _buildTravelersText(),
          hint: 'Travelers',
          onTap: () {
            _showTravelersDialog();
          },
        ),
        const SizedBox(height: 12),
        _buildPromptField(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              _performStaysSearch();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _buildTravelersText() {
    final totalTravelers = _numTravelers + _numChildren;
    final travelersText = totalTravelers == 1 ? '1 traveler' : '$totalTravelers travelers';
    final roomsText = _numRooms == 1 ? '1 room' : '$_numRooms rooms';
    return '$travelersText, $roomsText';
  }

  void _performStaysSearch() {
    // Build LLM-friendly query from form data
    final query = _buildStaysSearchQuery();
    
    if (query.isEmpty) {
      // Show error if location is not filled
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a location'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Calculate total travelers (adults + children)
    final totalTravelers = _numTravelers + _numChildren;

    // Navigate to HotelResultsScreen with the query and form data
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HotelResultsScreen(
          fromTravelScreen: true,
          query: query,
          checkInDate: _departureDate,
          checkOutDate: _returnDate,
          guestCount: totalTravelers,
          roomCount: _numRooms,
        ),
      ),
    );
  }

  String _buildStaysSearchQuery() {
    // Start with location (required)
    if (_staysLocation.isEmpty) {
      return '';
    }

    final List<String> queryParts = [];

    // Add accommodation type
    if (_accommodationType == 'Hotels') {
      queryParts.add('hotels');
    } else if (_accommodationType == 'Home') {
      queryParts.add('vacation rentals');
    } else {
      // "Any" - use "accommodations" to be inclusive
      queryParts.add('accommodations');
    }

    // Add location
    queryParts.add('in $_staysLocation');

    // Add description/prompt if provided
    if (_searchPrompt.trim().isNotEmpty) {
      queryParts.add(_searchPrompt.trim());
    }

    // Combine all parts into a natural language query
    return queryParts.join(' ');
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _locationController,
          focusNode: _locationFocusNode,
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            labelText: 'Going to',
            labelStyle: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary.withOpacity(0.8),
            ),
            hintText: 'Going to',
            hintStyle: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary.withOpacity(0.6),
            ),
            prefixIcon: Icon(
              Icons.location_on,
              color: AppColors.textSecondary,
              size: 18,
            ),
            filled: true,
            fillColor: const Color(0xFF1E1E1E),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.border.withOpacity(0.2),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.border.withOpacity(0.2),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: AppColors.primary.withOpacity(0.5),
                width: 1.5,
              ),
            ),
          ),
          onTap: () {
            setState(() {
              if (_locationSuggestions.isNotEmpty) {
                _showLocationSuggestions = true;
              }
            });
          },
        ),
        // Only show suggestions when typing and field is focused
        if (_showLocationSuggestions && 
            _locationSuggestions.isNotEmpty && 
            _locationFocusNode.hasFocus &&
            _locationController.text.trim().length >= 2)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.border.withOpacity(0.2),
                width: 1,
              ),
            ),
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _locationSuggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _locationSuggestions[index];
                final description = suggestion['description'] as String? ?? '';
                final mainText = suggestion['main_text'] as String? ?? '';
                final secondaryText = suggestion['secondary_text'] as String? ?? '';
                
                return InkWell(
                  onTap: () {
                    // Update location for current section
                    _setCurrentLocation(description);
                    _locationController.text = description;
                    
                    // Close suggestions immediately
                    setState(() {
                      _showLocationSuggestions = false;
                      _locationSuggestions = [];
                    });
                    
                    // Unfocus the location field
                    _locationFocusNode.unfocus();
                    FocusScope.of(context).unfocus();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (mainText.isNotEmpty)
                                Text(
                                  mainText,
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (secondaryText.isNotEmpty)
                                Text(
                                  secondaryText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildAccommodationTypeDropdown() {
    return GestureDetector(
      onTap: () {
        _showAccommodationTypeDialog();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.border.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.home,
              color: AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Accommodation',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _accommodationType,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showAccommodationTypeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Accommodation Type',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              ...['Any', 'Hotels', 'Home'].map((type) {
                return RadioListTile<String>(
                  title: Text(
                    type,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  value: type,
                  groupValue: _accommodationType,
                  onChanged: (value) {
                    setState(() {
                      _accommodationType = value!;
                    });
                    Navigator.pop(context);
                  },
                  activeColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPromptField() {
    return TextField(
      controller: _promptController,
      minLines: 1,
      maxLines: 6,
      style: TextStyle(
        fontSize: 15,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: 'Enter your search prompt or text',
        hintStyle: TextStyle(
          fontSize: 15,
          color: AppColors.textSecondary.withOpacity(0.6),
        ),
        prefixIcon: Icon(
          Icons.edit_note,
          color: AppColors.textSecondary,
          size: 18,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 48,
          minHeight: 24,
        ),
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        contentPadding: const EdgeInsets.all(14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.border.withOpacity(0.2),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.border.withOpacity(0.2),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.primary.withOpacity(0.5),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCruiseForm() {
    return Column(
      children: [
        _buildFormField(
          icon: Icons.location_on,
          label: 'Pick-up location',
          value: _flightsFromLocation.isEmpty ? null : _flightsFromLocation,
          hint: 'Pick-up location',
          onTap: () {
            // TODO: Open location picker
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildFormField(
                icon: Icons.calendar_today,
                label: 'Pick-up date',
                value: _departureDate == null ? null : _formatDate(_departureDate),
                hint: 'Pick-up date',
                onTap: () async {
                  final result = await custom.showCustomDatePicker(
                    context: context,
                    mode: custom.CustomDatePickerMode.singleDate,
                    initialStartDate: _departureDate,
                  );
                  if (result['startDate'] != null) {
                setState(() {
                  _departureDate = result['startDate'];
                });
              }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildFormField(
                icon: Icons.calendar_today,
                label: 'Drop-off date',
                value: _returnDate == null ? null : _formatDate(_returnDate),
                hint: 'Drop-off date',
                onTap: () async {
                  final result = await custom.showCustomDatePicker(
                    context: context,
                    mode: custom.CustomDatePickerMode.singleDate,
                    initialStartDate: _returnDate,
                    minDate: _departureDate,
                  );
                  if (result['startDate'] != null) {
                    setState(() {
                      _returnDate = result['startDate'];
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to search results
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Build Things to do form (without Travelers field)
  Widget _buildThingsToDoForm() {
    return Column(
      children: [
        _buildLocationField(),
        const SizedBox(height: 12),
        _buildFormField(
          icon: Icons.calendar_today,
          label: 'Select dates',
          value: _formatDateRange(_departureDate, _returnDate).isEmpty 
              ? null 
              : _formatDateRange(_departureDate, _returnDate),
          hint: 'Select dates',
          onTap: () async {
            final result = await custom.showCustomDatePicker(
              context: context,
              mode: custom.CustomDatePickerMode.roundTrip,
              initialStartDate: _departureDate,
              initialEndDate: _returnDate,
            );
            if (result['startDate'] != null || result['endDate'] != null) {
              setState(() {
                _departureDate = result['startDate'];
                _returnDate = result['endDate'];
              });
            }
          },
        ),
        const SizedBox(height: 12),
        _buildPromptField(),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to search results
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPackagesForm() {
    return Column(
      children: [
        _buildFormField(
          icon: Icons.location_on,
          label: 'Going to',
          value: _packagesLocation.isEmpty ? null : _packagesLocation,
          hint: 'Going to',
          onTap: () {
            // TODO: Open location picker
          },
        ),
        const SizedBox(height: 12),
        _buildFormField(
          icon: Icons.calendar_today,
          label: 'Select dates',
          value: _formatDateRange(_departureDate, _returnDate).isEmpty 
              ? null 
              : _formatDateRange(_departureDate, _returnDate),
          hint: 'Select dates',
          onTap: () async {
            final result = await custom.showCustomDatePicker(
              context: context,
              mode: custom.CustomDatePickerMode.roundTrip,
              initialStartDate: _departureDate,
              initialEndDate: _returnDate,
            );
              if (result['startDate'] != null || result['endDate'] != null) {
                setState(() {
                  _departureDate = result['startDate'];
                  _returnDate = result['endDate'];
                });
              }
          },
        ),
        const SizedBox(height: 12),
        _buildFormField(
          icon: Icons.person,
          label: 'Travelers',
          value: '$_numTravelers traveler${_numTravelers > 1 ? 's' : ''}',
          hint: 'Travelers',
          onTap: () {
            _showTravelersDialog();
          },
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              // TODO: Navigate to search results
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Search',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormField({
    required IconData icon,
    required String label,
    String? value,
    required String hint,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E), // Slightly lighter than background for contrast
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.border.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
            Text(
                    label,
              style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ?? hint,
                    style: TextStyle(
                      fontSize: 15,
                      color: value != null ? AppColors.textPrimary : AppColors.textSecondary.withOpacity(0.6),
                      fontWeight: value != null ? FontWeight.w500 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      ),
    );
  }

  void _showTravelersDialog() {
    int tempAdults = _numTravelers;
    int tempChildren = _numChildren;
    int tempRooms = _numRooms;
    String tempCabinClass = _cabinClass;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Travelers',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Adults
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Adults',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            color: AppColors.textSecondary,
                            onPressed: tempAdults > 1
                                ? () {
                                    setState(() {
                                      tempAdults--;
                                    });
                                  }
                                : null,
                          ),
                          Text(
                            '$tempAdults',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            color: AppColors.primary,
                            onPressed: () {
                              setState(() {
                                tempAdults++;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Children (only for Stays)
                  if (_selectedTravelType == 'Stays') ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Children',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              color: AppColors.textSecondary,
                              onPressed: tempChildren > 0
                                  ? () {
                                      setState(() {
                                        tempChildren--;
                                      });
                                    }
                                  : null,
                            ),
                            Text(
                              '$tempChildren',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              color: AppColors.primary,
                              onPressed: () {
                                setState(() {
                                  tempChildren++;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    // Rooms (only for Stays)
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Rooms',
                          style: TextStyle(
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              color: AppColors.textSecondary,
                              onPressed: tempRooms > 1
                                  ? () {
                                      setState(() {
                                        tempRooms--;
                                      });
                                    }
                                  : null,
                            ),
                            Text(
                              '$tempRooms',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              color: AppColors.primary,
                              onPressed: () {
                                setState(() {
                                  tempRooms++;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  // Cabin class (only for Flights)
                  if (_selectedTravelType == 'Flights') ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Cabin class',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...['Economy', 'Premium Economy', 'Business', 'First'].map((classType) {
                      return RadioListTile<String>(
                        title: Text(classType),
                        value: classType,
                        groupValue: tempCabinClass,
                        onChanged: (value) {
                          setState(() {
                            tempCabinClass = value!;
                          });
                        },
                        activeColor: AppColors.primary,
                        contentPadding: EdgeInsets.zero,
                      );
                    }),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _numTravelers = tempAdults;
                          _numChildren = tempChildren;
                          _numRooms = tempRooms;
                          _cabinClass = tempCabinClass;
                          if (_selectedTravelType == 'Flights') {
                            _travelers = '$_numTravelers traveler${_numTravelers > 1 ? 's' : ''}, $_cabinClass';
                          }
                        });
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

