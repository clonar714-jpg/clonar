import 'package:flutter/material.dart';
import 'StylishSearchButton.dart';
import '../theme/AppColors.dart';

class DualActionButtons extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onShopTap;
  final double size;
  final double spacing;

  const DualActionButtons({
    super.key,
    required this.onSearchTap,
    required this.onShopTap,
    this.size = 32,
    this.spacing = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StylishSearchButton(
          onTap: onSearchTap,
          size: size,
        ),
        SizedBox(width: spacing),
        GestureDetector(
          onTap: onShopTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomPaint(
              painter: ShopIconPainter(
                color: AppColors.primary,
              ),
              size: Size(size * 0.6, size * 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

class ShopIconPainter extends CustomPainter {
  final Color color;

  ShopIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw the three horizontal lines (left side)
    final lineSpacing = 3.0;
    final lineLength = 10.0;
    final startX = centerX - 7;
    
    // Top line (longest)
    canvas.drawLine(
      Offset(startX, centerY - lineSpacing),
      Offset(startX + lineLength, centerY - lineSpacing),
      paint,
    );
    
    // Middle line (medium)
    canvas.drawLine(
      Offset(startX, centerY),
      Offset(startX + lineLength - 2, centerY),
      paint,
    );
    
    // Bottom line (shortest)
    canvas.drawLine(
      Offset(startX, centerY + lineSpacing),
      Offset(startX + lineLength - 4, centerY + lineSpacing),
      paint,
    );

    // Draw the magnifying glass (right side)
    final magnifierCenterX = centerX + 3;
    final magnifierCenterY = centerY;
    final magnifierRadius = 4.5;
    
    // Draw the magnifying glass circle
    canvas.drawCircle(
      Offset(magnifierCenterX, magnifierCenterY),
      magnifierRadius,
      paint,
    );
    
    // Draw the magnifying glass handle
    final handleStartX = magnifierCenterX + magnifierRadius * 0.7;
    final handleStartY = magnifierCenterY + magnifierRadius * 0.7;
    final handleEndX = magnifierCenterX + 6;
    final handleEndY = magnifierCenterY + 6;
    
    canvas.drawLine(
      Offset(handleStartX, handleStartY),
      Offset(handleEndX, handleEndY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is ShopIconPainter && oldDelegate.color != color;
  }
}
