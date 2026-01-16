import 'package:flutter/material.dart';
import 'dart:async';
import '../theme/AppColors.dart';

/// ✅ PERPLEXITY-STYLE: Research activity widget with animated steps
/// Self-animated (no provider watching), purely phase-driven
class ResearchActivityWidget extends StatefulWidget {
  final String query;

  const ResearchActivityWidget({
    Key? key,
    required this.query,
  }) : super(key: key);

  @override
  State<ResearchActivityWidget> createState() => _ResearchActivityWidgetState();
}

class _ResearchActivityWidgetState extends State<ResearchActivityWidget> {
  int _index = 0;
  Timer? _stepTimer;

  // ✅ PERPLEXITY-STYLE: Context-aware steps based on query
  List<String> get _steps {
    final queryLower = widget.query.toLowerCase();
    
    if (queryLower.contains('hotel') || queryLower.contains('hotels')) {
      return [
        "Analyzing hotels",
        "Checking availability",
        "Comparing prices across sources",
        "Ranking best options",
      ];
    } else if (queryLower.contains('product') || queryLower.contains('buy') || queryLower.contains('shop')) {
      return [
        "Analyzing products",
        "Searching retailers",
        "Comparing prices",
        "Ranking best deals",
      ];
    } else if (queryLower.contains('place') || queryLower.contains('restaurant')) {
      return [
        "Analyzing locations",
        "Checking reviews",
        "Comparing options",
        "Ranking best matches",
      ];
    } else {
      return [
        "Analyzing intent",
        "Searching sources",
        "Checking information",
        "Ranking best results",
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    debugPrint('🔍 ResearchActivityWidget INIT - query: ${widget.query}');
    _loopSteps();
  }

  void _loopSteps() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 850));
      if (mounted) {
        setState(() {
          _index = (_index + 1) % _steps.length;
        });
      }
    }
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🔍 ResearchActivityWidget BUILD - step: ${_steps[_index]}, index: $_index');
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: 1,
      child: Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.border.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SearchingHeader(),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOut,
                  )),
                  child: FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                );
              },
              child: Text(
                _steps[_index],
                key: ValueKey(_index),
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SubtleShimmer(),
          ],
        ),
      ),
    );
  }
}

/// ✅ PERPLEXITY-STYLE: Animated "Searching..." header with dots
class _SearchingHeader extends StatefulWidget {
  @override
  State<_SearchingHeader> createState() => _SearchingHeaderState();
}

class _SearchingHeaderState extends State<_SearchingHeader> {
  int _dots = 0;
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _animate();
  }

  void _animate() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _dots = (_dots + 1) % 4;
        });
      }
    }
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          "Searching${"." * _dots}",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// ✅ PERPLEXITY-STYLE: Very subtle shimmer (not flashy)
class _SubtleShimmer extends StatefulWidget {
  @override
  State<_SubtleShimmer> createState() => _SubtleShimmerState();
}

class _SubtleShimmerState extends State<_SubtleShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: AppColors.surfaceVariant.withOpacity(0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              AppColors.primary.withOpacity(0.25 + (_animation.value * 0.15)),
            ),
            value: null, // Indeterminate progress
          );
        },
      ),
    );
  }
}
