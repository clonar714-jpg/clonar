import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../widgets/CustomDatePicker.dart' as custom show CustomDatePickerMode, showCustomDatePicker;

class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key});

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  String _selectedTravelType = 'Flights'; // Flights, Stays, Cruise, Packages
  String _selectedFlightType = 'Roundtrip'; // Roundtrip, One-way, Multi-city
  String _fromLocation = '';
  String _toLocation = '';
  DateTime? _departureDate;
  DateTime? _returnDate;
  String _travelers = '1 traveler, Economy';
  int _numTravelers = 1;
  String _cabinClass = 'Economy';
  
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Booking Form
                    _buildBookingForm(),
                    
                    const SizedBox(height: 20),
                    
                    // Promotional Banner
                    _buildPromotionalBanner(),
                    
                    const SizedBox(height: 20),
                  ],
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
          
          // Account Info (matching Expedia style)
          Row(
            children: [
              Text(
                '\$0.00 in OneKeyCash',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star,
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Blue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
      ),
                  ],
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
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTravelType == tabs[index];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTravelType = tabs[index];
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 20),
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
        },
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
        // Leaving from
        _buildFormField(
          icon: Icons.location_on,
          label: 'Leaving from',
          value: _fromLocation.isEmpty ? null : _fromLocation,
          hint: 'Leaving from',
          onTap: () {
            // TODO: Open location picker
          },
          trailing: GestureDetector(
            onTap: () {
              setState(() {
                final temp = _fromLocation;
                _fromLocation = _toLocation;
                _toLocation = temp;
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
          value: _toLocation.isEmpty ? null : _toLocation,
          hint: 'Going to',
          onTap: () {
            // TODO: Open location picker
          },
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
              if (result != null) {
                if (result['startDate'] != null || result['endDate'] != null) {
                  setState(() {
                    _departureDate = result['startDate'];
                    _returnDate = result['endDate'];
                  });
                }
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
                mode: custom.CustomDatePickerMode.single,
                initialStartDate: _departureDate,
              );
              if (result != null && result['startDate'] != null) {
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
              print('Search flights: $_fromLocation to $_toLocation');
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
                    mode: custom.CustomDatePickerMode.single,
                    initialStartDate: _multiCityFlights[index]['date'] as DateTime?,
                  );
                  if (result != null && result['startDate'] != null) {
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
        _buildFormField(
          icon: Icons.location_on,
          label: 'Going to',
          value: _toLocation.isEmpty ? null : _toLocation,
          hint: 'Going to',
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
                label: 'Check-in',
                value: _departureDate == null ? null : _formatDate(_departureDate),
                hint: 'Check-in',
                onTap: () async {
                  final result = await custom.showCustomDatePicker(
                    context: context,
                    mode: custom.CustomDatePickerMode.single,
                    initialStartDate: _departureDate,
                  );
              if (result != null && result['startDate'] != null) {
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
                label: 'Check-out',
                value: _returnDate == null ? null : _formatDate(_returnDate),
                hint: 'Check-out',
                onTap: () async {
                  final result = await custom.showCustomDatePicker(
                    context: context,
                    mode: custom.CustomDatePickerMode.single,
                    initialStartDate: _returnDate,
                    minDate: _departureDate,
                  );
                  if (result != null && result['startDate'] != null) {
                    setState(() {
                      _returnDate = result['startDate'];
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildFormField(
          icon: Icons.person,
          label: 'Travelers',
          value: '$_numTravelers traveler${_numTravelers > 1 ? 's' : ''}, 1 room',
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

  Widget _buildCruiseForm() {
    return Column(
      children: [
        _buildFormField(
          icon: Icons.location_on,
          label: 'Pick-up location',
          value: _fromLocation.isEmpty ? null : _fromLocation,
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
                    mode: custom.CustomDatePickerMode.single,
                    initialStartDate: _departureDate,
                  );
              if (result != null && result['startDate'] != null) {
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
                    mode: custom.CustomDatePickerMode.single,
                    initialStartDate: _returnDate,
                    minDate: _departureDate,
                  );
                  if (result != null && result['startDate'] != null) {
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

  Widget _buildPackagesForm() {
    return Column(
      children: [
        _buildFormField(
          icon: Icons.location_on,
          label: 'Going to',
          value: _toLocation.isEmpty ? null : _toLocation,
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
            if (result != null) {
              if (result['startDate'] != null || result['endDate'] != null) {
                setState(() {
                  _departureDate = result['startDate'];
                  _returnDate = result['endDate'];
                });
              }
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

  Widget _buildPromotionalBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E), // Dark blue like Expedia
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_offer,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Black Friday sale: Save up to 50%',
                  style: TextStyle(
                    fontSize: 13,
                fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
              ),
            ),
                const SizedBox(height: 2),
            Text(
                  'Save on eligible hotels, plus find deals on flights and more.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withOpacity(0.9),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () {
                    // TODO: Handle book now
                  },
                  child: const Text(
                    'Book now',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary,
                    ),
                  ),
            ),
          ],
        ),
      ),
          const SizedBox(width: 8),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: AppColors.primary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  void _showTravelersDialog() {
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
                            onPressed: _numTravelers > 1
                                ? () {
                                    setState(() {
                                      _numTravelers--;
                                    });
                                  }
                                : null,
                          ),
                          Text(
                            '$_numTravelers',
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
                                _numTravelers++;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
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
                        groupValue: _cabinClass,
                        onChanged: (value) {
                          setState(() {
                            _cabinClass = value!;
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

