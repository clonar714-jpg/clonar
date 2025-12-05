import 'package:flutter/material.dart' hide DatePickerMode;
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../services/AgentService.dart';
import '../widgets/HotelCardPerplexity.dart';
import '../widgets/CustomDatePicker.dart' show CustomDatePickerMode, showCustomDatePicker;
import 'HotelDetailScreen.dart';
import '../widgets/HotelMapView.dart';
import 'FullScreenMapScreen.dart';

class HotelResultsScreen extends StatefulWidget {
  final String query;
  final DateTime? checkInDate;
  final DateTime? checkOutDate;
  final int? guestCount;
  final int? roomCount;
  final bool fromTravelScreen; // Flag to indicate if coming from TravelScreen

  const HotelResultsScreen({
    Key? key, 
    required this.query,
    this.checkInDate,
    this.checkOutDate,
    this.guestCount,
    this.roomCount,
    this.fromTravelScreen = false,
  }) : super(key: key);

  @override
  State<HotelResultsScreen> createState() => _HotelResultsScreenState();
}

class _HotelResultsScreenState extends State<HotelResultsScreen> {
  bool _loading = true;
  String? _error;

  List<dynamic> _sections = [];
  List<dynamic>? _mapPoints; // Map points from API response
  String? _summary; // Summary text from API
  
  // ✅ Date and guest selection state
  late DateTime? _checkInDate;
  late DateTime? _checkOutDate;
  late int _guestCount;
  int? _roomCount;
  
  // ✅ View mode: 'map' or 'list' - default to 'map' if coming from TravelScreen
  String _viewMode = 'list';
  
  // ✅ Scroll controller for swipe-down-to-dismiss
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Initialize with values from TravelScreen if provided, otherwise use defaults
    _checkInDate = widget.checkInDate;
    _checkOutDate = widget.checkOutDate;
    _guestCount = widget.guestCount ?? 2;
    _roomCount = widget.roomCount;
    // Default to 'map' view if coming from TravelScreen
    _viewMode = widget.fromTravelScreen ? 'map' : 'list';
    _fetchHotels();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ✅ Handle scroll to detect swipe-down-to-dismiss at top
  void _onScroll() {
    // Scroll position tracking for swipe-down-to-dismiss
    // The actual dismiss is handled by NotificationListener
  }

  Future<void> _fetchHotels() async {
    try {
      setState(() => _loading = true);

      final res = await AgentService.askAgent(widget.query);

      setState(() {
        _sections = res["sections"] ?? [];
        _mapPoints = res["map"] as List<dynamic>?; // Extract map points if available
        _summary = res["summary"] as String?; // Extract summary if available
        _loading = false;
        });
    } catch (e) {
      setState(() {
        _error = "Failed to load hotels: $e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            // Show back arrow in map view when from TravelScreen, otherwise show X
            widget.fromTravelScreen && _viewMode == 'map' 
              ? Icons.arrow_back 
              : Icons.close, 
            color: Colors.white,
          ),
          onPressed: _closeScreen,
        ),
        title: Text("Hotels", style: AppTypography.title1),
        actions: [
          // View toggle buttons (map/list) - only show if map data is available
          if (_mapPoints != null && _mapPoints!.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewToggleButton('map', Icons.map, _viewMode == 'map'),
                const SizedBox(width: 8),
                _buildViewToggleButton('list', Icons.list, _viewMode == 'list'),
                const SizedBox(width: 8),
              ],
            ),
        ],
      ),
      body: GestureDetector(
        // ✅ Swipe down to dismiss (same as X button)
        // Only works when at the top of the list
        onVerticalDragEnd: (details) {
          // If user swipes down with sufficient velocity and at top, close the screen
          if (details.primaryVelocity != null && 
              details.primaryVelocity! > 300 &&
              _scrollController.hasClients &&
              _scrollController.position.pixels <= 0) {
            _closeScreen();
          }
        },
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  // ✅ Close screen function (used by both X button and swipe down)
  void _closeScreen() {
    // If coming from TravelScreen and in map view, go back to TravelScreen
    // Otherwise, just pop normally
    Navigator.pop(context);
  }

  // ✅ Build view toggle button
  Widget _buildViewToggleButton(String mode, IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 20,
          color: isSelected ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Text(
                        _error!,
        style: AppTypography.body1.copyWith(color: AppColors.textSecondary),
                        textAlign: TextAlign.center,
                      ),
    );
  }

