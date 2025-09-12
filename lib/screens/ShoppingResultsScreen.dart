import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Product.dart';
import '../services/ProductService.dart';
import '../services/ApiService.dart';
import 'ProductDetailScreen.dart';
import 'ShoppingGridScreen.dart';
import 'HotelDetailScreen.dart';
import 'HotelResultsScreen.dart';

class QuerySession {
  final String query;
  final List<Product> products;
  final List<Map<String, dynamic>> hotelResults;
  final String resultType; // "shopping" or "hotel"
  final bool isLoading;

  QuerySession({
    required this.query,
    required this.products,
    this.hotelResults = const [],
    this.resultType = "shopping",
    this.isLoading = false,
  });

  QuerySession copyWith({
    String? query,
    List<Product>? products,
    List<Map<String, dynamic>>? hotelResults,
    String? resultType,
    bool? isLoading,
  }) {
    return QuerySession(
      query: query ?? this.query,
      products: products ?? this.products,
      hotelResults: hotelResults ?? this.hotelResults,
      resultType: resultType ?? this.resultType,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ShoppingResultsScreen extends StatefulWidget {
  final String query;

  const ShoppingResultsScreen({
    super.key,
    required this.query,
  });

  @override
  State<ShoppingResultsScreen> createState() => _ShoppingResultsScreenState();
}

class _ShoppingResultsScreenState extends State<ShoppingResultsScreen> {
  List<QuerySession> conversationHistory = [];
  final TextEditingController _followUpController = TextEditingController();
  final FocusNode _followUpFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _queryKeys = [];

  @override
  void initState() {
    super.initState();
    print('ShoppingResultsScreen query: "${widget.query}"');
    // Create initial QuerySession
    final resultType = _detectResultType(widget.query);
    final initialSession = QuerySession(
      query: widget.query,
      products: [],
      hotelResults: [],
      resultType: resultType,
      isLoading: true,
    );
    conversationHistory.add(initialSession);
    _queryKeys.add(GlobalKey());
    _followUpController.addListener(() {
      print('Text changed: "${_followUpController.text}"');
    });
    _loadResultsForSession(0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure focus is removed when returning to this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followUpFocusNode.unfocus();
    });
  }

  @override
  void didUpdateWidget(ShoppingResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Unfocus when returning from navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _followUpFocusNode.unfocus();
    });
  }

  String _detectResultType(String query) {
    final lowerQuery = query.toLowerCase();
    final hotelKeywords = ['hotel', 'accommodation', 'stay', 'booking', 'resort', 'lodge', 'inn', 'hostel'];
    final shoppingKeywords = ['buy', 'shop', 'purchase', 'product', 'clothes', 'shoes', 'electronics', 'fashion'];
    
    for (String keyword in hotelKeywords) {
      if (lowerQuery.contains(keyword)) {
        return 'hotel';
      }
    }
    
    for (String keyword in shoppingKeywords) {
      if (lowerQuery.contains(keyword)) {
        return 'shopping';
      }
    }
    
    // Default to shopping if no specific keywords found
    return 'shopping';
  }

