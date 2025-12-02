import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String _selectedCategory = 'All';
  String _selectedSubcategory = 'All';
  bool _isGridView = true;
  String _feedFilter = 'All'; // 'All' or 'Following'
  bool _isSearchMode = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final Map<String, List<String>> _categorySubcategories = {
    'All': ['All'],
    'Fashion': ['Clothes', 'Outfits', 'Accessories', 'Shoes', 'Bags', 'Jewelry'],
    'Electronics': ['Laptops', 'Phones', 'Tablets', 'Headphones', 'Cameras', 'Gaming'],
    'Home & Garden': ['Furniture', 'Decor', 'Kitchen', 'Garden', 'Lighting', 'Storage'],
    'Sports': ['Fitness', 'Outdoor', 'Team Sports', 'Water Sports', 'Winter Sports', 'Equipment'],
    'Beauty': ['Skincare', 'Makeup', 'Hair Care', 'Fragrances', 'Tools', 'Bath & Body'],
    'Books': ['Fiction', 'Non-Fiction', 'Textbooks', 'Children', 'Comics', 'Audiobooks'],
    'Toys': ['Action Figures', 'Dolls', 'Board Games', 'Puzzles', 'Educational', 'Outdoor']
  };

  List<String> get _currentSubcategories {
    return _categorySubcategories[_selectedCategory] ?? ['All'];
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _toggleSearchMode() {
    setState(() {
      _isSearchMode = !_isSearchMode;
      if (_isSearchMode) {
        // Focus the search field when entering search mode
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      } else {
        // Clear search and unfocus when exiting search mode
        _searchController.clear();
        _searchFocusNode.unfocus();
      }
    });
  }

  List<Map<String, dynamic>> _getSampleItemsForCategory() {
    // Different content based on feed filter
    if (_feedFilter == 'Following') {
      return _getFollowingItems();
    }
    
    final Map<String, List<Map<String, dynamic>>> categoryItems = {
      'All': [
        {'title': 'Trending Now', 'subtitle': 'Popular items', 'image': '🔥', 'likes': '5.2k'},
        {'title': 'New Arrivals', 'subtitle': 'Latest drops', 'image': '✨', 'likes': '3.8k'},
        {'title': 'Best Sellers', 'subtitle': 'Top picks', 'image': '⭐', 'likes': '4.1k'},
        {'title': 'On Sale', 'subtitle': 'Great deals', 'image': '💰', 'likes': '2.9k'},
        {'title': 'Featured', 'subtitle': 'Editor\'s choice', 'image': '👑', 'likes': '3.5k'},
        {'title': 'Recommended', 'subtitle': 'For you', 'image': '💡', 'likes': '2.7k'},
        {'title': 'Limited Time', 'subtitle': 'Hurry up!', 'image': '⏰', 'likes': '1.8k'},
        {'title': 'Staff Picks', 'subtitle': 'Our favorites', 'image': '👥', 'likes': '2.3k'},
      ],
      'Fashion': [
        {'title': 'Summer Dresses', 'subtitle': 'Light & breezy', 'image': '👗', 'likes': '2.3k'},
        {'title': 'Denim Collection', 'subtitle': 'Classic jeans', 'image': '👖', 'likes': '1.8k'},
        {'title': 'Accessories', 'subtitle': 'Bags & jewelry', 'image': '👜', 'likes': '3.1k'},
        {'title': 'Shoe Trends', 'subtitle': 'Footwear', 'image': '👟', 'likes': '2.7k'},
        {'title': 'Outfit Ideas', 'subtitle': 'Style inspiration', 'image': '👔', 'likes': '4.2k'},
        {'title': 'Vintage Finds', 'subtitle': 'Retro style', 'image': '🕶️', 'likes': '1.5k'},
        {'title': 'Formal Wear', 'subtitle': 'Business attire', 'image': '👔', 'likes': '1.9k'},
        {'title': 'Casual Chic', 'subtitle': 'Everyday style', 'image': '👕', 'likes': '2.8k'},
      ],
      'Electronics': [
        {'title': 'Latest Phones', 'subtitle': 'Smartphones', 'image': '📱', 'likes': '3.2k'},
        {'title': 'Gaming Laptops', 'subtitle': 'High performance', 'image': '💻', 'likes': '2.1k'},
        {'title': 'Wireless Earbuds', 'subtitle': 'Audio gear', 'image': '🎧', 'likes': '2.8k'},
        {'title': 'Smart Watches', 'subtitle': 'Wearable tech', 'image': '⌚', 'likes': '1.7k'},
        {'title': 'Camera Gear', 'subtitle': 'Photography', 'image': '📷', 'likes': '2.4k'},
        {'title': 'Gaming Accessories', 'subtitle': 'Controllers & more', 'image': '🎮', 'likes': '1.9k'},
        {'title': 'Tablets', 'subtitle': 'Portable computing', 'image': '📱', 'likes': '1.6k'},
        {'title': 'Home Tech', 'subtitle': 'Smart devices', 'image': '🏠', 'likes': '2.3k'},
      ],
      'Home & Garden': [
        {'title': 'Modern Furniture', 'subtitle': 'Contemporary design', 'image': '🪑', 'likes': '2.9k'},
        {'title': 'Garden Tools', 'subtitle': 'Outdoor essentials', 'image': '🌱', 'likes': '1.4k'},
        {'title': 'Kitchen Gadgets', 'subtitle': 'Cooking tools', 'image': '🍳', 'likes': '2.1k'},
        {'title': 'Lighting Ideas', 'subtitle': 'Ambient lighting', 'image': '💡', 'likes': '1.8k'},
        {'title': 'Storage Solutions', 'subtitle': 'Organization', 'image': '📦', 'likes': '2.2k'},
        {'title': 'Decor Items', 'subtitle': 'Home accents', 'image': '🖼️', 'likes': '3.1k'},
        {'title': 'Outdoor Living', 'subtitle': 'Patio & deck', 'image': '🏡', 'likes': '1.7k'},
        {'title': 'Bedroom Sets', 'subtitle': 'Sleep essentials', 'image': '🛏️', 'likes': '2.5k'},
      ],
      'Sports': [
        {'title': 'Fitness Equipment', 'subtitle': 'Workout gear', 'image': '💪', 'likes': '2.6k'},
        {'title': 'Running Shoes', 'subtitle': 'Athletic footwear', 'image': '👟', 'likes': '3.2k'},
        {'title': 'Outdoor Gear', 'subtitle': 'Hiking & camping', 'image': '🎒', 'likes': '1.9k'},
        {'title': 'Team Sports', 'subtitle': 'Basketball, soccer', 'image': '⚽', 'likes': '2.3k'},
        {'title': 'Water Sports', 'subtitle': 'Swimming & surfing', 'image': '🏄', 'likes': '1.5k'},
        {'title': 'Winter Sports', 'subtitle': 'Skiing & snowboarding', 'image': '⛷️', 'likes': '1.2k'},
        {'title': 'Yoga & Pilates', 'subtitle': 'Mind & body', 'image': '🧘', 'likes': '2.8k'},
        {'title': 'Cycling Gear', 'subtitle': 'Bike accessories', 'image': '🚴', 'likes': '1.7k'},
      ],
      'Beauty': [
        {'title': 'Skincare Routine', 'subtitle': 'Face care', 'image': '🧴', 'likes': '3.4k'},
        {'title': 'Makeup Essentials', 'subtitle': 'Cosmetics', 'image': '💄', 'likes': '2.9k'},
        {'title': 'Hair Care', 'subtitle': 'Shampoo & styling', 'image': '💇', 'likes': '2.1k'},
        {'title': 'Fragrances', 'subtitle': 'Perfumes & colognes', 'image': '🌸', 'likes': '1.8k'},
        {'title': 'Beauty Tools', 'subtitle': 'Brushes & applicators', 'image': '🪞', 'likes': '2.5k'},
        {'title': 'Bath & Body', 'subtitle': 'Soaps & lotions', 'image': '🛁', 'likes': '1.9k'},
        {'title': 'Nail Care', 'subtitle': 'Manicure essentials', 'image': '💅', 'likes': '1.6k'},
        {'title': 'Men\'s Grooming', 'subtitle': 'Male beauty', 'image': '🧔', 'likes': '1.3k'},
      ],
      'Books': [
        {'title': 'Bestsellers', 'subtitle': 'Popular reads', 'image': '📚', 'likes': '2.1k'},
        {'title': 'Fiction Novels', 'subtitle': 'Storytelling', 'image': '📖', 'likes': '1.8k'},
        {'title': 'Non-Fiction', 'subtitle': 'Educational', 'image': '📘', 'likes': '1.5k'},
        {'title': 'Textbooks', 'subtitle': 'Academic', 'image': '📕', 'likes': '1.2k'},
        {'title': 'Children\'s Books', 'subtitle': 'Kids literature', 'image': '📗', 'likes': '2.3k'},
        {'title': 'Comics & Manga', 'subtitle': 'Graphic novels', 'image': '📙', 'likes': '1.7k'},
        {'title': 'Audiobooks', 'subtitle': 'Listen & learn', 'image': '🎧', 'likes': '1.4k'},
        {'title': 'Magazines', 'subtitle': 'Periodicals', 'image': '📰', 'likes': '1.1k'},
      ],
      'Toys': [
        {'title': 'Action Figures', 'subtitle': 'Collectibles', 'image': '🤖', 'likes': '2.4k'},
        {'title': 'Dolls & Playsets', 'subtitle': 'Imaginative play', 'image': '👸', 'likes': '1.9k'},
        {'title': 'Board Games', 'subtitle': 'Family fun', 'image': '🎲', 'likes': '2.7k'},
        {'title': 'Puzzles', 'subtitle': 'Brain teasers', 'image': '🧩', 'likes': '1.6k'},
        {'title': 'Educational Toys', 'subtitle': 'Learning tools', 'image': '🧮', 'likes': '2.2k'},
        {'title': 'Outdoor Toys', 'subtitle': 'Active play', 'image': '🚲', 'likes': '1.8k'},
        {'title': 'Building Sets', 'subtitle': 'Construction toys', 'image': '🧱', 'likes': '2.1k'},
        {'title': 'Art & Crafts', 'subtitle': 'Creative supplies', 'image': '🎨', 'likes': '1.5k'},
      ],
    };

    return categoryItems[_selectedCategory] ?? categoryItems['All']!;
  }

  List<Map<String, dynamic>> _getFollowingItems() {
    return [
      {'title': 'Sarah\'s Outfit', 'subtitle': '@sarah_style • 2h ago', 'image': '👗', 'likes': '324', 'isFollowing': true},
      {'title': 'Mike\'s Tech Review', 'subtitle': '@mike_tech • 4h ago', 'image': '📱', 'likes': '156', 'isFollowing': true},
      {'title': 'Emma\'s Home Decor', 'subtitle': '@emma_home • 6h ago', 'image': '🏠', 'likes': '89', 'isFollowing': true},
      {'title': 'Alex\'s Fitness Tips', 'subtitle': '@alex_fit • 8h ago', 'image': '💪', 'likes': '203', 'isFollowing': true},
      {'title': 'Lisa\'s Beauty Routine', 'subtitle': '@lisa_beauty • 10h ago', 'image': '💄', 'likes': '178', 'isFollowing': true},
      {'title': 'Tom\'s Book Review', 'subtitle': '@tom_reads • 12h ago', 'image': '📚', 'likes': '67', 'isFollowing': true},
      {'title': 'Anna\'s DIY Project', 'subtitle': '@anna_diy • 1d ago', 'image': '🛠️', 'likes': '145', 'isFollowing': true},
      {'title': 'Chris\'s Gaming Setup', 'subtitle': '@chris_games • 1d ago', 'image': '🎮', 'likes': '298', 'isFollowing': true},
    ];
  }

  void _showFeedFilterMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                'Feed Filter',
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              
              // All option
              _buildFilterOption(
                context,
                'All',
                'Show posts from everyone',
                Icons.public,
                _feedFilter == 'All',
                () {
                  setState(() {
                    _feedFilter = 'All';
                  });
                  Navigator.pop(context);
                },
              ),
              
              const SizedBox(height: 12),
              
              // Following option
              _buildFilterOption(
                context,
                'Following',
                'Show posts from accounts you follow',
                Icons.people,
                _feedFilter == 'Following',
                () {
                  setState(() {
                    _feedFilter = 'Following';
                  });
                  Navigator.pop(context);
                },
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterOption(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.body1.copyWith(
                      color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Fixed Top Row
          _buildFixedTopRow(),
          
          // Scrollable Body
          Expanded(
            child: _isSearchMode ? _buildSearchContent() : _buildFeedContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          
          // Second Row with Feed/Reels Icons
          _buildFeedReelsRow(),
          
          const SizedBox(height: 24),
          
          // Feed Items
          _buildFeedItems(),
          
          const SizedBox(height: 100), // Space for bottom navigation
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    return Column(
      children: [
        const SizedBox(height: 16),
        
        // Search Results
        Expanded(
          child: _buildSearchResults(),
        ),
      ],
    );
  }

  Widget _buildFixedTopRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(
            color: AppColors.surfaceVariant,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: _isSearchMode ? _buildSearchBar() : _buildNormalTopRow(),
      ),
    );
  }

  Widget _buildNormalTopRow() {
    return Row(
      children: [
        // Search Icon (Left side)
        GestureDetector(
          onTap: _toggleSearchMode,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18), // Rounded like Netflix
            ),
            child: Icon(
              Icons.search,
              color: AppColors.textPrimary,
              size: 18,
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Category Dropdown
        Expanded(
          flex: 3, // Increased from 2 to 3 for more space
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18), // More rounded like Netflix
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedCategory,
                isExpanded: true,
                style: AppTypography.body1.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14, // Slightly smaller font for better fit
                ),
                dropdownColor: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                icon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.textPrimary,
                    size: 16, // Slightly smaller icon
                  ),
                ),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedCategory = newValue!;
                    // Reset subcategory to first available option when category changes
                    _selectedSubcategory = _currentSubcategories.first;
                  });
                },
                items: _categorySubcategories.keys.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        value,
                        style: AppTypography.body1.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Subcategory Dropdown (Dynamic based on category)
        Expanded(
          flex: 3, // Increased from 2 to 3 for more space
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18), // More rounded like Netflix
              border: Border.all(color: AppColors.surfaceVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSubcategory,
                isExpanded: true,
                style: AppTypography.body1.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14, // Slightly smaller font for better fit
                ),
                dropdownColor: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                icon: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.textPrimary,
                    size: 16, // Slightly smaller icon
                  ),
                ),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedSubcategory = newValue!;
                  });
                },
                items: _currentSubcategories.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        value,
                        style: AppTypography.body1.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // 3-dotted menu icon (Right side)
        GestureDetector(
          onTap: () {
            _showFeedFilterMenu(context);
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _feedFilter == 'Following' ? AppColors.primary.withOpacity(0.1) : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18), // Rounded like Netflix
              border: Border.all(
                color: _feedFilter == 'Following' ? AppColors.primary : AppColors.surfaceVariant,
                width: _feedFilter == 'Following' ? 1 : 0,
              ),
            ),
            child: Icon(
              Icons.more_horiz,
              color: _feedFilter == 'Following' ? AppColors.primary : AppColors.textPrimary,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedReelsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Grid/Feed Icon
        GestureDetector(
          onTap: () {
            setState(() {
              _isGridView = true;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _isGridView ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isGridView ? Icons.grid_on : Icons.grid_view,
                  color: _isGridView ? AppColors.textPrimary : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
          'Feed',
                  style: AppTypography.body1.copyWith(
                    color: _isGridView ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(width: 16),
        
        // Reels/Video Icon
        GestureDetector(
          onTap: () {
            setState(() {
              _isGridView = false;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: !_isGridView ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  !_isGridView ? Icons.ondemand_video : Icons.video_library_outlined,
                  color: !_isGridView ? AppColors.textPrimary : AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Reels',
                  style: AppTypography.body1.copyWith(
                    color: !_isGridView ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedItems() {
    if (_isGridView) {
      return _buildGridView();
    } else {
      return _buildReelsView();
    }
  }

  Widget _buildGridView() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.8,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: 8,
      itemBuilder: (context, index) {
        return _buildFeedCard(index);
      },
    );
  }

  Widget _buildReelsView() {
    return Column(
      children: List.generate(6, (index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.surfaceVariant),
          ),
          child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                  Icons.play_circle_outline,
                  size: 48,
              color: AppColors.textSecondary,
            ),
                const SizedBox(height: 8),
            Text(
                  'Reel ${index + 1}',
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
          ),
        );
      }),
    );
  }

  Widget _buildFeedCard(int index) {
    final List<Map<String, dynamic>> sampleItems = _getSampleItemsForCategory();
    final item = sampleItems[index % sampleItems.length];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Center(
                child: Text(
                  item['image'],
                  style: const TextStyle(fontSize: 40),
                ),
              ),
            ),
          ),
          
          // Content
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'],
                    style: AppTypography.body1.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['subtitle'],
                    style: AppTypography.caption.copyWith(
                      color: _feedFilter == 'Following' ? AppColors.primary : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.favorite_border,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item['likes'],
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        // Back arrow
        GestureDetector(
          onTap: _toggleSearchMode,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.arrow_back,
              color: AppColors.textPrimary,
              size: 18,
            ),
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Search text field
        Expanded(
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: AppTypography.body1.copyWith(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Search users or hashtags...',
                hintStyle: AppTypography.body1.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                prefixIcon: Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  // Trigger search when text changes
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final searchQuery = _searchController.text.toLowerCase();
    
    if (searchQuery.isEmpty) {
      return _buildSearchSuggestions();
    }
    
    return _buildSearchResultsList(searchQuery);
  }

  Widget _buildSearchSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches
          Text(
            'Recent',
            style: AppTypography.title2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          _buildSearchSuggestionItem('@sarah_style', 'Sarah Johnson', 'user'),
          _buildSearchSuggestionItem('@mike_tech', 'Mike Chen', 'user'),
          _buildSearchSuggestionItem('#fashion', 'Fashion', 'hashtag'),
          _buildSearchSuggestionItem('#tech', 'Technology', 'hashtag'),
          
          const SizedBox(height: 24),
          
          // Popular hashtags
          Text(
            'Popular Hashtags',
            style: AppTypography.title2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          _buildSearchSuggestionItem('#summer2024', 'Summer 2024', 'hashtag'),
          _buildSearchSuggestionItem('#ootd', 'Outfit of the Day', 'hashtag'),
          _buildSearchSuggestionItem('#techreview', 'Tech Review', 'hashtag'),
          _buildSearchSuggestionItem('#homedecor', 'Home Decor', 'hashtag'),
        ],
      ),
    );
  }

  Widget _buildSearchSuggestionItem(String handle, String name, String type) {
    return GestureDetector(
      onTap: () {
        _searchController.text = handle;
        setState(() {});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: type == 'user' ? AppColors.primary : AppColors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                type == 'user' ? Icons.person : Icons.tag,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    handle,
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    name,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.search,
              color: AppColors.textSecondary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultsList(String query) {
    // Mock search results based on query
    final List<Map<String, dynamic>> searchResults = [
      {'type': 'user', 'handle': '@sarah_style', 'name': 'Sarah Johnson', 'followers': '2.3k'},
      {'type': 'user', 'handle': '@mike_tech', 'name': 'Mike Chen', 'followers': '1.8k'},
      {'type': 'hashtag', 'handle': '#fashion', 'name': 'Fashion', 'posts': '15.2k'},
      {'type': 'hashtag', 'handle': '#tech', 'name': 'Technology', 'posts': '8.9k'},
      {'type': 'user', 'handle': '@emma_home', 'name': 'Emma Wilson', 'followers': '3.1k'},
      {'type': 'hashtag', 'handle': '#homedecor', 'name': 'Home Decor', 'posts': '12.7k'},
    ];

    final filteredResults = searchResults.where((item) {
      return item['handle'].toLowerCase().contains(query) || 
             item['name'].toLowerCase().contains(query);
    }).toList();

    if (filteredResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: AppTypography.title2.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching for users or hashtags',
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredResults.length,
      itemBuilder: (context, index) {
        final item = filteredResults[index];
        return _buildSearchResultItem(item);
      },
    );
  }

  Widget _buildSearchResultItem(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.surfaceVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: item['type'] == 'user' ? AppColors.primary : AppColors.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              item['type'] == 'user' ? Icons.person : Icons.tag,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['handle'],
                  style: AppTypography.body1.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  item['name'],
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (item['type'] == 'user')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Follow',
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Text(
              '${item['posts']} posts',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
