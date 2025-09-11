import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Product.dart';
import '../services/ProductService.dart';
import 'ProductDetailScreen.dart';
import 'ShoppingGridScreen.dart';

class QuerySession {
  final String query;
  final List<Product> products;
  final bool isLoading;

  QuerySession({
    required this.query,
    required this.products,
    this.isLoading = false,
  });

  QuerySession copyWith({
    String? query,
    List<Product>? products,
    bool? isLoading,
  }) {
    return QuerySession(
      query: query ?? this.query,
      products: products ?? this.products,
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
    final initialSession = QuerySession(
      query: widget.query,
      products: [],
      isLoading: true,
    );
    conversationHistory.add(initialSession);
    _queryKeys.add(GlobalKey());
    _followUpController.addListener(() {
      print('Text changed: "${_followUpController.text}"');
    });
    _loadProductsForSession(0);
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
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    if (query.isNotEmpty) {
      setState(() {
        // Add new QuerySession with loading state
        final newSession = QuerySession(
          query: query,
          products: [],
          isLoading: true,
        );
        conversationHistory.add(newSession);
        _queryKeys.add(GlobalKey());
        _followUpController.clear(); // Clear the field
      });
      final newQueryIndex = conversationHistory.length - 1;
      _loadProductsForSession(newQueryIndex);
      // Scroll to new query text after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(newQueryIndex);
      });
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

  Future<void> _loadProductsForSession(int sessionIndex) async {
    if (sessionIndex >= conversationHistory.length) return;
    
    try {
      final productService = ProductService();
      final session = conversationHistory[sessionIndex];
      final fetchedProducts = await productService.fetchProducts(session.query);
      
      setState(() {
        // Update the specific session with products and set loading to false
        conversationHistory[sessionIndex] = session.copyWith(
          products: fetchedProducts,
          isLoading: false,
        );
      });
      // Scroll to query to show loaded results after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(sessionIndex);
      });
    } catch (e) {
      setState(() {
        // Update the session to show loading is complete even on error
        conversationHistory[sessionIndex] = conversationHistory[sessionIndex].copyWith(
          isLoading: false,
        );
      });
      // Scroll to query to show error state after the frame is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToQuery(sessionIndex);
      });
    }
  }

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
              
              // Tags row (for every query)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildTag('Clonar'),
                    _buildTag('Shopping'),
                    _buildTag('Images'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        
        // Products or loading indicator
        if (session.isLoading)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          _buildProductsListForSession(session),
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


  Widget _buildProductsListForSession(QuerySession session) {
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
              child: TextField(
                controller: _followUpController,
                focusNode: _followUpFocusNode,
                onSubmitted: (value) => _onFollowUpSubmitted(),
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                enabled: true,
                autofocus: false,
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

