import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:isolate';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Persona.dart';
import '../models/Collage.dart';
import '../services/ApiService.dart' as api;
import '../utils/ImageHelper.dart';
import 'AddToListPage.dart';
import 'CreatePersonaPage.dart';
import 'PersonaDetailPage.dart';
import 'CollageEditorPage.dart';
import 'CollageViewPage.dart';

// Isolate functions for heavy JSON parsing operations
Future<List<Persona>> _parsePersonasInIsolate(String jsonString) async {
  return await compute(_parsePersonasFromJson, jsonString);
}

Future<List<Collage>> _parseCollagesInIsolate(String jsonString) async {
  return await compute(_parseCollagesFromJson, jsonString);
}

Future<Map<String, dynamic>?> _parseProfileInIsolate(String jsonString) async {
  return await compute(_parseProfileFromJson, jsonString);
}

// Isolate-compatible parsing functions
List<Persona> _parsePersonasFromJson(String jsonString) {
  try {
    final data = jsonDecode(jsonString);
    if (data['success'] == true && data['data'] is List) {
      final List<Persona> personas = [];
      for (final item in data['data'] as List) {
        try {
          if (item is Map<String, dynamic>) {
            personas.add(Persona.fromJson(item));
          } else {
            print('Invalid persona item type: ${item.runtimeType}');
          }
        } catch (e) {
          print('Error parsing individual persona: $e');
          print('Persona data: $item');
          // Continue with next item instead of failing completely
        }
      }
      return personas;
    }
    return [];
  } catch (e) {
    print('Error parsing personas: $e');
    print('JSON string: $jsonString');
    return [];
  }
}

List<Collage> _parseCollagesFromJson(String jsonString) {
  try {
    print('🔍 Raw collages response: $jsonString');
    final data = jsonDecode(jsonString);
    print('🔍 Parsed collages data: $data');
    
    if (data['success'] == true && data['data'] != null) {
      // Backend returns { success: true, data: { collages: [...], pagination: {...} } }
      final responseData = data['data'] as Map<String, dynamic>;
      final collagesList = responseData['collages'] as List?;
      
      if (collagesList != null) {
        final collages = collagesList
            .map((json) {
              print('🔍 Parsing collage: $json');
              return Collage.fromJson(json);
            })
            .toList();
        print('🔍 Successfully parsed ${collages.length} collages');
        return collages;
      } else {
        print('🔍 No collages array in response data');
        return [];
      }
    } else {
      print('🔍 Invalid response format - success: ${data['success']}, data type: ${data['data'].runtimeType}');
    }
    return [];
  } catch (e) {
    print('❌ Error parsing collages: $e');
    return [];
  }
}

Map<String, dynamic>? _parseProfileFromJson(String jsonString) {
  try {
    final data = jsonDecode(jsonString);
    if (data['success'] == true && data['data'] != null) {
      return data['data'] as Map<String, dynamic>;
    }
    return null;
  } catch (e) {
    print('Error parsing profile: $e');
    return null;
  }
}

class DataCache {
  static bool accountDataLoaded = false;
  static List<dynamic> personas = [];
  static List<dynamic> collages = [];
  static Map<String, dynamic>? profile;
  
  // Safety method to clear corrupted cache
  static void clearCache() {
    accountDataLoaded = false;
    personas.clear();
    collages.clear();
    profile = null;
    print("🧹 DataCache cleared due to corruption");
  }
}

