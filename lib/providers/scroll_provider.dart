import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

/// ✅ PHASE 7: Scroll event type
enum ScrollEvent {
  scrollToBottom,
  scrollToTop,
  scrollToIndex,
}

/// ✅ PHASE 7 + PHASE 10: Scroll provider - handles scroll commands with throttling and cooldown
class ScrollNotifier extends StateNotifier<ScrollEvent?> {
  Timer? _throttleTimer;
  Timer? _cooldownTimer;
  ScrollEvent? _pendingEvent;
  DateTime? _lastScrollTime;
  bool _isInCooldown = false;
  final List<ScrollEvent> _pendingEvents = []; // ✅ PHASE 10: Merge multiple events
  
  ScrollNotifier() : super(null);

  /// ✅ PHASE 10: Request scroll to bottom (with 300ms cooldown and event merging)
  void scrollToBottom() {
    _scheduleScroll(ScrollEvent.scrollToBottom);
  }

  /// Request scroll to top (throttled)
  void scrollToTop() {
    _scheduleScroll(ScrollEvent.scrollToTop);
  }

  /// Request scroll to specific index (throttled)
  void scrollToIndex() {
    _scheduleScroll(ScrollEvent.scrollToIndex);
  }

  /// ✅ PHASE 10: Schedule scroll event with throttling, cooldown, and event merging
  void _scheduleScroll(ScrollEvent event) {
    // ✅ PHASE 10: Prevent scrollToBottom() from firing more than once per frame
    if (event == ScrollEvent.scrollToBottom && _isInCooldown) {
      // Add to pending events for merging
      if (!_pendingEvents.contains(event)) {
        _pendingEvents.add(event);
      }
      return;
    }
    
    // ✅ PHASE 10: Check cooldown (300ms between scroll events)
    final now = DateTime.now();
    if (_lastScrollTime != null) {
      final timeSinceLastScroll = now.difference(_lastScrollTime!);
      if (timeSinceLastScroll.inMilliseconds < 300) {
        // In cooldown, add to pending events
        if (!_pendingEvents.contains(event)) {
          _pendingEvents.add(event);
        }
        return;
      }
    }
    
    _pendingEvent = event;
    _lastScrollTime = now;
    _isInCooldown = true;
    
    // Cancel existing timers
    _throttleTimer?.cancel();
    _cooldownTimer?.cancel();
    
    // ✅ PHASE 10: Merge pending events (take the most important one)
    if (_pendingEvents.isNotEmpty) {
      _pendingEvents.clear();
    }
    
    // Schedule new scroll after throttle delay
    _throttleTimer = Timer(const Duration(milliseconds: 100), () {
      if (_pendingEvent != null) {
        state = _pendingEvent;
        _pendingEvent = null;
        
        // Clear state after a short delay to allow listeners to react
        Timer(const Duration(milliseconds: 50), () {
          state = null;
        });
      }
    });
    
    // ✅ PHASE 10: Set cooldown timer (300ms)
    _cooldownTimer = Timer(const Duration(milliseconds: 300), () {
      _isInCooldown = false;
      
      // Process any pending events after cooldown
      if (_pendingEvents.isNotEmpty) {
        final nextEvent = _pendingEvents.removeAt(0);
        _pendingEvents.clear();
        _scheduleScroll(nextEvent);
      }
    });
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }
}

/// ✅ PHASE 7: Scroll provider with keepAlive
final scrollProvider = StateNotifierProvider<ScrollNotifier, ScrollEvent?>((ref) {
  ref.keepAlive();
  return ScrollNotifier();
});

/// ✅ PHASE 7: Scroll state provider (exposed as simple flag)
final isScrollingProvider = StateProvider<bool>((ref) {
  ref.keepAlive();
  return false;
});

