import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Product.dart';
import '../services/AgentService.dart';
import '../services/CacheService.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _currentImageIndex = 0;
  int _quantity = 1;
  String? _selectedSize;
  String? _selectedColor;
  List<String> _availableSizes = [];
  List<String> _availableColors = [];
  bool _isOutOfStock = false;

  // Dynamic product content
  String _whatPeopleSay = '';
  String _buyThisIf = '';
  List<String> _keyFeatures = [];
  bool _isLoadingDetails = true;

  @override
  void initState() {
    super.initState();
    _initializeVariants();
    _loadProductDetails();
  }
  
  Future<void> _loadProductDetails() async {
    try {
      setState(() {
        _isLoadingDetails = true;
      });
      
      // ✅ CACHE: Generate cache key from product title and source
      final productTitle = widget.product.title;
      final productSource = widget.product.source ?? '';
      final cacheKey = CacheService.generateCacheKey(
        'product-details-$productTitle-$productSource',
      );
      
      // ✅ CACHE: Check cache first (product details change slowly, cache for 3 days)
      final cachedData = await CacheService.get(cacheKey);
      if (cachedData != null) {
        print('✅ Product details cache HIT for: $productTitle');
        setState(() {
          _whatPeopleSay = cachedData['whatPeopleSay'] ?? 'Customers appreciate the quality and value of this product.';
          _buyThisIf = cachedData['buyThisIf'] ?? 'This product is ideal for those seeking quality and reliability.';
          _keyFeatures = List<String>.from(cachedData['keyFeatures'] ?? []);
          _isLoadingDetails = false;
        });
        return; // Use cached data, skip API call
      }
      
      print('❌ Product details cache MISS for: $productTitle (fetching from API)');
      
      final url = Uri.parse('${AgentService.baseUrl}/api/product-details');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'domain': 'product', // ✅ NEW: Specify domain
          'id': widget.product.id.toString(),
          'title': widget.product.title,
          'description': widget.product.description,
          'price': widget.product.price,
          'rating': widget.product.rating,
          'source': widget.product.source,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        
        // ✅ CACHE: Store response in cache (3 days expiry for product details)
        await CacheService.set(
          cacheKey,
          data,
          expiry: const Duration(days: 3),
          query: 'product-details',
        );
        print('💾 Cached product details for: $productTitle');
        
        setState(() {
          _whatPeopleSay = data['whatPeopleSay'] ?? 'Customers appreciate the quality and value of this product.';
          _buyThisIf = data['buyThisIf'] ?? 'This product is ideal for those seeking quality and reliability.';
          _keyFeatures = List<String>.from(data['keyFeatures'] ?? []);
          _isLoadingDetails = false;
        });
      } else {
        // Use fallback content
        _setFallbackContent();
      }
    } catch (e) {
      print('Error loading product details: $e');
      _setFallbackContent();
    }
  }
  
  void _setFallbackContent() {
    setState(() {
      _whatPeopleSay = 'Customers appreciate the quality and value of this product. Many reviewers mention the good build quality and reliable performance.';
      _buyThisIf = 'You want a quality product that offers good value. Ideal for those seeking reliability and performance.';
      _keyFeatures = ['Quality materials', 'Reliable performance', 'Good value', 'Durable construction'];
      _isLoadingDetails = false;
    });
  }

  void _initializeVariants() {
    // ✅ null-safe: safely handle empty or null variants
    if (widget.product.variants.isNotEmpty) {
      _availableColors = widget.product.variants
          .where((v) => v.color.isNotEmpty) // ✅ null-safe: filter out empty colors
          .map((v) => v.color)
          .toList();
      _selectedColor = _availableColors.isNotEmpty ? _availableColors.first : null; // ✅ null-safe: check if colors exist
      _updateAvailableSizes();
    }
  }

  void _updateAvailableSizes() {
    if (_selectedColor != null) {
      try {
      final selectedVariant = widget.product.variants
            .firstWhere((v) => v.color == _selectedColor); // ✅ null-safe: find variant safely
        _availableSizes = selectedVariant.sizes
            .where((size) => size.isNotEmpty) // ✅ null-safe: filter out empty sizes
            .toList();
        _selectedSize = _availableSizes.isNotEmpty ? _availableSizes.first : null; // ✅ null-safe: check if sizes exist
        _updateStockStatus();
      } catch (e) {
        // ✅ null-safe: handle case where variant not found
        _availableSizes = [];
        _selectedSize = null;
      _updateStockStatus();
    }
  }
  }

  void _updateStockStatus() {
    if (_selectedColor != null && _selectedSize != null) {
      try {
      final selectedVariant = widget.product.variants
            .firstWhere((v) => v.color == _selectedColor); // ✅ null-safe: find variant safely
        _isOutOfStock = selectedVariant.availableQuantity <= 0; // ✅ null-safe: check if out of stock
      } catch (e) {
        // ✅ null-safe: handle case where variant not found
        _isOutOfStock = true;
      }
    } else {
      _isOutOfStock = false; // ✅ null-safe: reset stock status if no selection
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Scrollable content with image
            SingleChildScrollView(
        child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                  // Image carousel at the top (scrollable)
                  _buildImageCarousel(),
            
                  // Content with padding
                  Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    
                    // Product info section
                    _buildProductInfo(),
                    
                    const SizedBox(height: 24),
                    
                    // Middle sections
                    _buildWhatPeopleSaySection(),
                    const SizedBox(height: 24),
                    _buildBuyThisIfSection(),
                    const SizedBox(height: 24),
                    _buildFeatureTags(),
                    
                    const SizedBox(height: 24),
                    
                    // Key Features
                    _buildKeyFeatures(),
                    
                    const SizedBox(height: 100), // Space for fixed bottom buttons
                  ],
                ),
              ),
                ],
            ),
            ),
            
            // Fixed close and share icons at the top
            _buildFixedTopButtons(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomButtons(),
    );
  }

  Widget _buildFixedTopButtons() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                icon: const Icon(Icons.close, size: 24),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textPrimary,
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageCarousel() {
    // ✅ null-safe: handle empty images list
    if (widget.product.images.isEmpty) {
    return SizedBox(
      height: 300,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surfaceVariant,
            border: Border.all(
              color: AppColors.surfaceVariant,
              width: 1,
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.image_not_supported,
              color: AppColors.textSecondary,
              size: 60,
            ),
          ),
        ),
      );
    }

    // Only show carousel if there's more than one image
    final hasMultipleImages = widget.product.images.length > 1;

    return Stack(
      children: [
        SizedBox(
          height: 300,
      child: PageView.builder(
        onPageChanged: (index) {
          setState(() {
            _currentImageIndex = index;
          });
        },
        itemCount: widget.product.images.length,
        itemBuilder: (context, index) {
              final imageUrl = widget.product.images[index]; // ✅ null-safe: get image URL safely
              return GestureDetector(
                onTap: () => _viewImageFullscreen(index),
                child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.surfaceVariant,
              border: Border.all(
                color: AppColors.surfaceVariant,
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: widget.product.images[index],
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.image,
                    color: AppColors.textSecondary,
                    size: 60,
                  ),
                ),
              ),
              ),
            ),
          );
        },
      ),
        ),
        // Page indicator (dots) at the bottom
        if (hasMultipleImages)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.product.images.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
        // Image counter (e.g., "1 / 3") at the top right
        if (hasMultipleImages)
          Positioned(
            top: 12,
            right: 32,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentImageIndex + 1} / ${widget.product.images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProductInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          widget.product.title.isNotEmpty ? widget.product.title : 'Untitled Product', // ✅ null-safe: handle empty title
          style: AppTypography.title1.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 8),
        
        // Rating
        Row(
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 20),
            const SizedBox(width: 4),
            Text(
              '${widget.product.rating.toStringAsFixed(1)} (2,054)', // ✅ null-safe: format rating safely
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // Price with discount support
        _buildPriceSection(),
        const SizedBox(height: 20),
        
        // Color dropdown
        if (_availableColors.isNotEmpty) // ✅ null-safe: only show if colors available
        _buildDropdown('Color', _selectedColor, _availableColors, (value) {
          setState(() {
              _selectedColor = value; // ✅ null-safe: handle null value
            _updateAvailableSizes();
          });
        }),
        if (_availableColors.isNotEmpty) const SizedBox(height: 16),
        
        // Size dropdown
        if (_availableSizes.isNotEmpty) // ✅ null-safe: only show if sizes available
        _buildDropdown('Size', _selectedSize, _availableSizes, (value) {
          setState(() {
              _selectedSize = value; // ✅ null-safe: handle null value
            _updateStockStatus();
          });
        }),
        if (_availableSizes.isNotEmpty) const SizedBox(height: 16),
        const SizedBox(height: 16),
        
        // Quantity selector
        _buildQuantitySelector(),
      ],
    );
  }

  Widget _buildDropdown(String label, String? value, List<String> items, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.surfaceVariant),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value, // ✅ null-safe: value can be null
              isExpanded: true,
              onChanged: onChanged,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item.isNotEmpty ? item : 'Unknown'), // ✅ null-safe: handle empty items
                );
              }).toList(),
            ),
          ),
        ),
        if (label == 'Size' && _isOutOfStock) ...[
          const SizedBox(height: 4),
          Text(
            'Out of Stock',
            style: AppTypography.caption.copyWith(
              color: Colors.red,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPriceSection() {
    return Row(
      children: [
        if (widget.product.hasDiscount) ...[
          // Original price with strikethrough
          Text(
            widget.product.formattedPrice,
            style: AppTypography.title1.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 20,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 12),
          // Discounted price
          Text(
            widget.product.formattedDiscountPrice,
            style: AppTypography.title1.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ] else ...[
          // Normal price
          Text(
            widget.product.formattedPrice,
            style: AppTypography.title1.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuantitySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quantity',
          style: AppTypography.body1.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.surfaceVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 20),
                    onPressed: _quantity > 1 ? () {
                      setState(() {
                        _quantity--;
                      });
                    } : null,
                    color: _quantity > 1 ? AppColors.textPrimary : AppColors.textSecondary,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      _quantity.toString(),
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () {
                      setState(() {
                        _quantity++;
                      });
                    },
                    color: AppColors.textPrimary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWhatPeopleSaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What people say',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        _isLoadingDetails
            ? const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
            : Text(
                _whatPeopleSay.isNotEmpty
                    ? _whatPeopleSay
                    : 'Customers appreciate the quality and value of this product.',
          style: AppTypography.body1.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildBuyThisIfSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Buy this if',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        _isLoadingDetails
            ? const SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              )
            : Text(
                _buyThisIf.isNotEmpty
                    ? _buyThisIf
                    : 'This product is ideal for those seeking quality and reliability.',
          style: AppTypography.body1.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTags() {
    final List<String> features = _keyFeatures.isNotEmpty
        ? _keyFeatures
        : ['Quality materials', 'Reliable performance', 'Good value'];

    if (_isLoadingDetails && _keyFeatures.isEmpty) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: features.length,
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.surfaceVariant),
                ),
                child: Text(
                  features[index],
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKeyFeatures() {
    final List<String> keyFeatures = _keyFeatures.isNotEmpty
        ? _keyFeatures
        : ['Quality materials', 'Reliable performance', 'Good value', 'Durable construction'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key Features',
          style: AppTypography.title2.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingDetails && _keyFeatures.isEmpty)
          const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          )
        else
        ...keyFeatures.map((feature) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6, right: 12),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  feature,
                  style: AppTypography.body1.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Add to Wishlist and Add to Groups
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.favorite_border,
                    label: 'Add to Wishlist',
                    backgroundColor: AppColors.surfaceVariant,
                    textColor: AppColors.textPrimary,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to Wishlist!')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.group_add,
                    label: 'Add to Groups',
                    backgroundColor: AppColors.surfaceVariant,
                    textColor: AppColors.textPrimary,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to Groups!')),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Row 2: Buy with Clonar and In-App Reviews
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.shopping_cart,
                    label: _isOutOfStock ? 'Out of Stock' : 'Buy with Clonar',
                    backgroundColor: _isOutOfStock ? AppColors.surfaceVariant : Colors.tealAccent.shade700,
                    textColor: _isOutOfStock ? AppColors.textSecondary : Colors.white,
                    onPressed: _isOutOfStock ? null : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Added to Cart!')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.rate_review,
                    label: 'In-App Reviews',
                    backgroundColor: AppColors.surfaceVariant,
                    textColor: AppColors.textPrimary,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Reviews opened!')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    Color textColor = AppColors.textPrimary,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          splashFactory: InkRipple.splashFactory,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Open full-screen image viewer
  void _viewImageFullscreen(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageFullscreenView(
          images: widget.product.images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }
}

// Full-screen image viewer widget
class _ImageFullscreenView extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImageFullscreenView({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ImageFullscreenView> createState() => _ImageFullscreenViewState();
}

class _ImageFullscreenViewState extends State<_ImageFullscreenView> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen image viewer with swipe support
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemCount: widget.images.length,
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.images[index],
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                    errorWidget: (context, url, error) => const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Colors.white,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Close button at the top left
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          // Image counter at the top center (only if multiple images)
          if (widget.images.length > 1)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Page indicator dots at the bottom (only if multiple images)
          if (widget.images.length > 1)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.images.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index
                          ? Colors.white
                          : Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