// State management enums
enum AccountState { loading, loaded, error }
enum DataType { profile, personas, collages }

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

  // State management with lazy initialization
  late final ValueNotifier<AccountState> _accountState;
  late final ValueNotifier<Map<String, dynamic>?> _profile;
  late final ValueNotifier<List<Persona>> _personas;
  late final ValueNotifier<List<Collage>> _collages;
  late final ValueNotifier<String?> _error;
  late final ValueNotifier<Set<DataType>> _loadingData;
  
  // Prevent multiple data fetches
  bool _hasLoadedOnce = false;
  
  // Cached futures to prevent redundant API calls
  late final Future<List<Persona>> _personasFuture;
  late final Future<List<Collage>> _collagesFuture;
  late final Future<Map<String, dynamic>?> _profileFuture;
  
  // Memoized data to prevent recalculation
  Map<String, int>? _filterCountCache;
  List<String>? _cachedFilters;

  // API configuration
  static const String apiUrl = 'http://10.0.2.2:4000/api';

  @override
  void initState() {
    super.initState();
    
    // Initialize ValueNotifiers lazily
    _accountState = ValueNotifier(AccountState.loading);
    _profile = ValueNotifier(null);
    _personas = ValueNotifier([]);
    _collages = ValueNotifier([]);
    _error = ValueNotifier(null);
    _loadingData = ValueNotifier({});
    
    _tabController = TabController(length: 3, vsync: this);
    
    // Check if we should switch to a specific tab
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['tab'] == 'collages') {
        _tabController.animateTo(2); // Switch to Collages tab (index 2)
        _selectedFilter = 'Posted'; // Set to Posted filter
        print('🎯 Switched to Collages tab with Posted filter');
        // Force refresh data when navigating to collages tab
        _refreshData();
      }
    });

    _tabController.addListener(() {
      if (mounted) {
      setState(() {
          if (_tabController.index == 1) {
          _selectedFilter = 'Vault';
          } else if (_tabController.index == 2) {
          _selectedFilter = 'Posted';
          } else {
          _selectedFilter = 'All Items';
        }
      });
      }
    });

    // Initialize lazy futures
    _personasFuture = _fetchPersonasLazy();
    _collagesFuture = _fetchCollagesLazy();
    _profileFuture = _fetchProfileLazy();

    // PERFORMANCE FIX: Only load data if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_hasLoadedOnce) {
        _hasLoadedOnce = true;
        await _fetchAccountData();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _accountState.dispose();
    _profile.dispose();
    _personas.dispose();
    _collages.dispose();
    _error.dispose();
    _loadingData.dispose();
    super.dispose();
  }

  // Optimized lazy loading methods using isolates for heavy parsing
  Future<List<Persona>> _fetchPersonasLazy() async {
    try {
      final token = await _getToken();
      if (token == null) return [];
      
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/personas'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        // Move JSON parsing to isolate to prevent UI blocking
        return await _parsePersonasInIsolate(response.body);
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('Personas lazy fetch error: $e');
      return [];
    }
  }

  // 🔄 Force persona list refresh when coming back from detail
  Future<void> _refreshPersonasAfterEdit() async {
    try {
      final token = await _getToken();
      if (token == null) return;
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/personas'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      if (response.statusCode == 200) {
        final personas = await _parsePersonasInIsolate(response.body);
        if (mounted) {
          // 🔁 Force notify by assigning a new list instance
          _personas.value = List<Persona>.from(personas);
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error refreshing personas after edit: $e');
    }
  }

  Future<List<Collage>> _fetchCollagesLazy() async {
    try {
      final token = await _getToken();
      if (token == null) return [];
      
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/collages'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        // Move JSON parsing to isolate to prevent UI blocking
        return await _parseCollagesInIsolate(response.body);
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('Collages lazy fetch error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _fetchProfileLazy() async {
    try {
      final token = await _getToken();
      if (token == null) return null;
      
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/auth/me'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        // Move JSON parsing to isolate to prevent UI blocking
        return await _parseProfileInIsolate(response.body);
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('Profile lazy fetch error: $e');
      return null;
    }
  }

  // Backend integration methods
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('auth_token');
      
      // 🔥 Dev Mode Bypass: Allow fake user even without token
      if (token == null || token.isEmpty || token == 'test-token') {
        debugPrint('🧪 Dev Mode: Using fake token for testing');
        token = 'dev-mode-token';
      }
      
      return token;
    } catch (e) {
      if (kDebugMode) print('Token retrieval error: $e');
      // Even on error, return fake token in dev mode
      debugPrint('🧪 Dev Mode: Using fake token due to error');
      return 'dev-mode-token';
    }
  }

  Future<void> _fetchAccountData() async {
    if (!mounted) return;
    _accountState.value = AccountState.loading;
    _error.value = null;

    try {
      final token = await _getToken();
      if (token == null) {
        _error.value = 'Authentication required';
        _accountState.value = AccountState.error;
        return;
      }

      // PERFORMANCE FIX: Add small delay to prevent UI blocking
      await Future.delayed(const Duration(milliseconds: 5));

      // Run all fetches in parallel
      await Future.wait([
        _fetchProfile(token),
        _fetchPersonas(token),
        _fetchCollages(token),
      ]);

      if (!mounted) return;
      _accountState.value = AccountState.loaded;
    } catch (e) {
      print('Error loading account data: $e');
      if (mounted) {
        _error.value = 'Failed to load account data: $e';
        _accountState.value = AccountState.error;
      }
    }
  }

  Future<void> _fetchProfile(String token) async {
    if (!mounted) return;
    _loadingData.value = {..._loadingData.value, DataType.profile};
    
    try {
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/auth/me'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(
        const Duration(seconds: 3), // Reduced timeout
        onTimeout: () {
          print('Profile fetch timeout');
          return http.Response('{"success": false, "error": "timeout"}', 408);
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          if (!mounted) return;
          _profile.value = data['data'];
        }
      }
    } catch (e) {
      if (kDebugMode) print('Profile fetch error: $e');
    } finally {
      if (!mounted) return;
      _loadingData.value = _loadingData.value.where((type) => type != DataType.profile).toSet();
    }
  }

  Future<void> _fetchPersonas(String token) async {
    if (!mounted) return;
    _loadingData.value = {..._loadingData.value, DataType.personas};
    
    try {
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/personas'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(
        const Duration(seconds: 3), // Reduced timeout
        onTimeout: () {
          print('Personas fetch timeout');
          return http.Response('{"success": false, "error": "timeout"}', 408);
        },
      );

      if (response.statusCode == 200) {
        // Move JSON parsing to isolate to prevent UI blocking
        final personas = await _parsePersonasInIsolate(response.body);
        if (!mounted) return;
        _personas.value = personas;
      }
    } catch (e) {
      if (kDebugMode) print('Personas fetch error: $e');
    } finally {
      if (!mounted) return;
      _loadingData.value = _loadingData.value.where((type) => type != DataType.personas).toSet();
    }
  }

  Future<void> _fetchCollages(String token) async {
    if (!mounted) return;
    _loadingData.value = {..._loadingData.value, DataType.collages};
    
    try {
      final response = await api.safeRequest(
        http.get(
          Uri.parse('$apiUrl/collages'),
          headers: {'Authorization': 'Bearer $token'},
        ),
      ).timeout(
        const Duration(seconds: 3), // Reduced timeout
        onTimeout: () {
          print('Collages fetch timeout');
          return http.Response('{"success": false, "error": "timeout"}', 408);
        },
      );

      if (response.statusCode == 200) {
        // Move JSON parsing to isolate to prevent UI blocking
        final collages = await _parseCollagesInIsolate(response.body);
        if (!mounted) return;
        
        print('📋 AccountScreen - Loaded collages: ${collages.length}');
        for (int i = 0; i < collages.length; i++) {
          print('📋 Collage $i: title="${collages[i].title}", isPublished=${collages[i].isPublished}');
        }
        
        _collages.value = collages;
      }
    } catch (e) {
      if (kDebugMode) print('Collages fetch error: $e');
    } finally {
      if (!mounted) return;
      _loadingData.value = _loadingData.value.where((type) => type != DataType.collages).toSet();
    }
  }

  void _refreshData() {
    _fetchAccountData();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ValueListenableBuilder<AccountState>(
        valueListenable: _accountState,
        builder: (context, state, child) {
          if (state == AccountState.loading) {
            return _buildLoadingState();
          } else if (state == AccountState.error) {
            return _buildErrorState();
          }
          
          return NestedScrollView(
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
                        Tab(text: "Collages"),
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
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading your account...'),
        ],
      ),
    );
  }

  // Extracted const widgets for better performance
  static const Widget _loadingIndicator = Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Loading your account...'),
      ],
    ),
  );

  static const Widget _errorIcon = Icon(
    Icons.error_outline,
    size: 64,
    color: AppColors.error,
  );

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _errorIcon,
          const SizedBox(height: 16),
          ValueListenableBuilder<String?>(
            valueListenable: _error,
            builder: (context, error, child) {
              return Text(
                error ?? 'Something went wrong',
                style: AppTypography.title2,
                textAlign: TextAlign.center,
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Please check your connection and try again',
            style: AppTypography.body2,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _refreshData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return RepaintBoundary(
      child: ValueListenableBuilder<Map<String, dynamic>?>(
        valueListenable: _profile,
        builder: (context, profile, child) {
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
                      backgroundImage: profile?['avatar'] != null 
                          ? NetworkImage(profile!['avatar'])
                          : null,
                      child: profile?['avatar'] == null
                          ? const Icon(
                  Icons.person,
                  size: 30,
                  color: AppColors.primary,
                            )
                          : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                            profile?['name'] ?? 'User',
                      style: AppTypography.body1.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                            profile?['bio'] ?? 'Welcome to Clonar!',
                      style: AppTypography.body2.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                      icon: const Icon(
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
                RepaintBoundary(
                  child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
                      _StatItem(label: "Uploads", value: "${_collages.value.length}"),
                      _StatItem(label: "Personas", value: "${_personas.value.length}"),
                      _StatItem(label: "Collections", value: "0"),
            ],
          ),
                ),
        ],
      ),
    );
        },
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
                  // Search functionality can be added here if needed
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
    return ValueListenableBuilder<List<Persona>>(
      valueListenable: _personas,
      builder: (context, personas, child) {
        return ValueListenableBuilder<List<Collage>>(
          valueListenable: _collages,
          builder: (context, collages, child) {
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
                    final count = _getFilterCount(filter, personas, collages);
            
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
          },
        );
      },
    );
  }

  // Memoized filter count calculation to prevent recalculation
  int _getFilterCount(String filterName, List<Persona> personas, List<Collage> collages) {
    // Use cache key to prevent recalculation
    final cacheKey = '${_tabController.index}_${personas.length}_${collages.length}_$filterName';
    
    if (_filterCountCache != null && _filterCountCache!.containsKey(cacheKey)) {
      return _filterCountCache![cacheKey]!;
    }
    
    int count;
    if (_tabController.index == 1) { // Persona tab
      switch (filterName) {
        case 'Vault':
          count = personas.length; // All personas are "Vault" for now
          break;
        case 'Collab':
          count = 0; // No collab personas for now
          break;
        default:
          count = personas.length;
      }
    } else if (_tabController.index == 2) { // Uploads tab
      switch (filterName) {
        case 'Posted':
          count = collages.where((c) => c.isPublished).length;
          break;
        case 'Under way':
          count = collages.where((c) => !c.isPublished).length;
          break;
        default:
          count = collages.length;
      }
    } else { // Collections tab
      switch (filterName) {
        case 'All Items':
          count = collages.length;
          break;
        case 'Favorites':
          count = 0; // No favorites for now
          break;
        case 'Saved':
          count = collages.length;
          break;
        case 'Created by You':
          count = collages.length;
          break;
        default:
          count = collages.length;
      }
    }
    
    // Cache the result
    _filterCountCache ??= {};
    _filterCountCache![cacheKey] = count;
    return count;
  }

  Widget _buildPinsGrid() {
    return ValueListenableBuilder<List<Collage>>(
      valueListenable: _collages,
      builder: (context, collages, child) {
        if (collages.isEmpty) {
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
                  'No collections yet',
              style: AppTypography.title2,
            ),
            SizedBox(height: 8),
            Text(
                  'Start creating your collections!',
              style: AppTypography.body2,
            ),
          ],
        ),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
          cacheExtent: 1000, // Cache 1000 pixels worth of items
          addRepaintBoundaries: true, // Enable repaint boundaries for each item
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
          itemCount: collages.length,
      itemBuilder: (context, index) {
            final collage = collages[index];
            return RepaintBoundary(
              child: _buildCollageCard(collage, key: ValueKey('collage_${collage.id}_$index')),
            );
          },
        );
      },
    );
  }

  Widget _buildBoardsGrid() {
    return ValueListenableBuilder<List<Persona>>(
      valueListenable: _personas,
      builder: (context, personas, child) {
        if (personas.isEmpty) {
          return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                const Icon(
              Icons.folder_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
                const SizedBox(height: 16),
                const Text(
              'No personas yet',
              style: AppTypography.title2,
            ),
                const SizedBox(height: 8),
                const Text(
              'Create your first persona to get started',
              style: AppTypography.body1,
            ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreatePersonaPage(),
                      ),
                    ).then((result) {
                      if (result == true) {
                        _refreshData();
                      }
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Create First Persona'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
          ],
        ),
      );
    }
    
    return GridView.builder(
      padding: const EdgeInsets.all(16),
          cacheExtent: 1000, // Cache 1000 pixels worth of items
          addRepaintBoundaries: true, // Enable repaint boundaries for each item
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
          itemCount: personas.length,
      itemBuilder: (context, index) {
            final persona = personas[index];
            return RepaintBoundary(
              child: _buildPersonaCard(persona, key: ValueKey('persona_${persona.id}_$index')),
            );
          },
        );
      },
    );
  }

  Widget _buildCollagesGrid() {
    return ValueListenableBuilder<List<Collage>>(
      valueListenable: _collages,
      builder: (context, collages, child) {
        // Filter collages based on selected filter
        List<Collage> filteredCollages = collages;
        print('🔍 AccountScreen - Filtering collages:');
        print('🔍 Selected filter: $_selectedFilter');
        print('🔍 Total collages: ${collages.length}');
        
        if (_selectedFilter == 'Posted') {
          filteredCollages = collages.where((c) => c.isPublished).toList();
          print('🔍 Posted filter - Published collages: ${filteredCollages.length}');
        } else if (_selectedFilter == 'Under way') {
          filteredCollages = collages.where((c) => !c.isPublished).toList();
          print('🔍 Under way filter - Unpublished collages: ${filteredCollages.length}');
        } else {
          print('🔍 No filter - All collages: ${filteredCollages.length}');
        }
    
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
                    ).then((_) => _refreshData());
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
          cacheExtent: 1000, // Cache 1000 pixels worth of items
          addRepaintBoundaries: true, // Enable repaint boundaries for each item
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: filteredCollages.length + 1, // +1 for create button
      itemBuilder: (context, index) {
            if (index == 0) {
              // Create new collage button at the first position
              return RepaintBoundary(
                child: const _CreateCollageCard(key: ValueKey('create_collage_button')),
              );
            }
            // Adjust collage index since create button is at index 0
            final collage = filteredCollages[index - 1];
            return RepaintBoundary(
              child: _buildCollageCard(collage, key: ValueKey('collage_${collage.id}_${index - 1}')),
            );
          },
        );
      },
    );
  }


  Widget _buildCollageCard(Collage collage, {Key? key}) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CollageViewPage(collage: collage),
          ),
        ).then((_) => _refreshData());
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
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
                child: collage.coverImageUrl != null && collage.coverImageUrl!.isNotEmpty
                    ? Image.network(
                        ImageHelper.resolve(collage.coverImageUrl!),
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: AppColors.surfaceVariant,
                            child: const Center(
                              child: Icon(
                                Icons.auto_awesome_mosaic,
                                color: Colors.grey,
                                size: 32,
                              ),
                            ),
                          );
                        },
                      )
                    : Container(
                        color: AppColors.surfaceVariant,
                        child: const Center(
                          child: Icon(
                            Icons.auto_awesome_mosaic,
                            color: Colors.grey,
                            size: 32,
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
                    collage.title,
                    style: AppTypography.title2.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonaCard(Persona persona, {Key? key}) {
    return GestureDetector(
              onTap: () async {
                final result = await Navigator.push(
          context,
          MaterialPageRoute(
                    builder: (context) => PersonaDetailPage(persona: persona),
          ),
        );

                if (result == true && mounted) {
                  await _refreshPersonasAfterEdit();
                }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
                      offset: const Offset(0, 4),
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
                        child: persona.imageUrl != null
                        ? Image.network(
                                persona.imageUrl!,
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
                              persona.title,
                    style: AppTypography.title2.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
                ).then((_) => _refreshData());
              },
            ),
            _buildCreateOption(
              icon: Icons.folder,
              title: 'Create Persona',
              subtitle: 'Organize anything',
              onTap: () {
                Navigator.pop(context);
              Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CreatePersonaPage(),
                  ),
                ).then((result) {
                  if (result == true) {
                    _refreshData();
                  }
                });
              },
            ),
            _buildCreateOption(
              icon: Icons.auto_awesome_mosaic,
              title: 'Create Collage',
              subtitle: 'Design your perfect collage',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CollageEditorPage(),
                  ),
                ).then((_) => _refreshData());
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

// Extracted const widget for better performance
class _CreateCollageCard extends StatelessWidget {
  const _CreateCollageCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => const CollageEditorPage(),
          ),
        ).then((result) {
          if (result == true) {
            // ✅ Refresh data and switch to Collages tab
            final parent = context.findAncestorStateOfType<_AccountScreenState>();
            parent?._tabController.animateTo(2); // switch to Collages tab
            parent?._refreshData();
            
            // ✅ Show success feedback
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Collage added to Posted!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
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
}