import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/ShopScreen.dart';
import 'screens/FeedScreen.dart';
import 'screens/WardrobeScreen.dart';
import 'screens/WishlistScreen.dart';
import 'screens/AccountScreen.dart';
import 'screens/LoginPage.dart';
import 'screens/RegisterPage.dart';
import 'screens/SplashScreen.dart';
import 'theme/AppColors.dart';
import 'theme/Typography.dart';
import 'services/ApiService.dart';
import 'services/CacheService.dart';
import 'core/provider_observer.dart';
import 'core/emulator_detector.dart';

// Global theme data for reuse
late final ThemeData _appTheme;
late final SharedPreferences _prefs;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ STARTUP FIX: Defer first frame to prevent blocking work from delaying UI
  WidgetsBinding.instance.deferFirstFrame();
  
  // ✅ PATCH E1: Add image cache size limits (prevents RAM overflow and UI blocking)
  PaintingBinding.instance.imageCache.maximumSize = 500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20; // 100 MB
  
  // ✅ STARTUP FIX: Run app immediately - no blocking work before first frame
  runApp(const ClonarApp());
  
  // ✅ STARTUP FIX: Allow first frame immediately (UI renders first)
  WidgetsBinding.instance.allowFirstFrame();
  
  // ✅ STARTUP FIX: Schedule ALL heavy work AFTER first frame is rendered
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ✅ WINDOW FIX: Defer emulator detection to prevent window tracking initialization
    if (kDebugMode) {
      Future(() => EmulatorDetector.isEmulator()).catchError((_) {
        // Silent failure - not critical
      });
    }
    
    // ✅ STARTUP FIX: Initialize cache service AFTER first frame (disk IO + JSON parsing)
    Future(() async {
      try {
        await CacheService.initialize();
        await CacheService.cleanExpired();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Cache initialization failed: $e');
        }
      }
    });
  });
}

// Preload critical assets to reduce startup time
// TEMP FIX — disable all preloading
/*
Future<void> _preloadCriticalAssets() async {
  await Future.wait([
    // Preload SharedPreferences
    SharedPreferences.getInstance().then((prefs) => _prefs = prefs),
    
    // Preload theme data
    _preloadThemeData(),
    
    // Preload fonts
    _preloadFonts(),
    
    // Preload system UI overlay style
    _preloadSystemUI(),
    
    // Initialize HTTP client
    Future.microtask(() => ApiService.initialize()),
  ]);
}
*/

// TEMP FIX — disable preloading
/*
Future<void> _preloadThemeData() async {
  _appTheme = ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.dark, // Dark theme
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
    ),
    dividerColor: AppColors.border,
  );
}
*/

// TEMP FIX — disable preloading
/*
Future<void> _preloadFonts() async {
  // Preload system fonts
  await Future.wait([
    // This will cache the fonts for faster subsequent access
    Future.microtask(() => AppTypography.title1),
    Future.microtask(() => AppTypography.title2),
    Future.microtask(() => AppTypography.body1),
    Future.microtask(() => AppTypography.body2),
  ]);
}
*/

// Preload critical images asynchronously
Future<void> _preloadImages() async {
  // Preload common placeholder images
  try {
    await Future.wait([
      // Add any critical images that should be preloaded
      // precacheImage(AssetImage('assets/images/logo.png'), context),
      // precacheImage(AssetImage('assets/images/placeholder.png'), context),
    ]);
  } catch (e) {
    // Ignore image preload errors
    print('Image preload error: $e');
  }
}

// TEMP FIX — disable preloading
/*
Future<void> _preloadSystemUI() async {
  // Set system UI overlay style for dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light, // Light icons for dark background
      systemNavigationBarColor: Color(0xFF121212), // Dark background
      systemNavigationBarIconBrightness: Brightness.light, // Light icons
    ),
  );
}
*/

class ClonarApp extends StatelessWidget {
  const ClonarApp({super.key});

