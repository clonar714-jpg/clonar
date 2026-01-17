import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/AppColors.dart';
import '../providers/agent_provider.dart';
import '../providers/session_history_provider.dart';
import '../providers/follow_up_controller_provider.dart';
import '../models/query_session_model.dart';
import '../widgets/SessionRenderer.dart';
import '../screens/ProductDetailScreen.dart';
import '../screens/HotelDetailScreen.dart';
import '../screens/HotelResultsScreen.dart';
import '../screens/ShoppingGridScreen.dart';


class ClonarAnswerScreen extends ConsumerStatefulWidget {
  final String query;
  final String? imageUrl;
  final List<Map<String, dynamic>>? initialConversationHistory;
  final bool isReplayMode;
  final String? conversationId;

  const ClonarAnswerScreen({
    super.key,
    required this.query,
    this.imageUrl,
    this.initialConversationHistory,
    this.isReplayMode = false,
    this.conversationId,
  });

  @override
  ConsumerState<ClonarAnswerScreen> createState() => _ClonarAnswerScreenState();
}

class _ClonarAnswerScreenState extends ConsumerState<ClonarAnswerScreen> with WidgetsBindingObserver {
  final TextEditingController _followUpController = TextEditingController();
  final FocusNode _followUpFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _queryKeys = [];
  final ValueNotifier<bool> _showScrollButtonNotifier = ValueNotifier<bool>(false);
  
  // Memoization to prevent excessive rebuilds
  List<QuerySession>? _previousSessions;
  int _previousSessionHash = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    if (kDebugMode) {
      debugPrint('📱 ClonarAnswerScreen initState');
      debugPrint('   - Query: "${widget.query}"');
      debugPrint('   - isReplayMode: ${widget.isReplayMode}');
      debugPrint('   - conversationId: ${widget.conversationId}');
      final sessions = ref.read(sessionHistoryProvider);
      debugPrint('   - Sessions in provider: ${sessions.length}');
      for (int i = 0; i < sessions.length; i++) {
        final s = sessions[i];
        debugPrint('     Session $i: "${s.query}" (finalized: ${s.isFinalized})');
      }
    }
    