  void _navigateToHotelDetail(Map<String, dynamic> hotel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => HotelDetailScreen(hotel: hotel),
      ),
    );
  }

  // Helper method to launch URLs
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open $url')),
        );
      }
    }
  }

  // Helper method to make phone calls
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not make call to $phoneNumber')),
        );
      }
    }
  }

  // Helper method to open directions
  Future<void> _openDirections(String address) async {
    final Uri mapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}');
    if (await canLaunchUrl(mapsUri)) {
      await launchUrl(mapsUri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open directions to $address')),
        );
      }
    }
  }

  @override
  void dispose() {
    // Dismiss keyboard before disposing
    _followUpFocusNode.unfocus();
    _followUpController.dispose();
    _followUpFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFollowUpSubmitted() {
    final query = _followUpController.text.trim();
    print('ShoppingResultsScreen follow-up query: "$query"');
    
    if (query.isNotEmpty) {
      // Clear the field first
      _followUpController.clear();
      
      final resultType = _detectResultType(query);
      setState(() {
        // Add new QuerySession with loading state
        final newSession = QuerySession(
          query: query,
          products: [],
          hotelResults: [],
          resultType: resultType,
          isLoading: true,
        );
        conversationHistory.add(newSession);
        _queryKeys.add(GlobalKey());
      });
      
      final newQueryIndex = conversationHistory.length - 1;
      _loadResultsForSession(newQueryIndex);
      
      // Scroll to new query text after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(newQueryIndex);
      });
      
      // Dismiss keyboard after a short delay to allow the UI to update
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      });
    } else {
      // If empty, just focus back to the field
      print('Empty query - refocusing field');
      _followUpFocusNode.requestFocus();
    }
  }

  void _scrollToQuery(int queryIndex) {
    print('_scrollToQuery called with index: $queryIndex');
    print('_queryKeys.length: ${_queryKeys.length}');
    print('conversationHistory.length: ${conversationHistory.length}');
    
    if (queryIndex >= 0 && 
        queryIndex < _queryKeys.length && 
        _queryKeys[queryIndex].currentContext != null) {
      print('Scrolling to query at index: $queryIndex');
      try {
        Scrollable.ensureVisible(
          _queryKeys[queryIndex].currentContext!,
          duration: Duration.zero,
          alignment: 0.0,
        );
      } catch (e) {
        print('Scrollable.ensureVisible failed: $e');
        // Fallback: scroll to bottom
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    } else {
      print('Cannot scroll - conditions not met');
      print('queryIndex >= 0: ${queryIndex >= 0}');
      print('queryIndex < _queryKeys.length: ${queryIndex < _queryKeys.length}');
      print('_queryKeys[queryIndex].currentContext != null: ${queryIndex < _queryKeys.length ? _queryKeys[queryIndex].currentContext != null : 'N/A'}');
      
      // Fallback: scroll to bottom
      if (_scrollController.hasClients) {
        print('Using fallback scroll to bottom');
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }
  }

  Future<void> _loadResultsForSession(int sessionIndex) async {
    if (sessionIndex >= conversationHistory.length) return;
    
    try {
      final session = conversationHistory[sessionIndex];
      
      // Call the backend API for both shopping and hotel queries
      print('Searching for: ${session.query}');
      final apiResponse = await ApiService.search(session.query);
      print('API Response: $apiResponse');
      
      final resultType = apiResponse['type'] ?? 'shopping';
      final dynamic rawResults = apiResponse['results'] ?? [];
      final List<dynamic> results = rawResults is List ? rawResults : [];
      print('Result type: $resultType, Results count: ${results.length}');
      
      if (resultType == 'hotel') {
        // Map hotel results
        print('Processing hotel results...');
        print('Raw results type: ${results.runtimeType}');
        print('Raw results: $results');
        
        final List<Map<String, dynamic>> hotelResults = results.cast<Map<String, dynamic>>();
        print('Hotel results count: ${hotelResults.length}');
        if (hotelResults.isNotEmpty) {
          print('First hotel result: ${hotelResults[0]}');
        }
        
        setState(() {
          conversationHistory[sessionIndex] = session.copyWith(
            hotelResults: hotelResults,
            resultType: resultType,
            isLoading: false,
          );
        });
      } else {
        // Map shopping results to Product objects
        print('Shopping results: $results');
        final List<Product> products = results.map<Product>((item) {
          try {
            print('Mapping item: $item');
            final product = _mapShoppingResultToProduct(item);
            print('Mapped to product: ${product.title}');
            return product;
          } catch (e) {
            print('Error mapping product: $e, Item: $item');
            // Return a fallback product
            return Product(
              id: DateTime.now().millisecondsSinceEpoch,
              title: 'Error loading product',
              description: 'Unable to load product details',
              price: 0.0,
              source: 'Error',
              rating: 0.0,
              images: [],
              variants: [],
            );
          }
        }).toList();
        print('Final products list length: ${products.length}');
        setState(() {
          conversationHistory[sessionIndex] = session.copyWith(
            products: products,
            resultType: resultType,
            isLoading: false,
          );
        });
      }
      
      // Scroll to query to show loaded results after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(sessionIndex);
      });
    } catch (e) {
      print('Error loading results: $e');
      // Show error in the UI
      setState(() {
        conversationHistory[sessionIndex] = conversationHistory[sessionIndex].copyWith(
          isLoading: false,
          // Add error state - you might want to add an error field to QuerySession
        );
      });
      
      // Show error dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(sessionIndex);
        _showErrorDialog('Failed to load results: $e');
      });
    }
  }

  // Map backend shopping results to Product objects
  Product _mapShoppingResultToProduct(Map<String, dynamic> item) {
    // Parse price from string (e.g., "$29.99" -> 29.99)
    double parsePrice(dynamic priceValue) {
      if (priceValue == null) return 0.0;
      final priceStr = priceValue.toString().trim();
      if (priceStr.isEmpty || priceStr == '') return 0.0;
      final cleanPrice = priceStr.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleanPrice) ?? 0.0;
    }

    // Parse rating from string (e.g., "4.5" -> 4.5)
    double parseRating(dynamic ratingValue) {
      if (ratingValue == null) return 0.0;
      final ratingStr = ratingValue.toString().trim();
      if (ratingStr.isEmpty || ratingStr == '') return 0.0;
      return double.tryParse(ratingStr) ?? 0.0;
    }

    // Safe string extraction
    String safeString(dynamic value, String fallback) {
      if (value == null) return fallback;
      final str = value.toString().trim();
      return str.isEmpty ? fallback : str;
    }

    final price = parsePrice(item['price'] ?? item['extracted_price']);
    final oldPrice = parsePrice(item['old_price']);
    
    return Product(
      id: DateTime.now().millisecondsSinceEpoch + (item['title']?.toString().hashCode ?? 0),
      title: safeString(item['title'], 'Unknown Product'),
      description: safeString(item['tag'] ?? item['delivery'], 'No description available'),
      price: price,
      discountPrice: oldPrice > price ? oldPrice : null,
      source: safeString(item['source'], 'Unknown Source'),
      rating: parseRating(item['rating']),
      images: item['thumbnail'] != null ? [safeString(item['thumbnail'], '')] : [],
      variants: [],
    );
  }

  // Safe hotel data extraction
  Map<String, dynamic> _extractHotelData(Map<String, dynamic> hotel) {
    // Safe string extraction
    String safeString(dynamic value, String fallback) {
      if (value == null) return fallback;
      final str = value.toString().trim();
      return str.isEmpty ? fallback : str;
    }

    // Safe number extraction
    double safeNumber(dynamic value, double fallback) {
      if (value == null) return fallback;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      final str = value.toString().trim();
      if (str.isEmpty) return fallback;
      return double.tryParse(str) ?? fallback;
    }

    // Safe int extraction
    int safeInt(dynamic value, int fallback) {
      if (value == null) return fallback;
      if (value is int) return value;
      if (value is double) return value.toInt();
      final str = value.toString().trim();
      if (str.isEmpty) return fallback;
      return int.tryParse(str) ?? fallback;
    }

    // Safe amenities extraction
    List<String> safeAmenities(dynamic value) {
      if (value == null) return <String>[];
      if (value is List) {
        return value.map((item) => item?.toString() ?? '').where((item) => item.isNotEmpty).toList();
      }
      return <String>[];
    }

    // Handle images - properly extract from images array
    List<String> getImages() {
      final images = hotel['images'];
      if (images != null && images is List && images.isNotEmpty) {
        // Extract all image URLs from the images array
        final imageUrls = <String>[];
        for (final img in images) {
          if (img is String && img.isNotEmpty) {
            imageUrls.add(img);
          } else if (img is Map && img['thumbnail'] != null) {
            final thumbnail = img['thumbnail'].toString();
            if (thumbnail.isNotEmpty) {
              imageUrls.add(thumbnail);
            }
          }
        }
        if (imageUrls.isNotEmpty) {
          return imageUrls;
        }
      }
      
      // Fallback to thumbnail if available
      final thumbnail = hotel['thumbnail'];
      if (thumbnail != null && thumbnail.toString().isNotEmpty) {
        return [thumbnail.toString()];
      }
      return <String>[];
    }

    return {
      'name': safeString(hotel['name'], 'Unknown Hotel'),
      'location': safeString(hotel['address'], 'Location not specified'),
      'rating': safeNumber(hotel['rating'], 0.0),
      'reviewCount': safeInt(hotel['reviews'], 0),
      'price': safeNumber(hotel['price'], 0.0),
      'originalPrice': safeNumber(hotel['originalPrice'], 0.0),
      'description': safeString(hotel['description'], 'No description available'),
      'thumbnail': safeString(hotel['thumbnail'], ''),
      'link': safeString(hotel['link'], ''),
      'amenities': safeAmenities(hotel['amenities']),
      'images': getImages(),
    };
  }

  // Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Mock hotel data method - now replaced with real API calls
  // Future<List<Map<String, dynamic>>> _loadHotelResults(String query) async {
  //   // This method is no longer used - replaced with ApiService.search()
  //   return [];
  // }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // Dismiss keyboard before navigation
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Column(
        children: [
          // Fixed query bar at the top
          _buildFixedQueryBar(),
          
          // Conversation history
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: conversationHistory.length,
              itemBuilder: (context, index) {
                final session = conversationHistory[index];
                return _buildQuerySession(session, index);
              },
            ),
          ),
          
          // Follow-up input bar
          _buildFollowUpBar(),
        ],
        ),
      ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          // Dismiss keyboard immediately
          FocusScope.of(context).unfocus();
          // Small delay to ensure keyboard dismissal
          Future.delayed(const Duration(milliseconds: 100), () {
            Navigator.pop(context);
          });
        },
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.bookmark_border),
          onPressed: () {
            // TODO: Implement bookmark functionality
          },
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: () {
            // TODO: Implement share functionality
          },
        ),
      ],
    );
  }

  Widget _buildFixedQueryBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.surfaceVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: AppColors.textSecondary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Search for products, hotels, flights, and more...',
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuerySession(QuerySession session, int index) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Query text + tags container with KeyedSubtree
        KeyedSubtree(
          key: index < _queryKeys.length ? _queryKeys[index] : GlobalKey(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Query text (simple format like before)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  session.query,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  softWrap: true,
                  maxLines: null,
                  overflow: TextOverflow.visible,
                ),
              ),
              
              // Tags row (dynamic based on result type)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildTag('Clonar'),
                    _buildTag(session.resultType == 'hotel' ? 'Hotels' : 'Shopping'),
                    _buildTag('Images'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        
        // Results or loading indicator
        if (session.isLoading)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _buildResultsForSession(session),
      ],
    );
  }

  Widget _buildTag(String text) {
    return GestureDetector(
      onTap: () {
        if (text == 'Shopping') {
          // Navigate to ShoppingGridScreen with all products from all sessions
          final allProducts = <Product>[];
          for (final session in conversationHistory) {
            allProducts.addAll(session.products);
          }
          if (allProducts.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShoppingGridScreen(products: allProducts),
              ),
            );
          }
        } else if (text == 'Hotels') {
          // Navigate to HotelResultsScreen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HotelResultsScreen(query: 'hotels'),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }


  Widget _buildResultsForSession(QuerySession session) {
    if (session.resultType == 'hotel') {
      return _buildHotelResultsList(session);
    } else {
      return _buildShoppingResultsList(session);
    }
  }

  Widget _buildShoppingResultsList(QuerySession session) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: session.products.length,
      itemBuilder: (context, index) {
        return Column(
          children: [
            _buildProductCard(session.products[index]),
            if (index < session.products.length - 1) const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildHotelResultsList(QuerySession session) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: session.hotelResults.length,
      itemBuilder: (context, index) {
        return Column(
          children: [
            _buildHotelCard(session.hotelResults[index]),
            if (index < session.hotelResults.length - 1) const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildProductCard(Product product) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.surfaceVariant,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            product.title,
            style: AppTypography.title2.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          
          // Rating + Source
          Row(
            children: [
              const Icon(
                Icons.star,
                color: Colors.amber,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${product.rating}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• ${product.source}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Price
          Text(
            product.formattedPrice,
            style: AppTypography.title1.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          // Images Layout
          _buildImageLayout(product),
          const SizedBox(height: 16),
          
          // Description
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
            product.description,
            style: AppTypography.body1.copyWith(
                fontSize: 14,
              height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotelCard(Map<String, dynamic> hotel) {
    // Extract safe hotel data
    final safeHotel = _extractHotelData(hotel);
    
    return GestureDetector(
      onTap: () => _navigateToHotelDetail(safeHotel),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.surfaceVariant,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hotel name and location
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    safeHotel['name'],
                    style: AppTypography.title1.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    safeHotel['location'],
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Rating and review count
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        safeHotel['rating'] > 0 ? '${safeHotel['rating']}' : 'N/A',
                        style: AppTypography.body1.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${safeHotel['reviewCount']} reviews)',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (safeHotel['originalPrice'] > 0) ...[
                            Text(
                              '\$${safeHotel['originalPrice']}',
                              style: AppTypography.body1.copyWith(
                                color: AppColors.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                          Text(
                            safeHotel['price'] > 0 ? '\$${safeHotel['price']}' : 'Price not available',
                            style: AppTypography.title1.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Image carousel
            _buildHotelImageCarousel(safeHotel['images']),
            
            // Quick actions
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // Empty onTap to prevent bubbling
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildQuickActionButton('Find a Room', Icons.bed, () {
                      _navigateToHotelDetail(safeHotel);
                    }),
                    _buildQuickActionButton('Website', Icons.language, () {
                      _launchUrl(safeHotel['link']);
                    }),
                    _buildQuickActionButton('Call', Icons.phone, () {
                      _makePhoneCall(safeHotel['phone']);
                    }),
                    _buildQuickActionButton('Directions', Icons.directions, () {
                      _openDirections(safeHotel['location']);
                    }),
                  ],
                ),
              ),
            ),
            
            // Description or Amenities
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (safeHotel['description'] != 'No description available')
                    Text(
                      safeHotel['description'],
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    )
                  else if (safeHotel['amenities'].isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Amenities:',
                          style: AppTypography.body1.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: safeHotel['amenities'].take(6).map<Widget>((amenity) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                amenity,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    )
                  else
                    Text(
                      'No additional information available',
                      style: AppTypography.body1.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotelImageCarousel(List<String>? images) {
    final imageList = images ?? [];
    if (imageList.isEmpty) {
      return SizedBox(
        height: 200,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surfaceVariant,
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.hotel,
                  color: AppColors.textSecondary,
                  size: 48,
                ),
                SizedBox(height: 8),
                Text(
                  'No images available',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: imageList.length,
        itemBuilder: (context, index) {
          return Container(
            width: 280,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.surfaceVariant,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageList[index],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: AppColors.surfaceVariant,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: AppColors.textSecondary,
                      size: 40,
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


  Widget _buildQuickActionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowUpBar() {
    return SafeArea(
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Left: Search Icon
            const Icon(
              Icons.search,
              color: AppColors.textSecondary,
              size: 24,
            ),
            
            const SizedBox(width: 16),
            
            // Center: TextField
            Expanded(
              child: GestureDetector(
                onTap: () {
                  print('TextField tapped - requesting focus');
                  _followUpFocusNode.requestFocus();
                },
                child: TextField(
                  controller: _followUpController,
                  focusNode: _followUpFocusNode,
                  onSubmitted: (value) => _onFollowUpSubmitted(),
                  onChanged: (value) {
                    // Enable real-time typing
                    print('Text changed: $value');
                  },
                  onTap: () {
                    print('TextField onTap - requesting focus');
                    _followUpFocusNode.requestFocus();
                  },
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enabled: true,
                  autofocus: false,
                  readOnly: false,
                  showCursor: true,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask follow up...',
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
            ),
            
            const SizedBox(width: 12),
            
            // Right: Send Button
            GestureDetector(
              onTap: _onFollowUpSubmitted,
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
    );
  }

  Widget _buildImageLayout(Product product) {
    if (product.images.isEmpty) {
      return SizedBox(
        height: 120,
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceVariant,
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported,
                        color: AppColors.textSecondary,
                        size: 32,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'No image available',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceVariant,
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.image_not_supported,
                        color: AppColors.textSecondary,
                        size: 32,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'No image available',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: Row(
        children: [
          // First image
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProductDetailScreen(product: product),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  product.images[0],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) {
                      return AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: child,
                      );
                    }
                    return Container(
                      color: AppColors.surfaceVariant,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.accent,
                          ),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.surfaceVariant,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.image_not_supported,
                              color: AppColors.textSecondary,
                              size: 28,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Image unavailable',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Second image or empty space
          Expanded(
            child: product.images.length > 1
                ? GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProductDetailScreen(product: product),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        product.images[1],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) {
                            return AnimatedOpacity(
                              opacity: 1.0,
                              duration: const Duration(milliseconds: 300),
                              child: child,
                            );
                          }
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.accent,
                                ),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    color: AppColors.textSecondary,
                                    size: 28,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Image unavailable',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.surfaceVariant.withOpacity(0.3),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

}