  // ✅ GLOBAL FIX: Static ThemeData to prevent recreation on every build
  static final _theme = ThemeData(
    primarySwatch: Colors.blue,
    brightness: Brightness.dark, // Dark theme
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
    ),
    dividerColor: AppColors.border,
  );

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      observers: [AppProviderObserver()],
      child: MaterialApp(
        // ✅ GLOBAL FIX: Removed GlobalKey - it was recreated on every build causing MaterialApp recreation
        title: 'Clonar',
        theme: _theme,
        home: const AuthWrapper(),
        onGenerateRoute: (settings) {
          // Safe navigation fallback - prevents crashes during hot reload
          return MaterialPageRoute(
            builder: (_) => const AuthWrapper(),
          );
        },
        routes: {
          '/login': (context) => LoginPage(),
          '/register': (context) => RegisterPage(),
          '/account': (context) => const MainNavigationScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    // TEMP FIX — bypass auth check
    // _checkAuthStatusWithTimeout(); // ✅ Use timeout version
    setState(() {
      _isAuthenticated = true;
      _isLoading = false;
    });
  }

  Future<void> _checkAuthStatus() async {
    try {
      // 🧪 Development mode: bypass authentication
      const bool isDevelopment = true; // Set to false for production
      
      if (isDevelopment) {
        print('🧪 Dev mode: Authentication bypassed ✅');
        setState(() {
          _isAuthenticated = true;
          _isLoading = false;
        });
        return;
      }
      
      // Use preloaded SharedPreferences for faster access
      String? token = _prefs.getString('token');
      
      print('🔍 Auth check: Token found: ${token != null}');
      
      bool isValidToken = false;
      
      // 🔥 Dev Mode Bypass: Auto-save fake token for testing
      if (token == null || token.isEmpty) {
        debugPrint('🧪 Dev Mode: Auto-saving fake token for testing');
        await _prefs.setString('token', 'dev-mode-token');
        token = 'dev-mode-token';
        isValidToken = true;
        print('✅ Dev Mode: Using fake token');
      } else if (token.isNotEmpty) {
        // Validate JWT token format (should have exactly 3 segments separated by dots)
        final segments = token.split('.');
        if (segments.length == 3) {
          isValidToken = true;
          print('✅ Token format is valid (3 segments)');
        } else {
          print('❌ Token format is invalid (${segments.length} segments, expected 3)');
          // In dev mode, use fake token instead of clearing
          debugPrint('🧪 Dev Mode: Using fake token instead of clearing invalid token');
          await _prefs.setString('token', 'dev-mode-token');
          token = 'dev-mode-token';
          isValidToken = true;
        }
      }
      
      setState(() {
        _isAuthenticated = isValidToken;
        _isLoading = false;
      });
      
      print('✅ Auth check completed: Authenticated = $_isAuthenticated');
    } catch (e) {
      print('❌ Auth check error: $e');
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  // ✅ PREVENT STUCK: Add safety timeout for auth check
  Future<void> _checkAuthStatusWithTimeout() async {
    try {
      await _checkAuthStatus().timeout(Duration(seconds: 2)); // ✅ Even shorter
    } catch (e) {
      print('❌ Auth check timeout: $e');
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
              const SizedBox(height: 24),
              Text(
                'Loading...',
                style: AppTypography.body1.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 16),
              // Emergency reset buttons
              Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await _prefs.remove('token');
                      setState(() {
                        _isAuthenticated = false;
                        _isLoading = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Emergency: Clear Auth'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    child: Text('Emergency: Reset Loading'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_isAuthenticated) {
      return const MainNavigationScreen();
    } else {
      return LoginPage();
    }
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Lazy screen loading - only create when needed
  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const ShopScreen();
      case 1:
        return const FeedScreen();
      case 2:
        return const AccountScreen();
      case 3:
        return const WishlistScreen();
      case 4:
        return const WardrobeScreen();
      default:
        return const ShopScreen();
    }
  }

  // Lightweight navigation handler - instant switching
  void _onTabTapped(int index) {
    // Ignore redundant taps on the same tab
    if (index == _currentIndex) {
      return;
    }

    // Instantly switch to the new tab
    setState(() {
      _currentIndex = index;
    });
  }

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
      body: _getScreen(_currentIndex),
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
          onTap: _onTabTapped,
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
