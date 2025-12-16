// ✅ PHASE 10: Flutter UI Load Simulation
// Simulates heavy UI load to test for jank, freezes, and exceptions

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../lib/models/query_session_model.dart';
import '../lib/providers/session_history_provider.dart';
import '../lib/providers/streaming_text_provider.dart';
import '../lib/providers/follow_up_engine_provider.dart';

/// ✅ PHASE 10: Stress test widget that simulates heavy load
class UIStressTestScreen extends ConsumerStatefulWidget {
  const UIStressTestScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<UIStressTestScreen> createState() => _UIStressTestScreenState();
}

class _UIStressTestScreenState extends ConsumerState<UIStressTestScreen> {
  int _sessionCount = 0;
  int _followUpCount = 0;
  int _scrollEvents = 0;
  bool _isRunning = false;
  DateTime? _startTime;

  /// ✅ PHASE 10: Generate 100 session objects
  void _generateSessions() {
    if (!mounted) return;
    
    final sessions = <QuerySession>[];
    for (int i = 0; i < 100; i++) {
      sessions.add(QuerySession(
        query: 'Test query $i',
        summary: 'This is a test summary for session $i. ' * 10, // Long summary
        intent: ['shopping', 'hotels', 'places', 'movies', 'restaurants'][i % 5],
        cards: List.generate(20, (j) => {
          return {
            'title': 'Card $j for session $i',
            'description': 'Description ' * 50,
            'price': (100 + j * 10).toString(),
            'rating': (4.0 + (j % 10) / 10).toString(),
            'images': List.generate(5, (k) => 'https://example.com/image$k.jpg'),
          };
        }),
        results: List.generate(10, (j) => {
          return {
            'type': 'product',
            'name': 'Result $j',
            'data': 'Data ' * 100,
          };
        }),
        destinationImages: List.generate(20, (j) => 'https://example.com/dest$j.jpg'),
        locationCards: List.generate(10, (j) => {
          return {
            'title': 'Location $j',
            'description': 'Location description ' * 30,
            'latitude': 1.0 + j * 0.1,
            'longitude': 103.0 + j * 0.1,
          };
        }),
        isStreaming: false,
        isParsing: false,
        timestamp: DateTime.now().subtract(Duration(minutes: i)),
      ));
    }
    
    // Add all sessions
    for (final session in sessions) {
      ref.read(sessionHistoryProvider.notifier).addSession(session);
    }
    
    setState(() {
      _sessionCount = sessions.length;
    });
  }

  /// ✅ PHASE 10: Generate 50 follow-ups
  void _generateFollowUps() {
    if (!mounted) return;
    
    final sessions = ref.read(sessionHistoryProvider);
    if (sessions.isEmpty) return;
    
    final followUps = [
      'show me cheaper ones',
      'what about alternatives',
      'tell me more',
      'show on map',
      'compare prices',
      'show reviews',
      'best time to visit',
      'how to get there',
      'what are the amenities',
      'show similar items',
    ];
    
    for (int i = 0; i < 50 && i < sessions.length; i++) {
      final session = sessions[i % sessions.length];
      final followUp = followUps[i % followUps.length];
      
      // Trigger follow-up engine
      ref.read(followUpEngineProvider(session));
    }
    
    setState(() {
      _followUpCount = 50;
    });
  }

  /// ✅ PHASE 10: Simulate rapid scrolling
  void _simulateRapidScrolling() {
    if (!mounted) return;
    
    final scrollNotifier = ref.read(scrollProvider.notifier);
    int events = 0;
    
    final timer = Stream.periodic(const Duration(milliseconds: 50), (i) {
      if (events >= 100) return null; // Stop after 100 events
      events++;
      scrollNotifier.scrollToBottom();
      return events;
    }).listen((event) {
      if (event != null && mounted) {
        setState(() {
          _scrollEvents = event;
        });
      }
    });
    
    Future.delayed(const Duration(seconds: 10), () {
      timer.cancel();
    });
  }

  /// ✅ PHASE 10: Run all stress tests
  void _runStressTest() {
    if (_isRunning) return;
    
    setState(() {
      _isRunning = true;
      _startTime = DateTime.now();
      _sessionCount = 0;
      _followUpCount = 0;
      _scrollEvents = 0;
    });
    
    // Clear existing sessions
    ref.read(sessionHistoryProvider.notifier).clear();
    ref.read(streamingTextProvider.notifier).reset();
    
    // Run tests sequentially to avoid overwhelming
    Future.delayed(const Duration(milliseconds: 100), () {
      _generateSessions();
    });
    
    Future.delayed(const Duration(milliseconds: 500), () {
      _generateFollowUps();
    });
    
    Future.delayed(const Duration(milliseconds: 1000), () {
      _simulateRapidScrolling();
    });
    
    // Stop after 30 seconds
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionHistoryProvider);
    final elapsed = _startTime != null 
        ? DateTime.now().difference(_startTime!).inSeconds 
        : 0;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('UI Stress Test'),
      ),
      body: Column(
        children: [
          // Stats panel
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('📊 Stats:', style: Theme.of(context).textTheme.titleLarge),
                Text('Sessions: $_sessionCount'),
                Text('Follow-ups: $_followUpCount'),
                Text('Scroll events: $_scrollEvents'),
                Text('Elapsed: ${elapsed}s'),
                Text('Status: ${_isRunning ? "Running" : "Stopped"}'),
              ],
            ),
          ),
          
          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isRunning ? null : _runStressTest,
                  child: const Text('Run Stress Test'),
                ),
                ElevatedButton(
                  onPressed: () {
                    ref.read(sessionHistoryProvider.notifier).clear();
                    setState(() {
                      _sessionCount = 0;
                      _followUpCount = 0;
                      _scrollEvents = 0;
                    });
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          
          // Session list
          Expanded(
            child: ListView.builder(
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(session.query),
                    subtitle: Text('${session.cards.length} cards, ${session.locationCards.length} locations'),
                    trailing: Text(session.intent ?? 'unknown'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

