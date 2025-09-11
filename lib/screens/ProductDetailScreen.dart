import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Product.dart';

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

  @override
  void initState() {
    super.initState();
    _initializeVariants();
  }

  void _initializeVariants() {
    if (widget.product.variants.isNotEmpty) {
      _availableColors = widget.product.variants.map((v) => v.color).toList();
      _selectedColor = _availableColors.first;
      _updateAvailableSizes();
    }
  }

  void _updateAvailableSizes() {
    if (_selectedColor != null) {
      final selectedVariant = widget.product.variants
          .firstWhere((v) => v.color == _selectedColor);
      _availableSizes = selectedVariant.sizes;
      _selectedSize = _availableSizes.isNotEmpty ? _availableSizes.first : null;
      _updateStockStatus();
    }
  }

  void _updateStockStatus() {
    if (_selectedColor != null && _selectedSize != null) {
      final selectedVariant = widget.product.variants
          .firstWhere((v) => v.color == _selectedColor);
      _isOutOfStock = selectedVariant.availableQuantity == 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top section with close/share icons and image carousel
            _buildTopSection(),
            
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
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
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomButtons(),
    );
  }

  Widget _buildTopSection() {
    return Column(
      children: [
        // Close and share icons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.close, size: 24),
                onPressed: () => Navigator.pop(context),
                color: AppColors.textPrimary,
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 24),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Product shared!')),
                  );
                },
                color: AppColors.textPrimary,
              ),
            ],
          ),
        ),
        
        // Image carousel
        _buildImageCarousel(),
      ],
    );
  }

  Widget _buildImageCarousel() {
    return SizedBox(
      height: 300,
      child: PageView.builder(
        onPageChanged: (index) {
          setState(() {
            _currentImageIndex = index;
          });
        },
        itemCount: widget.product.images.length,
        itemBuilder: (context, index) {
          return Container(
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
              child: Image.network(
                widget.product.images[index],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.image,
                      color: AppColors.textSecondary,
                      size: 60,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Text(
          widget.product.title,
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
              '${widget.product.rating} (2,054)',
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
        _buildDropdown('Color', _selectedColor, _availableColors, (value) {
          setState(() {
            _selectedColor = value!;
            _updateAvailableSizes();
          });
        }),
        const SizedBox(height: 16),
        
        // Size dropdown
        _buildDropdown('Size', _selectedSize, _availableSizes, (value) {
          setState(() {
            _selectedSize = value!;
            _updateStockStatus();
          });
        }),
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
              value: value,
              isExpanded: true,
              onChanged: onChanged,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
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
        Text(
          'Customers love the comfort and style of these shoes. Many reviewers mention the excellent fit and durability.',
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
        Text(
          'You want a versatile sneaker that works for both casual wear and light athletic activities. Perfect for everyday comfort.',
          style: AppTypography.body1.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTags() {
    final List<String> features = [
      'Heel Lockdown',
      'Breathability',
      'Eco-Friendly',
      'Durable',
      'Comfortable',
    ];

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
    final List<String> keyFeatures = [
      'Retro basketball style',
      'Heel lockdown',
      'Breathability',
      'Eco-conscious materials',
      'Lightweight design',
      'Versatile styling',
    ];

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
}

