import 'package:flutter/material.dart';
import 'screens/ShopScreen.dart';
import 'screens/FeedScreen.dart';
import 'screens/WardrobeScreen.dart';
import 'screens/WishlistScreen.dart';
import 'screens/AccountScreen.dart';
import 'theme/AppColors.dart';
import 'theme/Typography.dart';

Future<void> main() async {
  runApp(const ClonarApp());
}

class ClonarApp extends StatelessWidget {
  const ClonarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clonar',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      home: const MainNavigationScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const ShopScreen(),
    const FeedScreen(),
    const WardrobeScreen(),
    const WishlistScreen(),
    const AccountScreen(),
  ];

  Widget _buildShopIcon(bool isActive) {
    return Container(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: ShopIconPainter(
          color: isActive ? AppColors.primary : AppColors.iconSecondary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
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
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
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
              icon: Icon(Icons.checkroom_outlined),
              activeIcon: Icon(Icons.checkroom),
              label: 'Wardrobe',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite_outline),
              activeIcon: Icon(Icons.favorite),
              label: 'Wishlist',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
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

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

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
