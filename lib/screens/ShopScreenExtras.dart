import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import 'TravelScreen.dart';

/// Extracted features from ShopScreen that can be optionally included
/// This file contains: notification icon, chat icon, and quick action buttons

class ShopScreenExtras {
  /// Top right icons (notification and chat)
  static Widget buildTopRightIcons(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Notification Icon
        GestureDetector(
          onTap: () {
            // Dismiss keyboard when tapping notification
            FocusScope.of(context).unfocus();
          },
          child: FaIcon(
            FontAwesomeIcons.bell,
            color: AppColors.iconPrimary,
            size: 24,
          ),
        ),
        const SizedBox(width: 30),
        // Chat Icon
        GestureDetector(
          onTap: () {
            // Dismiss keyboard when tapping chat
            FocusScope.of(context).unfocus();
          },
          child: FaIcon(
            FontAwesomeIcons.facebookMessenger,
            color: AppColors.iconPrimary,
            size: 24,
          ),
        ),
      ],
    );
  }

  /// Quick action buttons widget
  static Widget buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Row 1: Shop Anything, Clone others' Style, Suggest an Outfit
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(context, 'Shop Anything'),
              _buildActionButton(context, 'Clone  Style'),
              _buildActionButton(context, 'Suggest an Outfit'),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Virtual Try On, Travel
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(context, 'Virtual Try On'),
              const SizedBox(width: 12),
              _buildActionButton(
                context,
                'Travel',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TravelScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildActionButton(BuildContext context, String text, {VoidCallback? onTap}) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.28, // ~28% of screen width
      height: 36,
      child: ElevatedButton(
        onPressed: () {
          // Dismiss keyboard when tapping action button
          FocusScope.of(context).unfocus();
          // Call custom callback if provided, otherwise default action
          if (onTap != null) {
            onTap();
          } else {
            // TODO: Implement default action
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSecondary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
        child: Text(
          text,
          style: AppTypography.button.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// Bottom navigation bar widget
  static Widget buildBottomNavigationBar({
    required int currentIndex,
    required Function(int) onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(
            color: AppColors.surfaceVariant,
            width: 0.5,
          ),
        ),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.iconSecondary,
        currentIndex: currentIndex,
        onTap: onTap,
        selectedLabelStyle: AppTypography.captionSmall,
        unselectedLabelStyle: AppTypography.captionSmall,
        elevation: 0,
        items: [
          BottomNavigationBarItem(
            icon: _buildShopIcon(false),
            activeIcon: _buildShopIcon(true),
            label: 'Shop',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view),
            activeIcon: Icon(Icons.grid_on),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Account',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite_outline),
            activeIcon: Icon(Icons.favorite),
            label: 'Wishlist',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checkroom_outlined),
            activeIcon: Icon(Icons.checkroom),
            label: 'Wardrobe',
          ),
        ],
      ),
    );
  }

  static Widget _buildShopIcon(bool isActive) {
    return Container(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _ShopIconPainter(
          color: isActive ? AppColors.primary : AppColors.iconSecondary,
        ),
      ),
    );
  }
}

class _ShopIconPainter extends CustomPainter {
  final Color color;

  _ShopIconPainter({required this.color});

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
    return oldDelegate is _ShopIconPainter && oldDelegate.color != color;
  }
}

