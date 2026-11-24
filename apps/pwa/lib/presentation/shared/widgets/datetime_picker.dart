import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:lynk_core/core.dart';

/// Available modes for [LynkWheelDatePicker].
enum LynkWheelPickerMode {
  /// Date only: Day, Month, Year wheels.
  date,

  /// Time only: Hour (1-12), Minute (00-59), Period (AM/PM).
  time,

  /// Date & Time: Date (e.g. 'Thu, Oct 24'), Hour (1-12), Minute (00-59), Period (AM/PM).
  dateAndTime,
}

/// An iOS-style drum wheel date & time picker bottom sheet built on Flutter's
/// native [ListWheelScrollView].
///
/// Supports dark-theme aesthetic, custom accent highlights, and smooth physics
/// with zero external Cupertino library dependencies.
class LynkWheelDatePicker extends StatefulWidget {
  final LynkWheelPickerMode mode;
  final DateTime initialDateTime;
  final DateTime? minimumDate;
  final DateTime? maximumDate;
  final String title;
  final ValueChanged<DateTime> onConfirmed;

  const LynkWheelDatePicker({
    super.key,
    required this.mode,
    required this.initialDateTime,
    this.minimumDate,
    this.maximumDate,
    required this.title,
    required this.onConfirmed,
  });

  /// Displays the wheel picker in a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required LynkWheelPickerMode mode,
    required DateTime initialDateTime,
    DateTime? minimumDate,
    DateTime? maximumDate,
    required String title,
    required ValueChanged<DateTime> onConfirmed,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => LynkWheelDatePicker(
        mode: mode,
        initialDateTime: initialDateTime,
        minimumDate: minimumDate,
        maximumDate: maximumDate,
        title: title,
        onConfirmed: onConfirmed,
      ),
    );
  }

  @override
  State<LynkWheelDatePicker> createState() => _LynkWheelDatePickerState();
}

class _LynkWheelDatePickerState extends State<LynkWheelDatePicker> {
  static const double _itemExtent = 42.0;

  late int _selectedYear;
  late int _selectedMonth; // 1-12
  late int _selectedDay; // 1-31
  late int _selectedHour; // 1-12
  late int _selectedMinute; // 0-59
  late bool _isPm; // true = PM, false = AM

  // For dateAndTime mode: list of consecutive days
  late final List<DateTime> _dateTimeDays;
  late int _selectedDayIndex;

  late final FixedExtentScrollController _yearController;
  late final FixedExtentScrollController _monthController;
  late final FixedExtentScrollController _dayController;
  late final FixedExtentScrollController _dateController;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late final FixedExtentScrollController _periodController;

  late final int _startYear;
  late final int _endYear;

