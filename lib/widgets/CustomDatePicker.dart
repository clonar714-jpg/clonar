import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import '../theme/AppColors.dart';

enum CustomDatePickerMode {
  roundTrip,
  oneWay,
  multiCity,
  singleDate, // For hotels, cars, etc.
}

class CustomDatePicker extends StatefulWidget {
  final CustomDatePickerMode mode;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final DateTime? minDate;
  final DateTime? maxDate;
  final Function(DateTime? startDate, DateTime? endDate)? onDateSelected;

  const CustomDatePicker({
    super.key,
    required this.mode,
    this.initialStartDate,
    this.initialEndDate,
    this.minDate,
    this.maxDate,
    this.onDateSelected,
  });

  @override
  State<CustomDatePicker> createState() => _CustomDatePickerState();
}

class _CustomDatePickerState extends State<CustomDatePicker> {
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  DateTime? _tempStartDate;
  DateTime? _tempEndDate;

  @override
  void initState() {
    super.initState();
    _selectedStartDate = widget.initialStartDate;
    _selectedEndDate = widget.initialEndDate;
    _tempStartDate = widget.initialStartDate;
    _tempEndDate = widget.initialEndDate;
  }

  void _onSelectionChanged(DateRangePickerSelectionChangedArgs args) {
    if (widget.mode == CustomDatePickerMode.oneWay || widget.mode == CustomDatePickerMode.singleDate) {
      // Single date selection
      if (args.value is DateTime) {
        setState(() {
          _tempStartDate = args.value as DateTime;
          _tempEndDate = null;
        });
      }
    } else if (widget.mode == CustomDatePickerMode.roundTrip) {
      // Range selection
      if (args.value is PickerDateRange) {
        final range = args.value as PickerDateRange;
        setState(() {
          _tempStartDate = range.startDate;
          _tempEndDate = range.endDate;
        });
      } else if (args.value is DateTime) {
        // First date selected
        setState(() {
          _tempStartDate = args.value as DateTime;
          _tempEndDate = null;
        });
      }
    } else if (widget.mode == CustomDatePickerMode.multiCity) {
      // Single date for multi-city
      if (args.value is DateTime) {
        setState(() {
          _tempStartDate = args.value as DateTime;
          _tempEndDate = null;
        });
      }
    }
  }

  void _confirmSelection() {
    setState(() {
      _selectedStartDate = _tempStartDate;
      _selectedEndDate = _tempEndDate;
    });
    
    if (widget.onDateSelected != null) {
      widget.onDateSelected!(_selectedStartDate, _selectedEndDate);
    }
    
    Navigator.pop(context);
}

  void _clearSelection() {
    setState(() {
      _tempStartDate = null;
      _tempEndDate = null;
    });
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }


  @override
  Widget build(BuildContext context) {
    final isRangeMode = widget.mode == CustomDatePickerMode.roundTrip;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getTitle(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Row(
                    children: [
                      if (_tempStartDate != null || _tempEndDate != null)
                        TextButton(
                          onPressed: _clearSelection,
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textSecondary,
                          size: 24,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Selected dates preview
            if (_tempStartDate != null || _tempEndDate != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                color: AppColors.surfaceVariant.withOpacity(0.3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_tempStartDate != null)
                      Text(
                        _formatDate(_tempStartDate),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (_tempStartDate != null && _tempEndDate != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (_tempEndDate != null)
                      Text(
                        _formatDate(_tempEndDate),
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            
            // Calendar
            Container(
              padding: const EdgeInsets.all(16),
              child: SfDateRangePicker(
                view: DateRangePickerView.month,
                selectionMode: isRangeMode 
                    ? DateRangePickerSelectionMode.range
                    : DateRangePickerSelectionMode.single,
                initialSelectedDate: _selectedStartDate,
                initialSelectedRange: isRangeMode && _selectedStartDate != null && _selectedEndDate != null
                    ? PickerDateRange(_selectedStartDate, _selectedEndDate)
                    : null,
                minDate: widget.minDate ?? DateTime.now(),
                maxDate: widget.maxDate ?? DateTime.now().add(const Duration(days: 365 * 2)),
                onSelectionChanged: _onSelectionChanged,
                monthViewSettings: DateRangePickerMonthViewSettings(
                  firstDayOfWeek: 1, // Monday
                  viewHeaderStyle: DateRangePickerViewHeaderStyle(
                    textStyle: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                headerStyle: DateRangePickerHeaderStyle(
                  textStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.transparent,
                ),
                selectionTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                selectionColor: AppColors.primary,
                rangeSelectionColor: AppColors.primary.withOpacity(0.3),
                startRangeSelectionColor: AppColors.primary,
                endRangeSelectionColor: AppColors.primary,
                rangeTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                todayHighlightColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                headerHeight: 60,
                monthCellStyle: DateRangePickerMonthCellStyle(
                  textStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  disabledDatesTextStyle: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.3),
                    fontSize: 14,
                  ),
                  todayTextStyle: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  blackoutDateTextStyle: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.3),
                    fontSize: 14,
                  ),
                ),
                yearCellStyle: DateRangePickerYearCellStyle(
                  textStyle: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  disabledDatesTextStyle: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.3),
                    fontSize: 14,
                  ),
                  todayTextStyle: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppColors.border.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.border),
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: (_tempStartDate != null && 
                                  (isRangeMode ? _tempEndDate != null : true))
                          ? _confirmSelection
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.surfaceVariant,
                        disabledForegroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTitle() {
    switch (widget.mode) {
      case CustomDatePickerMode.roundTrip:
        return 'Select dates';
      case CustomDatePickerMode.oneWay:
        return 'Select departure date';
      case CustomDatePickerMode.multiCity:
        return 'Select departure date';
      case CustomDatePickerMode.singleDate:
        return 'Select date';
    }
  }
}

// Helper function to show date picker
Future<Map<String, DateTime?>> showCustomDatePicker({
  required BuildContext context,
  required CustomDatePickerMode mode,
  DateTime? initialStartDate,
  DateTime? initialEndDate,
  DateTime? minDate,
  DateTime? maxDate,
}) async {
  DateTime? selectedStartDate;
  DateTime? selectedEndDate;

  await showDialog(
    context: context,
    builder: (context) => CustomDatePicker(
      mode: mode,
      initialStartDate: initialStartDate,
      initialEndDate: initialEndDate,
      minDate: minDate,
      maxDate: maxDate,
      onDateSelected: (startDate, endDate) {
        selectedStartDate = startDate;
        selectedEndDate = endDate;
      },
    ),
  );

  return {
    'startDate': selectedStartDate,
    'endDate': selectedEndDate,
  };
}