    // Unfocus follow-up field immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _followUpFocusNode.unfocus();
      }
    });
    
    // Add scroll listener
    _scrollController.addListener(_handleScroll);
    
    // Initialize query keys
    if (widget.initialConversationHistory != null && widget.initialConversationHistory!.isNotEmpty) {
      for (int i = 0; i < widget.initialConversationHistory!.length; i++) {
        _queryKeys.add(GlobalKey());
      }
    }
    _queryKeys.add(GlobalKey());
    
   
    if (!widget.isReplayMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          
          await Future.delayed(const Duration(milliseconds: 100));
          
          if (!mounted) return;
          
          final existingSessions = ref.read(sessionHistoryProvider);
          final trimmedQuery = widget.query.trim();
          
          if (kDebugMode) {
            debugPrint('🔍 Checking for duplicate query: "$trimmedQuery"');
            debugPrint('   - Existing sessions: ${existingSessions.length}');
            for (int i = 0; i < existingSessions.length; i++) {
              final s = existingSessions[i];
              debugPrint('   - Session $i: "${s.query}" (finalized: ${s.isFinalized}, summary: ${s.summary?.length ?? 0} chars)');
            }
          }
          
          // ✅ FIX: Check for finalized sessions (not just summary)
          final queryAlreadySubmitted = existingSessions.any((s) => 
            s.query.trim() == trimmedQuery && 
            s.imageUrl == widget.imageUrl &&
            (s.isFinalized || s.isStreaming || s.isParsing || s.summary != null)
          );
          
          if (!queryAlreadySubmitted) {
            if (kDebugMode) {
              debugPrint('🚀 Submitting new query: "${widget.query}"');
            }
            ref.read(agentControllerProvider.notifier).submitQuery(
              widget.query, 
              imageUrl: widget.imageUrl,
            );
          } else if (kDebugMode) {
            debugPrint('⏭️ Skipping duplicate query submission: "$trimmedQuery"');
          }
        }
      });
    } else {
      // ✅ REPLAY MODE: Sessions are already loaded from history - DO NOT submit query
      if (kDebugMode) {
        final existingSessions = ref.read(sessionHistoryProvider);
        debugPrint('✅ REPLAY MODE: Skipping query submission');
        debugPrint('   - Query: "${widget.query}"');
        debugPrint('   - Sessions in provider: ${existingSessions.length}');
        for (int i = 0; i < existingSessions.length; i++) {
          final s = existingSessions[i];
          debugPrint('   - Session $i: "${s.query}" (finalized: ${s.isFinalized})');
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _followUpController.dispose();
    _followUpFocusNode.dispose();
    _scrollController.dispose();
    _showScrollButtonNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _followUpFocusNode.unfocus();
    }
    super.didChangeAppLifecycleState(state);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    
    final isAtBottom = _scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 150.0;
    
    if (isAtBottom != _isAtBottom) {
      _isAtBottom = isAtBottom;
      _showScrollButtonNotifier.value = !isAtBottom;
    }
  }

  bool _isAtBottom = true;

  int _computeSessionHash(List<QuerySession> sessions) {
    if (sessions.isEmpty) return 0;
    int hash = sessions.length;
    for (final session in sessions) {
      hash = hash ^ session.sessionId.hashCode;
      hash = hash ^ (session.summary?.length ?? 0);
      hash = hash ^ (session.sections?.length ?? 0);
      hash = hash ^ (session.isStreaming ? 1 : 0);
      hash = hash ^ (session.isFinalized ? 2 : 0);
      hash = hash ^ (session.sources.length);
    }
    return hash;
  }

  void _onFollowUpSubmitted() {
    final query = _followUpController.text.trim();
    if (kDebugMode) {
      debugPrint('ClonarAnswerScreen follow-up query: "$query"');
    }
    
    if (query.isNotEmpty) {
      _followUpController.clear();
      
      final sessions = ref.read(sessionHistoryProvider);
      final previousSession = sessions.isNotEmpty ? sessions.last : null;
      
      ref.read(agentControllerProvider.notifier).submitFollowUp(
        query,
        previousSession?.query ?? '',
      );
      
      _queryKeys.add(GlobalKey());
      
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          FocusScope.of(context).unfocus();
        }
      });
    } else {
      _followUpFocusNode.requestFocus();
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () {
          FocusScope.of(context).unfocus();
          Future.delayed(const Duration(milliseconds: 100), () {
            Future.microtask(() {
              if (!mounted) return;
              final sessions = ref.read(sessionHistoryProvider);
              final historyToReturn = sessions.map((session) {
                String fullAnswer = session.answer ?? '';
                if (fullAnswer.isEmpty && session.sections != null && session.sections!.isNotEmpty) {
                  final sectionContents = session.sections!.map((s) {
                    final title = s['title']?.toString() ?? '';
                    final content = s['content']?.toString() ?? '';
                    return title.isNotEmpty ? '### $title\n\n$content' : content;
                  }).where((text) => text.isNotEmpty).join('\n\n');
                  if (sectionContents.isNotEmpty) {
                    fullAnswer = sectionContents;
                  }
                }
                if (fullAnswer.isEmpty) {
                  fullAnswer = session.summary ?? '';
                }
                
                return {
                  'query': session.query,
                  'summary': session.summary ?? '',
                  'answer': fullAnswer,
                  'intent': session.intent ?? session.resultType,
                  'cardType': session.cardType ?? session.resultType,
                  'cards': session.products.map((p) => {
                    'title': p.title,
                    'price': p.price,
                    'rating': p.rating,
                    'images': p.images,
                    'source': p.source,
                  }).toList(),
                  'results': session.rawResults,
                  'sections': session.sections,
                  'sources': session.sources,
                  'followUpSuggestions': session.followUpSuggestions,
                  'imageUrl': session.imageUrl,
                };
              }).toList();
              
              final returnValue = widget.conversationId != null
                  ? {'history': historyToReturn, 'conversationId': widget.conversationId}
                  : historyToReturn;
              
              if (mounted) {
                Navigator.pop(context, returnValue);
              }
            });
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

  Widget _buildFollowUpBar() {
    return SafeArea(
      child: Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.search,
              color: AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _followUpController,
                focusNode: _followUpFocusNode,
                onSubmitted: (value) => _onFollowUpSubmitted(),
                autofocus: false,
                minLines: 1,
                maxLines: 4,
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary,
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

  Widget _buildScrollToBottomButton() {
    final bottomPosition = 80.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final buttonWidth = 44.0;
    final leftPosition = (screenWidth - buttonWidth) / 2;
    
    return ValueListenableBuilder<bool>(
      valueListenable: _showScrollButtonNotifier,
      builder: (context, showButton, child) {
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          bottom: showButton ? bottomPosition : -60.0,
          left: leftPosition,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showButton ? 1.0 : 0.0,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: showButton ? 1.0 : 0.8,
              child: Material(
                elevation: 8.0,
                shadowColor: Colors.black.withOpacity(0.3),
                shape: const CircleBorder(),
                color: AppColors.surface,
                child: InkWell(
                  onTap: _scrollToBottom,
                  borderRadius: BorderRadius.circular(24.0),
                  child: Container(
                    width: 44.0,
                    height: 44.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.border.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textPrimary,
                      size: 28.0,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          FocusScope.of(context).unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: Column(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final sessions = ref.watch(sessionHistoryProvider);
                        
                        
                        if (widget.isReplayMode && kDebugMode) {
                          debugPrint('📱 ClonarAnswerScreen BUILD (replay mode)');
                          debugPrint('   - Sessions count: ${sessions.length}');
                          for (int i = 0; i < sessions.length; i++) {
                            final s = sessions[i];
                            debugPrint('   - Session $i: "${s.query}" (finalized: ${s.isFinalized}, summary: ${s.summary?.length ?? 0} chars, answer: ${s.answer?.length ?? 0} chars)');
                          }
                        }
                        
                        // Memoization check
                        final currentHash = _computeSessionHash(sessions);
                        if (currentHash == _previousSessionHash && 
                            _previousSessions != null &&
                            _previousSessions!.length == sessions.length) {
                          // Use previous state
                        } else {
                          _previousSessionHash = currentHash;
                          _previousSessions = List<QuerySession>.from(sessions);
                        }
                        
                        // Handle initial conversation history
                        if (!widget.isReplayMode && 
                            widget.initialConversationHistory != null && 
                            widget.initialConversationHistory!.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            ref.read(sessionHistoryProvider.notifier).clear();
                            for (final sessionData in widget.initialConversationHistory!) {
                              final session = QuerySession(
                                sessionId: sessionData['sessionId'] as String?,
                                query: sessionData['query'] as String,
                                summary: sessionData['summary'] as String?,
                                answer: sessionData['answer'] as String?,
                                intent: sessionData['intent'] as String?,
                                cardType: sessionData['cardType'] as String?,
                                cards: (sessionData['cards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                                results: sessionData['results'] ?? [],
                                destinationImages: (sessionData['destination_images'] as List?)?.map((e) => e.toString()).toList() ?? [],
                                locationCards: (sessionData['locationCards'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [],
                                phase: QueryPhase.done, 
                                isStreaming: false,
                                isParsing: false,
                                isFinalized: true, 
                              );
                              ref.read(sessionHistoryProvider.notifier).addSession(session);
                            }
                          });
                        }
                        
                        return RepaintBoundary(
                          child: CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    if (index >= sessions.length) return const SizedBox.shrink();
                                    
                                    final session = sessions[index];
                                    
                                    return RepaintBoundary(
                                      key: ValueKey('session-$index-${session.query.hashCode}'),
                                      child: SessionRenderer(
                                        model: SessionRenderModel(
                                          sessionId: session.sessionId, 
                                          index: index,
                                          context: context,
                                          onFollowUpTap: (query, previousSession) {
                                            
                                            ref.read(followUpControllerProvider.notifier).handleFollowUp(
                                              query,
                                              previousSession,
                                            );
                                          },
                                          onHotelTap: (hotel) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => HotelDetailScreen(hotel: hotel),
                                              ),
                                            );
                                          },
                                          onProductTap: (product) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => ProductDetailScreen(product: product),
                                              ),
                                            );
                                          },
                                          onViewAllHotels: (query) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => HotelResultsScreen(query: query),
                                              ),
                                            );
                                          },
                                          onViewAllProducts: (query) {
                                            final currentSession = sessions.isNotEmpty ? sessions.last : null;
                                            if (currentSession != null && currentSession.products.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => ShoppingGridScreen(products: currentSession.products),
                                                ),
                                              );
                                            }
                                          },
                                          query: widget.query,
                                        ),
                                      ),
                                    );
                                  },
                                  childCount: sessions.length,
                                  addAutomaticKeepAlives: true,
                                  addRepaintBoundaries: false,
                                ),
                              ),
                              SliverPadding(
                                padding: const EdgeInsets.only(bottom: 100),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  _buildFollowUpBar(),
                ],
              ),
            ),
            _buildScrollToBottomButton(),
          ],
        ),
      ),
    );
  }
}