  Widget _buildContent() {
    // ✅ Collect all hotels from all sections into a single list
    final List<dynamic> allHotels = [];
    for (final section in _sections) {
      final items = section["items"] ?? [];
      if (items is List) {
        allHotels.addAll(items);
      }
    }

    // Show map view or list view based on _viewMode
    if (_viewMode == 'map' && _mapPoints != null && _mapPoints!.isNotEmpty) {
      return _buildMapView(allHotels);
    } else {
      return _buildListView(allHotels);
    }
  }

  // ✅ Build map view (like ShoppingResultsScreen - map first, then description, then list)
  Widget _buildMapView(List<dynamic> allHotels) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ STEP 1: Map FIRST (like ShoppingResultsScreen)
          if (_mapPoints != null && _mapPoints!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapScreen(
                        points: _mapPoints!,
                        title: widget.query,
                      ),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    HotelMapView(
                      points: _mapPoints!,
                      height: MediaQuery.of(context).size.height * 0.65,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullScreenMapScreen(
                              points: _mapPoints!,
                              title: widget.query,
                            ),
                          ),
                        );
                      },
                    ),
                    // Visual indicator at bottom
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surface.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fullscreen, color: AppColors.textPrimary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Tap to view full screen',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
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
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ✅ STEP 2: Date/Guest selector buttons (after map)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildSelectorButton(
                    icon: Icons.calendar_today,
                    label: _getDateLabel(),
                    onTap: _showDatePicker,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSelectorButton(
                    icon: Icons.person,
                    label: _getGuestLabel(),
                    onTap: _showGuestSelector,
                  ),
                ),
              ],
            ),
          ),

          // ✅ STEP 3: Description text (if available)
          if (_summary != null && _summary!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _summary!,
                style: AppTypography.body1.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ✅ STEP 4: Hotel list (below map and description)
          if (allHotels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...allHotels.asMap().entries.map((entry) {
                    final index = entry.key;
                    final hotel = entry.value;
                    final isLast = index == allHotels.length - 1;
                    return Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HotelDetailScreen(
                                  hotel: Map<String, dynamic>.from(hotel),
                                  checkInDate: _checkInDate,
                                  checkOutDate: _checkOutDate,
                                  guestCount: _guestCount,
                                  roomCount: _roomCount,
                                ),
                              ),
                            );
                          },
                          child: HotelCardPerplexity(hotel: Map<String, dynamic>.from(hotel)),
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.white.withOpacity(0.1),
                          ),
                        if (!isLast) const SizedBox(height: 20),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  "No hotels found",
                  style: AppTypography.body1.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ✅ Build list view (original list-only view)
  Widget _buildListView(List<dynamic> allHotels) {
    return Column(
      children: [
        // ✅ Date/Guest selector buttons at the top
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: _buildSelectorButton(
                  icon: Icons.calendar_today,
                  label: _getDateLabel(),
                  onTap: _showDatePicker,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSelectorButton(
                  icon: Icons.person,
                  label: _getGuestLabel(),
                  onTap: _showGuestSelector,
                ),
              ),
            ],
          ),
        ),
        
        // ✅ Scrollable list of hotel cards (vertical, not horizontal)
        Expanded(
          child: allHotels.isEmpty
                  ? Center(
                  child: Text(
                    "No hotels found",
                    style: AppTypography.body1.copyWith(color: AppColors.textSecondary),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: allHotels.length,
                  itemBuilder: (context, index) {
                    final hotel = allHotels[index];
                    final isLast = index == allHotels.length - 1;
                    return Column(
                        children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => HotelDetailScreen(
                                  hotel: Map<String, dynamic>.from(hotel),
                                  checkInDate: _checkInDate,
                                  checkOutDate: _checkOutDate,
                                  guestCount: _guestCount,
                                  roomCount: _roomCount,
                                ),
                              ),
                            );
                          },
                          child: HotelCardPerplexity(hotel: Map<String, dynamic>.from(hotel)),
                        ),
                        // ✅ White horizontal divider after each hotel (except last)
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.white.withOpacity(0.1),
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ✅ Date/Guest selector button widget
  Widget _buildSelectorButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                            style: AppTypography.body1.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  // ✅ Get date label for button
  String _getDateLabel() {
    if (_checkInDate != null && _checkOutDate != null) {
      final checkIn = _formatDate(_checkInDate!);
      final checkOut = _formatDate(_checkOutDate!);
      return "$checkIn - $checkOut";
    } else if (_checkInDate != null) {
      return _formatDate(_checkInDate!);
    }
    return "Select dates";
  }

  // ✅ Format date as "MMM d" (e.g., "Jan 15")
  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}';
    }

  // ✅ Get guest label for button
  String _getGuestLabel() {
    if (_guestCount == 1) {
      return "1 guest";
    }
    if (_roomCount != null && _roomCount! > 1) {
      return "$_guestCount guests, $_roomCount rooms";
    }
    return "$_guestCount guests";
  }

  // ✅ Show date picker dialog
  Future<void> _showDatePicker() async {
    final result = await showCustomDatePicker(
      context: context,
      mode: CustomDatePickerMode.roundTrip,
      initialStartDate: _checkInDate,
      initialEndDate: _checkOutDate,
      minDate: DateTime.now(),
    );

    if (result['startDate'] != null && result['endDate'] != null) {
      setState(() {
        _checkInDate = result['startDate'] as DateTime;
        _checkOutDate = result['endDate'] as DateTime;
      });
    }
    }

  // ✅ Show guest selector bottom sheet
  void _showGuestSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _GuestSelectorBottomSheet(
        initialGuestCount: _guestCount,
        onGuestCountChanged: (count) {
          setState(() {
            _guestCount = count;
          });
          Navigator.pop(context);
        },
      ),
    );
          }
        }

