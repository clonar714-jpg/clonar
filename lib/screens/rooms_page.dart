// lib/screens/rooms_page.dart
import 'package:flutter/material.dart';
import '../models/room.dart';
import '../services/rooms_service.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../widgets/room_card.dart';
import 'package:intl/intl.dart';

/// 🏨 Rooms Listing Page (Perplexity-style)
/// 
/// Displays available rooms for a hotel with:
/// - Date/guest selector at top
/// - Scrollable list of room cards
/// - Each card shows images, price, amenities, and Reserve button
class RoomsPage extends StatefulWidget {
  final String hotelId;
  final String hotelName;
  final DateTime? initialCheckIn;
  final DateTime? initialCheckOut;
  final int initialGuests;

  const RoomsPage({
    Key? key,
    required this.hotelId,
    required this.hotelName,
    this.initialCheckIn,
    this.initialCheckOut,
    this.initialGuests = 2,
  }) : super(key: key);

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  bool _loading = true;
  String? _error;
  List<Room> _rooms = [];

  late DateTime _checkIn;
  late DateTime _checkOut;
  late int _guests;

  @override
  void initState() {
    super.initState();
    _checkIn = widget.initialCheckIn ?? DateTime.now();
    _checkOut = widget.initialCheckOut ?? _checkIn.add(const Duration(days: 1));
    _guests = widget.initialGuests;
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rooms = await RoomsService.fetchRooms(
        hotelId: widget.hotelId,
        checkIn: _formatDate(_checkIn),
        checkOut: _formatDate(_checkOut),
        guests: _guests,
      );

      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load rooms: $e';
        _loading = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _formatDisplayDate(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  Future<void> _showDatePicker() async {
    // TODO: Use CustomDatePicker when available
    // For now, show a simple date picker
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _checkIn,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _checkIn) {
      setState(() {
        _checkIn = picked;
        _checkOut = _checkIn.add(const Duration(days: 1));
      });
      _fetchRooms();
    }
  }

  void _showGuestSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _GuestSelectorBottomSheet(
        initialGuestCount: _guests,
        onGuestCountChanged: (count) {
          setState(() {
            _guests = count;
          });
          Navigator.pop(context);
          _fetchRooms();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Reserve',
          style: AppTypography.title1.copyWith(
            color: const Color(0xFF00D4AA), // Perplexity teal
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ✅ Date/Guest selector bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: _buildSelectorButton(
                    icon: Icons.calendar_today,
                    label: '${_formatDisplayDate(_checkIn)} - ${_formatDisplayDate(_checkOut)}',
                    onTap: _showDatePicker,
      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSelectorButton(
                    icon: Icons.person,
                    label: _guests == 1 ? '1 guest' : '$_guests guests',
                    onTap: _showGuestSelector,
                  ),
                ),
              ],
            ),
          ),

          // ✅ "powered by Selfbook" text (or your booking provider)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'powered by Selfbook',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),

          // ✅ Rooms list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
                              _error!,
                              style: AppTypography.body1.copyWith(
                                color: AppColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchRooms,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _rooms.isEmpty
                        ? Center(
                            child: Text(
                              'No rooms available',
                              style: AppTypography.body1.copyWith(
                                color: AppColors.textSecondary,
              ),
            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _rooms.length,
                            itemBuilder: (context, index) {
                              return RoomCard(
                                room: _rooms[index],
                                onReserve: () {
                                  // TODO: Navigate to booking screen
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Reserving ${_rooms[index].name}...'),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
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
}

// ✅ Guest selector bottom sheet (reused from HotelResultsScreen)
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Guests',
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Adults',
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ages 13+',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
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
                  Text(
                    '$_guestCount',
                    style: AppTypography.title2.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
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
                'Apply',
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

