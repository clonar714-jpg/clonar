import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import 'ShoppingResultsScreen.dart';

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Ensure search field is not focused when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.unfocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchSubmitted() {
    final query = _searchController.text.trim();
    print('ShopScreen submitting query: "$query"');
    _searchFocusNode.unfocus(); // Unfocus the search field
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    if (query.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShoppingResultsScreen(query: query),
        ),
      ).then((_) {
        // Clear search text when returning from ShoppingResultsScreen
        _searchController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Top Section with Logo and Icons (always at top)
              _buildTopSection(),
              
              // Middle Section (centered vertically)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Search Bar
                      _buildSearchBar(),
                      
                      const SizedBox(height: 16),
                      
                      // Quick Actions
                      _buildQuickActions(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Stack(
      children: [
        // Center Logo and Title
        Center(
          child: Column(
            children: [
              const SizedBox(height: 100),
              // Circle Logo Placeholder with brand icon
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.textPrimary,
                ),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.iconPlaceholder,
                    ),
                    child: const Icon(
                      Icons.people,
                      color: AppColors.textPrimary,
                      size: 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // App Title
              Text(
                'Clonar',
                style: AppTypography.headline1,
              ),
            ],
          ),
        ),
        
        // Top Right Icons
        Positioned(
          top: 40,
          right: 50,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notification Icon
              FaIcon(
                 FontAwesomeIcons.bell,
                color: AppColors.iconPrimary,
                size: 24,
              ),
              const SizedBox(width: 30),
              // Chat Icon
              FaIcon(
                FontAwesomeIcons.facebookMessenger,
                color: AppColors.iconPrimary,
                size: 24,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 56,
          maxHeight: 120,
        ),
        decoration: BoxDecoration(
          color: AppColors.searchBackground,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Left: Plus Icon
              const Icon(
                Icons.add,
                color: AppColors.iconPrimary,
                size: 24,
              ),
              
              const SizedBox(width: 16),
              
              // Center: TextField
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Shop, style, or clone an agent...',
                    hintStyle: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Right: Send Button
              GestureDetector(
                onTap: _onSearchSubmitted,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.shade700,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_upward,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
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
          // Row 2: Virtual Try On, Rate My Style
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(context, 'Virtual Try On'),
              const SizedBox(width: 12),
              _buildActionButton(context, 'Rate My Style'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String text) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.28, // ~28% of screen width
      height: 36,
      child: ElevatedButton(
        onPressed: () {
          // TODO: Implement action
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
}
