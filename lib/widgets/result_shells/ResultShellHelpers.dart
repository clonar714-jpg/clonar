// ======================================================================
// RESULT SHELL HELPERS - Shared card rendering utilities
// ======================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/query_session_model.dart';
import '../../models/Product.dart';
import '../SessionRenderer.dart';

/// Helper class to access card rendering methods from SessionRenderer
class ResultShellCardRenderer {
  final SessionRenderModel model;
  
  const ResultShellCardRenderer(this.model);
  
  /// Render intent-based content (cards) - delegates to SessionRenderer logic
  Widget buildIntentBasedContent(BuildContext context, QuerySession session, WidgetRef ref) {
    // Access the private method via a public wrapper
    // We'll need to make this accessible or create a public method
    final intent = session.resultType;
    
    if (intent == 'shopping' && session.products.isNotEmpty) {
      return _buildShoppingContent(session);
    } else if (intent == 'hotel' || intent == 'hotels') {
      if (session.hotelSections != null && session.hotelSections!.isNotEmpty) {
        return _buildHotelSectionsContent(session, ref);
      } else if (session.hotelResults.isNotEmpty) {
        return _buildHotelContent(session, ref);
      }
    } else if (intent == 'places' || intent == 'location') {
      return _buildPlacesContent(session, ref);
    } else if (intent == 'movies') {
      return _buildMoviesContent(context, session, ref);
    }
    
    return const SizedBox.shrink();
  }
  
  // Simplified card rendering methods (we'll need to import from SessionRenderer or duplicate)
  Widget _buildShoppingContent(QuerySession session) {
    const maxVisible = 12;
    final visibleProducts = session.products.take(maxVisible).toList();
    
    return Column(
      children: visibleProducts.map((product) {
        // This would need access to _buildProductCard from SessionRenderer
        // For now, return a placeholder
        return const SizedBox.shrink();
      }).toList(),
    );
  }
  
  Widget _buildHotelSectionsContent(QuerySession session, WidgetRef ref) {
    return const SizedBox.shrink();
  }
  
  Widget _buildHotelContent(QuerySession session, WidgetRef ref) {
    return const SizedBox.shrink();
  }
  
  Widget _buildPlacesContent(QuerySession session, WidgetRef ref) {
    return const SizedBox.shrink();
  }
  
  Widget _buildMoviesContent(BuildContext context, QuerySession session, WidgetRef ref) {
    return const SizedBox.shrink();
  }
}

