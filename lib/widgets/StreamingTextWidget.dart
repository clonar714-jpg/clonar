import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';

/// ✅ PRODUCTION-GRADE: Isolated streaming text widget
/// Prevents parent rebuilds by using internal animation state
/// Similar to ChatGPT/Perplexity/Cursor - smooth, word-by-word streaming
/// 
/// To disable animation entirely, set enableAnimation: false
/// This will show text immediately without any animation
class StreamingTextWidget extends StatefulWidget {
  final String targetText;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool enableAnimation;

  const StreamingTextWidget({
    Key? key,
    required this.targetText,
    this.style,
    this.textAlign,
    this.enableAnimation = false, // ✅ PRODUCTION: Disabled by default to prevent performance issues
  }) : super(key: key);

  @override
  State<StreamingTextWidget> createState() => _StreamingTextWidgetState();
}

class _StreamingTextWidgetState extends State<StreamingTextWidget> {
  String _displayedText = '';
  Timer? _animationTimer;
  int _currentIndex = 0;
  bool _isAnimating = false;

  // ✅ PRODUCTION: Optimized timing for smooth ChatGPT/Perplexity-style animation
  static const Duration _updateInterval = Duration(milliseconds: 20); // Very smooth 20ms updates
  static const int _minCharsPerUpdate = 2; // Minimum chars for smooth flow
  static const int _maxCharsPerUpdate = 5; // Maximum chars to prevent jumps

  @override
  void initState() {
    super.initState();
    if (widget.enableAnimation && widget.targetText.isNotEmpty) {
      _startAnimation();
    } else {
      _displayedText = widget.targetText;
    }
  }

  @override
  void didUpdateWidget(StreamingTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetText != oldWidget.targetText) {
      _animationTimer?.cancel();
      _currentIndex = 0;
      _isAnimating = false;
      if (widget.enableAnimation && widget.targetText.isNotEmpty) {
        _startAnimation();
      } else {
        setState(() {
          _displayedText = widget.targetText;
        });
      }
    }
  }

  void _startAnimation() {
    if (_isAnimating) return;
    _isAnimating = true;
    _displayedText = '';
    _currentIndex = 0;
    _performUpdate();
  }

  void _performUpdate() {
    if (!mounted || !_isAnimating) return;

    if (_currentIndex >= widget.targetText.length) {
      // Animation complete
      if (_displayedText != widget.targetText) {
        setState(() {
          _displayedText = widget.targetText;
        });
      }
      _isAnimating = false;
      _animationTimer?.cancel();
      return;
    }

    // ✅ PRODUCTION: Smart word-boundary detection for natural flow
    int nextIndex = _findNextUpdateIndex();
    _currentIndex = nextIndex;
    
    final newText = widget.targetText.substring(0, _currentIndex);
    if (newText != _displayedText) {
      setState(() {
        _displayedText = newText;
      });
    }

    // Schedule next update on next frame (prevents blocking UI thread)
    _animationTimer?.cancel();
    _animationTimer = Timer(_updateInterval, () {
      if (mounted && _isAnimating) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isAnimating) {
            _performUpdate();
          }
        });
      }
    });
  }

  /// ✅ PRODUCTION: Find next update index using word boundaries for natural flow
  int _findNextUpdateIndex() {
    if (_currentIndex >= widget.targetText.length) {
      return widget.targetText.length;
    }

    // Try to find next word boundary (space, punctuation, or newline)
    int searchStart = _currentIndex;
    int maxSearch = searchStart + _maxCharsPerUpdate;
    
    // Look for word boundaries for natural pauses
    for (int i = searchStart; i < maxSearch && i < widget.targetText.length; i++) {
      final char = widget.targetText[i];
      
      // Word boundaries: space, newline, punctuation
      if (char == ' ' || char == '\n' || char == '\t' ||
          char == '.' || char == ',' || char == '!' || char == '?' ||
          char == ';' || char == ':') {
        return i + 1; // Include the boundary character
      }
    }
    
    // If no boundary found, advance by minimum chars (smooth continuous flow)
    final minAdvance = searchStart + _minCharsPerUpdate;
    if (minAdvance < widget.targetText.length) {
      return minAdvance;
    }
    
    // Last chunk - return full length
    return widget.targetText.length;
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}

