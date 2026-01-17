import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/query_session_model.dart';
import '../models/Product.dart';
import '../theme/AppColors.dart';
import 'ClonarAnswerWidget.dart';
import '../providers/session_phase_provider.dart';
import '../providers/session_history_provider.dart';
import '../widgets/ResearchActivityWidget.dart';

class SessionRenderModel {
  final String sessionId;
  final int index;
  final BuildContext context;
  final Function(String, QuerySession) onFollowUpTap;
  final Function(Map<String, dynamic>) onHotelTap;
  final Function(Product) onProductTap;
  final Function(String) onViewAllHotels;
  final Function(String) onViewAllProducts;
  final String? query;
  
  SessionRenderModel({
    required this.sessionId, 
    required this.index,
    required this.context,
    required this.onFollowUpTap,
    required this.onHotelTap,
    required this.onProductTap,
    required this.onViewAllHotels,
    required this.onViewAllProducts,
    this.query,
  });
}

class SessionRenderer extends StatelessWidget {
  final SessionRenderModel model;
  
  const SessionRenderer({super.key, required this.model});
  
  @override
  Widget build(BuildContext context) {
    return _SessionContentRenderer(model: model);
  }
}

class _SessionContentRenderer extends ConsumerWidget {
  final SessionRenderModel model;
  
  const _SessionContentRenderer({required this.model});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
   
    final phase = ref.watch(sessionPhaseProvider(model.sessionId));
    
    
    final session = ref.read(sessionByIdProvider(model.sessionId));
    final query = session?.query ?? '';
    
    return Padding(
      key: ValueKey('session-${model.index}'),
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ FIX 3: Add horizontal padding to query text (16px like description/images)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              query,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          
          
          _buildContentDirectly(model.sessionId, phase, ref),
        ],
      ),
    );
  }
  
 
  Widget _buildContentDirectly(String sessionId, QueryPhase phase, WidgetRef ref) {
    debugPrint('🧱 SessionRenderer BUILD - phase: $phase');
    
   
    final query = model.query ?? ref.read(sessionByIdProvider(sessionId))?.query ?? '';
    
   
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: phase == QueryPhase.searching
          ? Padding(
              key: const ValueKey('search'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Builder(
                builder: (context) {
                  debugPrint('🔍 Rendering ResearchActivityWidget - query: $query');
                  return ResearchActivityWidget(
                    query: query,
                  );
                },
              ),
            )
          : ClonarAnswerWidget(
              key: ValueKey('perplexity-$sessionId'),
              sessionId: sessionId,
            ),
    );
  }
}