// ✅ Guest selector bottom sheet widget
class _GuestSelectorBottomSheet extends StatefulWidget {
  final int initialGuestCount;
  final Function(int) onGuestCountChanged;

  const _GuestSelectorBottomSheet({
    required this.initialGuestCount,
    required this.onGuestCountChanged,
  });

  @override
  State<_GuestSelectorBottomSheet> createState() => _GuestSelectorBottomSheetState();
}

class _GuestSelectorBottomSheetState extends State<_GuestSelectorBottomSheet> {
  late int _guestCount;

  @override
  void initState() {
    super.initState();
    _guestCount = widget.initialGuestCount;
  }

  void _increment() {
    setState(() {
      if (_guestCount < 20) {
        _guestCount++;
      }
    });
  }

  void _decrement() {
    setState(() {
      if (_guestCount > 1) {
        _guestCount--;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
        child: Column(
        mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Guests",
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                ),
                ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
          const SizedBox(height: 24),
            
          // Guest count selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Adults",
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Ages 13+",
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
                  Row(
                    children: [
                  // Decrement button
                  Container(
                    decoration: BoxDecoration(
                      color: _guestCount > 1 
                          ? AppColors.primary.withOpacity(0.1)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _guestCount > 1 
                            ? AppColors.primary
                            : AppColors.border,
                        width: 1,
                          ),
                        ),
                    child: IconButton(
                      icon: Icon(
                        Icons.remove,
                        color: _guestCount > 1 
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: _guestCount > 1 ? _decrement : null,
                          ),
                        ),
                  const SizedBox(width: 16),
                  // Count display
                        Text(
                    "$_guestCount",
                    style: AppTypography.title2.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                          ),
                        ),
                  const SizedBox(width: 16),
                  // Increment button
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary,
                        width: 1,
                      ),
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.add,
                        color: AppColors.primary,
                        size: 20,
                              ),
                      onPressed: _guestCount < 20 ? _increment : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
          const SizedBox(height: 32),
          
          // Apply button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                widget.onGuestCountChanged(_guestCount);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                "Apply",
                style: AppTypography.body1.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
