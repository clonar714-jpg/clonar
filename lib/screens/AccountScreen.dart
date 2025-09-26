import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Persona.dart';
import '../models/Collage.dart';
import 'AddToListPage.dart';
import 'CreatePersonaPage.dart';
import 'DesignToUploadPage.dart';
import 'PersonaDetailPage.dart';
import 'CollageEditorPage.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All Items';
  final ScrollController _scrollController = ScrollController();

  // Sample collage data
  final List<Collage> _collages = [
    Collage(
      id: '1',
      title: 'Fashion Mood Board',
      description: 'My latest fashion inspiration',
      coverImageUrl: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=400',
      layout: 'grid',
      tags: ['fashion', 'moodboard', 'style'],
      isPublished: true,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Collage(
      id: '2',
      title: 'Travel Memories',
      description: 'Photos from my recent trip to Europe',
      coverImageUrl: 'https://images.unsplash.com/photo-1506905925346-14b8e128d6ba?w=400',
      layout: 'masonry',
      tags: ['travel', 'memories', 'europe'],
      isPublished: false,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      updatedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Collage(
      id: '3',
      title: 'Home Decor Ideas',
      description: 'Interior design inspiration',
      coverImageUrl: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=400',
      layout: 'diagonal',
      tags: ['home', 'decor', 'interior'],
      isPublished: true,
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
      updatedAt: DateTime.now().subtract(const Duration(days: 6)),
    ),
  ];

  // Sample persona data
  final List<Persona> _personas = [
    Persona(
      id: '1',
      name: 'Fashion Inspiration',
      description: 'My personal style collection',
      coverImageUrl: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=400',
      tags: ['fashion', 'style', 'outfits'],
      items: [
        PersonaItem(
          id: '1',
          imageUrl: 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=400',
          title: 'Summer Outfit',
          addedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
        PersonaItem(
          id: '2',
          imageUrl: 'https://images.unsplash.com/photo-1515372039744-b8f02a3ae446?w=400',
          title: 'Casual Look',
          addedAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
      updatedAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Persona(
      id: '2',
      name: 'Home Decor Ideas',
      description: 'Interior design inspiration for my new apartment',
      coverImageUrl: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=400',
      tags: ['home', 'decor', 'interior'],
      items: [
        PersonaItem(
          id: '3',
          imageUrl: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=400',
          title: 'Living Room',
          addedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ],
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      updatedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    Persona(
      id: '3',
      name: 'Travel Memories',
      description: 'Photos from my recent trips',
      coverImageUrl: 'https://images.unsplash.com/photo-1506905925346-14b8e128d6ba?w=400',
      tags: ['travel', 'memories', 'vacation'],
      items: [],
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      updatedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  // Sample data for saved items
  final List<Map<String, dynamic>> _savedItems = [
    {
      "title": "Modern Living Room",
      "image": "https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=400",
      "category": "Interior Design",
      "isFavorite": true,
      "type": "original",
      "status": "posted",
    },
    {
      "title": "Minimalist Kitchen",
      "image": "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=400",
      "category": "Kitchen",
      "isFavorite": false,
      "type": "collab",
      "status": "underway",
    },
    {
      "title": "Cozy Bedroom",
      "image": "https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=400",
      "category": "Bedroom",
      "isFavorite": true,
      "type": "original",
      "status": "posted",
    },
    {
      "title": "Garden Ideas",
      "image": "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400",
      "category": "Garden",
      "isFavorite": false,
      "type": "collab",
      "status": "underway",
    },
    {
      "title": "Bathroom Design",
      "image": "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=400",
      "category": "Bathroom",
      "isFavorite": true,
      "type": "original",
      "status": "posted",
    },
    {
      "title": "Office Space",
      "image": "https://images.unsplash.com/photo-1497366216548-37526070297c?w=400",
      "category": "Office",
      "isFavorite": false,
      "type": "collab",
      "status": "underway",
    },
    {
      "title": "Dining Room Setup",
      "image": "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=400",
      "category": "Dining",
      "isFavorite": true,
      "type": "original",
      "status": "posted",
    },
    {
      "title": "Outdoor Patio",
      "image": "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400",
      "category": "Outdoor",
      "isFavorite": false,
      "type": "collab",
      "status": "underway",
    },
    {
      "title": "Home Office",
      "image": "https://images.unsplash.com/photo-1497366216548-37526070297c?w=400",
      "category": "Office",
      "isFavorite": true,
      "type": "original",
      "status": "posted",
    },
    {
      "title": "Kids Room",
      "image": "https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=400",
      "category": "Kids",
      "isFavorite": false,
      "type": "collab",
      "status": "underway",
    },
  ];

  final List<Map<String, dynamic>> _boards = [
    {
      "title": "Home Decor",
      "itemCount": 24,
      "coverImage": "https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=400",
    },
    {
      "title": "Kitchen Ideas",
      "itemCount": 18,
      "coverImage": "https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=400",
    },
    {
      "title": "Garden Projects",
      "itemCount": 12,
      "coverImage": "https://images.unsplash.com/photo-1416879595882-3373a0480b5b?w=400",
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        // Reset filter when switching tabs
        if (_tabController.index == 1) { // Persona tab
          _selectedFilter = 'Vault';
        } else if (_tabController.index == 2) { // Uploads tab
          _selectedFilter = 'Posted';
        } else { // Collections tab
          _selectedFilter = 'All Items';
        }
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            // Collapsible profile header
            SliverAppBar(
              backgroundColor: AppColors.background,
              expandedHeight: 130,
              floating: false,
              pinned: false,
              snap: false,
              automaticallyImplyLeading: false,
              toolbarHeight: 0,
              collapsedHeight: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: SafeArea(
                  child: _buildProfileHeader(),
                ),
              ),
            ),
          ];
        },
        body: SafeArea(
          child: Column(
            children: [
              // Fixed TabBar
              Container(
                color: AppColors.background,
                child: TabBar(
                  controller: _tabController,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 3,
                  labelStyle: AppTypography.title2.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: AppTypography.title2,
                  tabs: const [
                    Tab(text: "Collections"),
                    Tab(text: "Persona"),
                    Tab(text: "Uploads"),
                  ],
                ),
              ),

              // Fixed Search bar + filters
              Container(
                color: AppColors.background,
                child: Column(
                  children: [
                    // Search bar + Plus button
                    _buildSearchSection(),
                    
                    // Filter buttons
                    _buildFilterSection(),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: IndexedStack(
                  index: _tabController.index,
                  children: [
                    _buildPinsGrid(),
                    _buildBoardsGrid(),
                    _buildCollagesGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Icon(
                  Icons.person,
                  size: 30,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Raghavendra Kumar",
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Founder @bridl360",
                      style: AppTypography.body2.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.settings,
                  color: AppColors.iconSecondary,
                  size: 20,
                ),
                onPressed: () {
                  // Handle settings
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Stats below the profile info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(label: "Uploads", value: "1"),
              _StatItem(label: "Followers", value: "144"),
              _StatItem(label: "Following", value: "166"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.searchBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.searchBorder),
              ),
              child: TextField(
                controller: _searchController,
                style: AppTypography.body1,
                decoration: InputDecoration(
                  hintText: "Search your Catalog",
                  hintStyle: AppTypography.body1.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.iconSecondary,
                  ),
                ),
                onChanged: (value) {
                  setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: () {
                _showCreateOptions(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    // Different filters based on the selected tab
    List<String> filters;
    switch (_tabController.index) {
      case 0: // Collections
        filters = ['All Items', 'Favorites', 'Saved', 'Created by You'];
        break;
      case 1: // Persona
        filters = ['Vault', 'Collab'];
        break;
      case 2: // Uploads
        filters = ['Posted', 'Under way'];
        break;
      default:
        filters = ['All Items', 'Favorites', 'Saved', 'Created by You'];
    }
    
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.asMap().entries.map((entry) {
            final index = entry.key;
            final filter = entry.value;
            final isSelected = _selectedFilter == filter;
            final count = _getFilterCount(filter);
            
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 6.0),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filter,
                      style: AppTypography.caption.copyWith(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? Colors.white.withOpacity(0.2) 
                            : AppColors.textSecondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        count.toString(),
                        style: AppTypography.caption.copyWith(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surfaceVariant,
                side: BorderSide.none,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPinsGrid() {
    final filteredItems = _getFilteredItems();
    print('Filtered items count: ${filteredItems.length}');
    print('Original items count: ${_savedItems.length}');
    
    if (filteredItems.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 64,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text(
              'No saved items yet',
              style: AppTypography.title2,
            ),
            SizedBox(height: 8),
            Text(
              'Start saving your favorite ideas!',
              style: AppTypography.body2,
            ),
          ],
        ),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        return _buildPinCard(item);
      },
    );
  }

  Widget _buildBoardsGrid() {
    final filteredPersonas = _getFilteredPersonas();
    
    if (filteredPersonas.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: 16),
            Text(
              'No personas yet',
              style: AppTypography.title2,
            ),
            SizedBox(height: 8),
            Text(
              'Create your first persona to get started',
              style: AppTypography.body1,
            ),
          ],
        ),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: filteredPersonas.length,
      itemBuilder: (context, index) {
        final persona = filteredPersonas[index];
        return _buildPersonaCard(persona);
      },
    );
  }

  Widget _buildCollagesGrid() {
    final filteredCollages = _getFilteredCollages();
    
    if (filteredCollages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_mosaic,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'No collages yet',
              style: AppTypography.title2,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first collage to get started',
              style: AppTypography.body1,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CollageEditorPage(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Collage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: filteredCollages.length + 1, // +1 for create button
      itemBuilder: (context, index) {
        if (index == filteredCollages.length) {
          // Create new collage button
          return _buildCreateCollageCard();
        }
        final collage = filteredCollages[index];
        return _buildCollageCard(collage);
      },
    );
  }

  Widget _buildPinCard(Map<String, dynamic> item) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: Icon(
                        Icons.image,
                        size: 48,
                        color: AppColors.iconPlaceholder,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          item['isFavorite'] = !item['isFavorite'];
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item['isFavorite'] ? Icons.favorite : Icons.favorite_border,
                          color: item['isFavorite'] ? AppColors.error : AppColors.iconSecondary,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['title'],
                  style: AppTypography.title2.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item['category'],
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonaCard(Persona persona) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PersonaDetailPage(persona: persona),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: persona.coverImageUrl != null
                    ? Image.network(
                        persona.coverImageUrl!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: AppColors.iconPlaceholder,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        width: double.infinity,
                        color: AppColors.surfaceVariant,
                        child: const Center(
                          child: Icon(
                            Icons.folder_outlined,
                            size: 48,
                            color: AppColors.iconPlaceholder,
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    persona.name,
                    style: AppTypography.title2.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${persona.items.length} items',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (persona.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: persona.tags.take(2).map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollageCard(Collage collage) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CollageEditorPage(existingCollage: collage),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: collage.coverImageUrl != null
                        ? Image.network(
                            collage.coverImageUrl!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.surfaceVariant,
                                child: const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 48,
                                    color: AppColors.iconPlaceholder,
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(
                            width: double.infinity,
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: Icon(
                                Icons.auto_awesome_mosaic,
                                size: 48,
                                color: AppColors.iconPlaceholder,
                              ),
                            ),
                          ),
                  ),
                  // Status indicator
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: collage.isPublished ? Colors.green : Colors.orange,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        collage.isPublished ? 'Posted' : 'Draft',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  // Layout indicator
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        collage.layout.toUpperCase(),
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collage.title,
                    style: AppTypography.title2.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${collage.items.length} items',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (collage.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: collage.tags.take(2).map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateCollageCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const CollageEditorPage(),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Create Collage',
              style: AppTypography.title2.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Start designing',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardCard(Map<String, dynamic> board) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                color: AppColors.surfaceVariant,
                child: const Center(
                  child: Icon(
                    Icons.folder,
                    size: 48,
                    color: AppColors.iconPlaceholder,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  board['title'],
                  style: AppTypography.title2.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
            Text(
                  '${board['itemCount']} pins',
                  style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Collage> _getFilteredCollages() {
    List<Collage> collages = List.from(_collages);
    
    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      collages = collages.where((collage) {
        return collage.title.toLowerCase().contains(_searchController.text.toLowerCase()) ||
               (collage.description?.toLowerCase().contains(_searchController.text.toLowerCase()) ?? false) ||
               collage.tags.any((tag) => tag.toLowerCase().contains(_searchController.text.toLowerCase()));
      }).toList();
    }
    
    // Apply category filter based on selected tab
    if (_tabController.index == 2) { // Uploads tab
      switch (_selectedFilter) {
        case 'Posted':
          collages = collages.where((collage) => collage.isPublished).toList();
          break;
        case 'Under way':
          collages = collages.where((collage) => !collage.isPublished).toList();
          break;
        default:
          break;
      }
    }
    
    return collages;
  }

  List<Persona> _getFilteredPersonas() {
    List<Persona> personas = List.from(_personas);
    
    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      personas = personas.where((persona) {
        return persona.name.toLowerCase().contains(_searchController.text.toLowerCase()) ||
               (persona.description?.toLowerCase().contains(_searchController.text.toLowerCase()) ?? false) ||
               persona.tags.any((tag) => tag.toLowerCase().contains(_searchController.text.toLowerCase()));
      }).toList();
    }
    
    // Apply category filter based on selected tab
    if (_tabController.index == 1) { // Persona tab
      switch (_selectedFilter) {
        case 'Vault':
          // For demo purposes, show all personas as "Vault" (original)
          break;
        case 'Collab':
          // For demo purposes, show empty for "Collab"
          personas = [];
          break;
        default:
          break;
      }
    }
    
    return personas;
  }

  List<Map<String, dynamic>> _getFilteredItems() {
    List<Map<String, dynamic>> items = List.from(_savedItems);
    
    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      items = items.where((item) {
        return item['title'].toLowerCase().contains(_searchController.text.toLowerCase()) ||
               item['category'].toLowerCase().contains(_searchController.text.toLowerCase());
      }).toList();
    }
    
    // Apply category filter based on selected tab
    if (_tabController.index == 1) { // Persona tab
      switch (_selectedFilter) {
        case 'Vault':
          items = items.where((item) => item['type'] == 'original').toList();
          break;
        case 'Collab':
          items = items.where((item) => item['type'] == 'collab').toList();
          break;
        default:
          break;
      }
    } else if (_tabController.index == 2) { // Uploads tab
      switch (_selectedFilter) {
        case 'Posted':
          items = items.where((item) => item['status'] == 'posted').toList();
          break;
        case 'Under way':
          items = items.where((item) => item['status'] == 'underway').toList();
          break;
        default:
          break;
      }
    } else { // Collections tab
      switch (_selectedFilter) {
        case 'Favorites':
          items = items.where((item) => item['isFavorite'] == true).toList();
          break;
        case 'Saved':
          // For demo purposes, show all items (since all items in this list are "saved")
          break;
        case 'Created by You':
          // For demo purposes, show all items
          break;
        default:
          break;
      }
    }
    
    return items;
  }

  // Helper method to get count for a specific filter
  int _getFilterCount(String filterName) {
    List<Map<String, dynamic>> items = List.from(_savedItems);
    
    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      items = items.where((item) {
        return item['title'].toLowerCase().contains(_searchController.text.toLowerCase()) ||
               item['category'].toLowerCase().contains(_searchController.text.toLowerCase());
      }).toList();
    }
    
    // Apply specific filter
    if (_tabController.index == 1) { // Persona tab
      switch (filterName) {
        case 'Vault':
          return items.where((item) => item['type'] == 'original').length;
        case 'Collab':
          return items.where((item) => item['type'] == 'collab').length;
        default:
          return items.length;
      }
    } else if (_tabController.index == 2) { // Uploads tab
      switch (filterName) {
        case 'Posted':
          return items.where((item) => item['status'] == 'posted').length;
        case 'Under way':
          return items.where((item) => item['status'] == 'underway').length;
        default:
          return items.length;
      }
    } else { // Collections tab
      switch (filterName) {
        case 'All Items':
          return items.length;
        case 'Favorites':
          return items.where((item) => item['isFavorite'] == true).length;
        case 'Saved':
          return items.length; // All items are considered "saved"
        case 'Created by You':
          return items.length; // For demo purposes, all items are "created by you"
        default:
          return items.length;
      }
    }
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Create New',
              style: AppTypography.title1,
            ),
            const SizedBox(height: 24),
            _buildCreateOption(
              icon: Icons.add,
              title: 'Add to Collections',
              subtitle: 'Add anything to your collections',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddToListPage(),
                  ),
                );
              },
            ),
            _buildCreateOption(
              icon: Icons.folder,
              title: 'Create Persona',
              subtitle: 'Organize anything',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreatePersonaPage(),
                  ),
                );
              },
            ),
            _buildCreateOption(
              icon: Icons.auto_awesome_mosaic,
              title: 'Design to Upload',
              subtitle: 'Combine multiple lists',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DesignToUploadPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: AppTypography.title2),
      subtitle: Text(subtitle, style: AppTypography.body2),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  
  const _StatItem({
    required this.label, 
    required this.value, 
    Key? key
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label, 
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}