import 'dart:async';
import 'package:flutter/material.dart';


class PerplexityTypingAnimation extends StatefulWidget {
  final String text;
  final bool isStreaming;
  final TextStyle? textStyle;
  final Duration animationDuration;
  final int wordsPerTick;
  final bool animate;
  final VoidCallback? onAnimationComplete;

  const PerplexityTypingAnimation({
    Key? key,
    required this.text,
    required this.isStreaming,
    this.textStyle,
    this.animationDuration = const Duration(milliseconds: 30),
    this.wordsPerTick = 1,
    this.animate = true,
    this.onAnimationComplete,
  }) : super(key: key);

  @override
  State<PerplexityTypingAnimation> createState() => _PerplexityTypingAnimationState();
}

class _PerplexityTypingAnimationState extends State<PerplexityTypingAnimation>
    with SingleTickerProviderStateMixin {
  String _displayedText = '';
  Timer? _animationTimer;
  late AnimationController _cursorController;
  late Animation<double> _cursorAnimation;

  @override
  void initState() {
    super.initState();
    
    
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530), // Smooth blink speed
    );
    
    _cursorAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _cursorController,
      curve: Curves.easeInOut,
    ));
    
    _cursorController.repeat(reverse: true);
    
   
    _startAnimation();
  }

  @override
  void didUpdateWidget(PerplexityTypingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    
    if (widget.text != oldWidget.text) {
      if (widget.text.length > oldWidget.text.length) {
        
        if (_animationTimer == null || !_animationTimer!.isActive) {
          _startAnimation();
        }
      } else {
        // Text was replaced (correction) - restart animation
        _displayedText = '';
        _startAnimation();
      }
    }
    
    
    if (widget.isStreaming) {
      if (!_cursorController.isAnimating) {
        _cursorController.repeat(reverse: true);
      }
    } else {
      _cursorController.stop();
      _cursorController.value = 0.0; 
    }
  }

  void _startAnimation() {
   
    if (_animationTimer?.isActive ?? false) {
      return;
    }
    
   
    if (_displayedText.length >= widget.text.length) {
      // If displayed text is already longer, reset to match widget text
      _displayedText = widget.text;
      return;
    }
    
    
    _animationTimer = Timer.periodic(widget.animationDuration, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      
      if (_displayedText.length < widget.text.length) {
        // Get remaining text to display
        final remainingText = widget.text.substring(_displayedText.length).trimLeft();
        
        if (remainingText.isEmpty) {
          // No text left, we're done
          setState(() {
            _displayedText = widget.text;
          });
          timer.cancel();
          if (!widget.isStreaming) {
            _cursorController.stop();
            _cursorController.value = 0.0;
          }
          return;
        }
        
        // Split into words
        final words = remainingText.split(' ').where((w) => w.isNotEmpty).toList();
        
        if (words.isEmpty) {
          // No words, just add remaining characters
          setState(() {
            _displayedText = widget.text;
          });
          timer.cancel();
          if (!widget.isStreaming) {
            _cursorController.stop();
            _cursorController.value = 0.0;
          }
          return;
        }
        
        // Add words gradually (1-2 words per tick for smooth animation)
        int wordsToAdd = widget.wordsPerTick;
        if (words.length < wordsToAdd) {
          wordsToAdd = words.length;
        }
        
        if (wordsToAdd > 0) {
          // Calculate how much text to add
          final wordsToAddList = words.sublist(0, wordsToAdd);
          final textToAdd = wordsToAddList.join(' ');
          
          // Find where to insert in the original text
          final currentLength = _displayedText.length;
          // Find the next occurrence of this text after current position
          final searchStart = currentLength;
          final nextWordStart = widget.text.indexOf(textToAdd, searchStart);
          
          if (nextWordStart != -1 && nextWordStart >= currentLength) {
            // Found it - add up to that position (including any leading space)
            final endPos = nextWordStart + textToAdd.length;
            setState(() {
              _displayedText = widget.text.substring(0, endPos);
            });
          } else {
            // Fallback: append the words
            final spaceNeeded = currentLength > 0 && 
                               _displayedText.isNotEmpty && 
                               !_displayedText.endsWith(' ') ? ' ' : '';
            setState(() {
              _displayedText = _displayedText + spaceNeeded + textToAdd;
            });
          }
        }
      } else {
        // Animation complete
        timer.cancel();
        if (!widget.isStreaming) {
          _cursorController.stop();
          _cursorController.value = 0.0;
        }
        // ✅ PATCH 2: Call onAnimationComplete callback
        if (widget.onAnimationComplete != null) {
          widget.onAnimationComplete!();
        }
      }
    });
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ PATCH 2: If animate=false, instantly show full text (prevents freeze)
    if (!widget.animate) {
      return Text(widget.text, style: widget.textStyle);
    }
    
   
    final displayText = _displayedText;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text with fade-in effect
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: RichText(
            key: ValueKey(displayText),
            text: TextSpan(
              style: widget.textStyle ?? const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Colors.black87,
              ),
              children: [
                TextSpan(text: displayText),
                // Animated blinking cursor (only when streaming)
                if (widget.isStreaming || _displayedText.length < widget.text.length)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: AnimatedBuilder(
                      animation: _cursorAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorAnimation.value,
                          child: Container(
                            width: 2,
                            height: 18,
                            margin: const EdgeInsets.only(left: 2),
                            decoration: BoxDecoration(
                              color: widget.textStyle?.color ?? Colors.black87,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