  @override
  void initState() {
    super.initState();
    final clamped = _clampDateTime(widget.initialDateTime);

    _startYear = (widget.minimumDate?.year ?? 1900);
    _endYear = (widget.maximumDate?.year ?? 2100);

    _selectedYear = clamped.year;
    _selectedMonth = clamped.month;
    _selectedDay = clamped.day;

    final hour24 = clamped.hour;
    _isPm = hour24 >= 12;
    _selectedHour = hour24 % 12;
    if (_selectedHour == 0) _selectedHour = 12;
    _selectedMinute = clamped.minute;

    // Build days range for dateAndTime mode (-180 days to +180 days around initial, or bounded)
    final minD = widget.minimumDate ?? clamped.subtract(const Duration(days: 365));
    final maxD = widget.maximumDate ?? clamped.add(const Duration(days: 365));

    final cleanMin = DateTime(minD.year, minD.month, minD.day);
    final cleanMax = DateTime(maxD.year, maxD.month, maxD.day);
    final target = DateTime(clamped.year, clamped.month, clamped.day);

    final totalDays = cleanMax.difference(cleanMin).inDays + 1;
    _dateTimeDays = List.generate(
      totalDays > 0 ? totalDays : 1,
      (i) => cleanMin.add(Duration(days: i)),
    );

    final foundIdx = _dateTimeDays.indexWhere(
      (d) => d.year == target.year && d.month == target.month && d.day == target.day,
    );
    _selectedDayIndex = foundIdx >= 0 ? foundIdx : 0;

    // Controllers
    _yearController = FixedExtentScrollController(
      initialItem: (_selectedYear - _startYear).clamp(0, _endYear - _startYear),
    );
    _monthController = FixedExtentScrollController(initialItem: _selectedMonth - 1);
    _dayController = FixedExtentScrollController(initialItem: _selectedDay - 1);
    _dateController = FixedExtentScrollController(initialItem: _selectedDayIndex);
    _hourController = FixedExtentScrollController(initialItem: _selectedHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
    _periodController = FixedExtentScrollController(initialItem: _isPm ? 1 : 0);
  }

  @override
  void dispose() {
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    _dateController.dispose();
    _hourController.dispose();
    _minuteController.dispose();
    _periodController.dispose();
    super.dispose();
  }

  DateTime _clampDateTime(DateTime dt) {
    if (widget.minimumDate != null && dt.isBefore(widget.minimumDate!)) {
      return widget.minimumDate!;
    }
    if (widget.maximumDate != null && dt.isAfter(widget.maximumDate!)) {
      return widget.maximumDate!;
    }
    return dt;
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  DateTime _buildCurrentDateTime() {
    int year = _selectedYear;
    int month = _selectedMonth;
    int day = _selectedDay;

    if (widget.mode == LynkWheelPickerMode.dateAndTime) {
      if (_dateTimeDays.isNotEmpty && _selectedDayIndex < _dateTimeDays.length) {
        final d = _dateTimeDays[_selectedDayIndex];
        year = d.year;
        month = d.month;
        day = d.day;
      }
    }

    int hour = _selectedHour % 12;
    if (_isPm) hour += 12;

    final maxDays = _daysInMonth(year, month);
    final clampedDay = day.clamp(1, maxDays);

    final result = DateTime(year, month, clampedDay, hour, _selectedMinute);
    return _clampDateTime(result);
  }

  Widget _buildWheelItem(String text, {bool isSelected = false}) {
    return Center(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.inter(
          fontSize: 17,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? Colors.white : Colors.white38,
        ),
      ),
    );
  }

  Widget _buildWheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required Widget Function(int index, bool isSelected) builder,
    required ValueChanged<int> onSelectedItemChanged,
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _itemExtent,
        perspective: 0.003,
        diameterRatio: 1.3,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: onSelectedItemChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          builder: (context, index) {
            if (index < 0 || index >= itemCount) return null;
            final isSelected = controller.hasClients && controller.selectedItem == index;
            return builder(index, isSelected);
          },
          childCount: itemCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final months = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final maxDays = _daysInMonth(_selectedYear, _selectedMonth);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Cancel / Title / Done
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.tertiary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                bottom: BorderSide(color: Colors.white12, width: 0.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTypography.inter(
                      fontSize: 15,
                      color: Colors.white54,
                    ),
                  ),
                ),
                Text(
                  widget.title,
                  style: AppTypography.interTight(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    widget.onConfirmed(_buildCurrentDateTime());
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Done',
                    style: AppTypography.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Wheels Container with Selection Overlay
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Highlight Bar in Center
                IgnorePointer(
                  child: Container(
                    height: _itemExtent,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),

                // Wheels Content based on Mode
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      // Date Mode (Month, Day, Year)
                      if (widget.mode == LynkWheelPickerMode.date) ...[
                        _buildWheel(
                          controller: _monthController,
                          itemCount: 12,
                          flex: 3,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedMonth = index + 1;
                              final newMaxDays = _daysInMonth(_selectedYear, _selectedMonth);
                              if (_selectedDay > newMaxDays) {
                                _selectedDay = newMaxDays;
                                _dayController.jumpToItem(_selectedDay - 1);
                              }
                            });
                          },
                          builder: (index, isSelected) =>
                              _buildWheelItem(months[index], isSelected: isSelected),
                        ),
                        _buildWheel(
                          controller: _dayController,
                          itemCount: maxDays,
                          flex: 2,
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedDay = index + 1);
                          },
                          builder: (index, isSelected) =>
                              _buildWheelItem('${index + 1}', isSelected: isSelected),
                        ),
                        _buildWheel(
                          controller: _yearController,
                          itemCount: _endYear - _startYear + 1,
                          flex: 3,
                          onSelectedItemChanged: (index) {
                            setState(() {
                              _selectedYear = _startYear + index;
                              final newMaxDays = _daysInMonth(_selectedYear, _selectedMonth);
                              if (_selectedDay > newMaxDays) {
                                _selectedDay = newMaxDays;
                                _dayController.jumpToItem(_selectedDay - 1);
                              }
                            });
                          },
                          builder: (index, isSelected) =>
                              _buildWheelItem('${_startYear + index}', isSelected: isSelected),
                        ),
                      ],

                      // Date & Time Mode (Combined Date wheel, Hour, Minute, AM/PM)
                      if (widget.mode == LynkWheelPickerMode.dateAndTime) ...[
                        _buildWheel(
                          controller: _dateController,
                          itemCount: _dateTimeDays.length,
                          flex: 5,
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedDayIndex = index);
                          },
                          builder: (index, isSelected) {
                            final d = _dateTimeDays[index];
                            final label = DateFormat('EEE, MMM d').format(d);
                            return _buildWheelItem(label, isSelected: isSelected);
                          },
                        ),
                        _buildWheel(
                          controller: _hourController,
                          itemCount: 12,
                          flex: 2,
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedHour = index + 1);
                          },
                          builder: (index, isSelected) =>
                              _buildWheelItem('${index + 1}', isSelected: isSelected),
                        ),
                        const Text(
                          ':',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        _buildWheel(
                          controller: _minuteController,
                          itemCount: 60,
                          flex: 2,
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedMinute = index);
                          },
                          builder: (index, isSelected) => _buildWheelItem(
                            index.toString().padLeft(2, '0'),
                            isSelected: isSelected,
                          ),
                        ),
                        _buildWheel(
                          controller: _periodController,
                          itemCount: 2,
                          flex: 3,
                          onSelectedItemChanged: (index) {
                            setState(() => _isPm = index == 1);
                          },
                          builder: (index, isSelected) => _buildWheelItem(
                            index == 0 ? 'AM' : 'PM',
                            isSelected: isSelected,
                          ),
                        ),
                      ],

                      // Time Mode (Hour, Minute, AM/PM)
                      if (widget.mode == LynkWheelPickerMode.time) ...[
                        _buildWheel(
                          controller: _hourController,
                          itemCount: 12,
                          flex: 3,
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedHour = index + 1);
                          },
                          builder: (index, isSelected) =>
                              _buildWheelItem('${index + 1}', isSelected: isSelected),
                        ),
                        const Text(
                          ':',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                        _buildWheel(
                          controller: _minuteController,
                          itemCount: 60,
                          flex: 3,
                          onSelectedItemChanged: (index) {
                            setState(() => _selectedMinute = index);
                          },
                          builder: (index, isSelected) => _buildWheelItem(
                            index.toString().padLeft(2, '0'),
                            isSelected: isSelected,
                          ),
                        ),
                        _buildWheel(
                          controller: _periodController,
                          itemCount: 2,
                          flex: 3,
                          onSelectedItemChanged: (index) {
                            setState(() => _isPm = index == 1);
                          },
                          builder: (index, isSelected) => _buildWheelItem(
                            index == 0 ? 'AM' : 'PM',
                            isSelected: isSelected,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
