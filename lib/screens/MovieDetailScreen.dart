import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/AppColors.dart';
import '../services/AgentService.dart';

class MovieDetailScreen extends StatefulWidget {
  final int movieId;
  final String? movieTitle; // Optional for initial display
  final int? initialTabIndex; // Optional: which tab to show initially (0=Overview, 1=Cast, 2=Showtimes, 3=Trailers, 4=Reviews)
  final bool? isInTheaters; // Optional: pass from SessionRenderer to ensure consistency

  const MovieDetailScreen({
    super.key,
    required this.movieId,
    this.movieTitle,
    this.initialTabIndex,
    this.isInTheaters,
  });

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _movieDetails;
  Map<String, dynamic>? _credits;
  Map<String, dynamic>? _videos;
  Map<String, dynamic>? _reviews;
  Map<String, dynamic>? _images;
  String? _reviewSummary;
  bool _isLoadingSummary = false;
  bool _isSummaryExpanded = false;
  bool _isLoading = true;
  String? _error;
  bool _isInTheaters = false;
  late TabController _tabController;
  int _selectedDateIndex = 0;
  String? _selectedTheater;
  String? _selectedShowtime;
  String? _selectedFormat;
  int _currentImageIndex = 0;
  late PageController _imagePageController;

  // Mock showtimes data (in production, this would come from a theater API)
  final List<Map<String, dynamic>> _theaters = [
    {
      'name': 'Megaplex Luxury Theatres at The Gateway',
      'address': '165 South Rio Grande Street, Salt Lake City, UT 84101',
      'distance': '0.2 mi',
      'showtimes': [
        {'time': '2:00 PM', 'format': 'Standard'},
        {'time': '3:00 PM', 'format': 'Standard'},
        {'time': '4:00 PM', 'format': 'Standard'},
        {'time': '3:30 PM', 'format': '3D'},
      ],
    },
    {
      'name': 'Brewvies Cinema Pub',
      'address': '677 South 200 West, Salt Lake City, UT 84101',
      'distance': '1.1 mi',
      'showtimes': [
        {'time': '4:00 PM', 'format': 'Standard'},
        {'time': '7:00 PM', 'format': 'Standard'},
        {'time': '10:00 PM', 'format': 'Standard'},
      ],
    },
    {
      'name': 'Cinemark Sugarhouse',
      'address': '2227 South Highland Drive, Salt Lake City, UT 84106',
      'distance': '4.1 mi',
      'showtimes': [
        {'time': '2:15 PM', 'format': 'Standard'},
        {'time': '4:00 PM', 'format': 'Standard'},
        {'time': '6:00 PM', 'format': 'Standard'},
      ],
    },
  ];

  final List<String> _dates = [
    'Today, Nov 24',
    'Tue, Nov 25',
    'Wed, Nov 26',
    'Thu, Nov 27',
    'Fri, Nov 28',
  ];

  @override
  void initState() {
    super.initState();
    // Initialize with default length, will be updated after loading movie data
    _tabController = TabController(length: 5, vsync: this);
    _imagePageController = PageController();
    _loadMovieData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _imagePageController.dispose();
    super.dispose();
  }

  Future<void> _loadMovieData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final details = await AgentService.getMovieDetails(widget.movieId);
      final credits = await AgentService.getMovieCredits(widget.movieId);
      final videos = await AgentService.getMovieVideos(widget.movieId);
      final reviews = await AgentService.getMovieReviews(widget.movieId);
      final images = await AgentService.getMovieImages(widget.movieId);
      
      // Debug: Log review count
      if (kDebugMode) {
        final reviewCount = (reviews['results'] as List?)?.length ?? 0;
        print('📝 Movie ${widget.movieId} reviews: $reviewCount reviews found');
      }

      // Check if movie is in theaters (prefer passed value from SessionRenderer, then backend flag, then calculate from release date)
      bool isInTheaters = widget.isInTheaters ?? details['isInTheaters'] == true;
      
      // Debug logging
      if (kDebugMode) {
        print('🎬 MovieDetailScreen: isInTheaters from widget = ${widget.isInTheaters}');
        print('🎬 MovieDetailScreen: isInTheaters from details = ${details['isInTheaters']}');
        print('🎬 MovieDetailScreen: release_date = ${details['release_date']}');
      }
      
      // Only calculate from release date if not already set from widget or backend
      if (!isInTheaters && widget.isInTheaters == null && details['release_date'] != null) {
        // Fallback: check release date
        try {
          final releaseDate = DateTime.parse(details['release_date']);
          final now = DateTime.now();
          final daysSinceRelease = now.difference(releaseDate).inDays;
          // Movie is "in theaters" if released within last 120 days or releasing in next 60 days
          // But NOT if it's way in the future (more than 60 days away)
          isInTheaters = (daysSinceRelease >= 0 && daysSinceRelease <= 120) || 
                         (daysSinceRelease < 0 && daysSinceRelease >= -60);
          // Additional check: if release date is more than 60 days in the future, it's not in theaters
          if (daysSinceRelease < -60) {
            isInTheaters = false;
          }
          
          if (kDebugMode) {
            print('🎬 MovieDetailScreen: daysSinceRelease = $daysSinceRelease');
            print('🎬 MovieDetailScreen: isInTheaters after date check = $isInTheaters');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error parsing release date: $e');
          }
          isInTheaters = false;
        }
      }
      
      // Force false if backend explicitly says false (override any fallback)
      if (details['isInTheaters'] == false) {
        isInTheaters = false;
        if (kDebugMode) {
          print('🎬 MovieDetailScreen: Forcing isInTheaters = false (backend override)');
        }
      }
      
      if (kDebugMode) {
        print('🎬 MovieDetailScreen: Final isInTheaters = $isInTheaters');
      }

      // Update tab controller length based on isInTheaters
      final tabLength = isInTheaters ? 5 : 4;
      TabController? newController;
      
      if (_tabController.length != tabLength) {
        // Create new controller before disposing old one
        newController = TabController(length: tabLength, vsync: this);
        if (kDebugMode) {
          print('🎬 MovieDetailScreen: Creating new TabController with length $tabLength (isInTheaters: $isInTheaters)');
        }
      }

      setState(() {
        _movieDetails = details;
        _credits = credits;
        _videos = videos;
        _reviews = reviews;
        _images = images;
        _isInTheaters = isInTheaters;
        _isLoading = false;
        
        // Update controller if needed
        if (newController != null) {
          _tabController.dispose();
          _tabController = newController;
        }
      });
      
      if (kDebugMode) {
        print('🎬 MovieDetailScreen: TabController length = ${_tabController.length}, isInTheaters = $_isInTheaters');
      }

      // Navigate to specific tab if requested (after state update)
      if (widget.initialTabIndex != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final maxTabs = isInTheaters ? 5 : 4;
          int adjustedIndex = widget.initialTabIndex!;
          
          // Adjust tab index if Showtimes is not available
          // Tab structure: 0=Overview, 1=Cast, 2=Showtimes(conditional), 3=Trailers, 4=Reviews
          // If Showtimes is missing: 0=Overview, 1=Cast, 2=Trailers, 3=Reviews
          if (!isInTheaters) {
            // If requesting Showtimes (index 2), default to Overview
            if (adjustedIndex == 2) {
              adjustedIndex = 0;
            }
            // If requesting Trailers (index 3) or Reviews (index 4), subtract 1
            else if (adjustedIndex >= 3) {
              adjustedIndex -= 1;
            }
          }
          
          // Validate the adjusted index
          if (adjustedIndex >= 0 && adjustedIndex < maxTabs && _tabController.length > adjustedIndex) {
            _tabController.animateTo(adjustedIndex);
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _getPosterUrl(String? posterPath) {
    if (posterPath == null || posterPath.isEmpty) return '';
    return 'https://image.tmdb.org/t/p/w500$posterPath';
  }


  List<String> _getMovieImagesList() {
    final List<String> images = [];
    
    // Add backdrops first (they look better for carousel)
    if (_images != null) {
      final backdrops = _images!['backdrops'] as List? ?? [];
      for (var backdrop in backdrops) {
        final filePath = backdrop['file_path']?.toString();
        if (filePath != null && filePath.isNotEmpty) {
          images.add('https://image.tmdb.org/t/p/w1280$filePath');
        }
      }
    }
    
    // Add main backdrop if available and not already in list
    if (_movieDetails != null) {
      final backdropPath = _movieDetails!['backdrop_path']?.toString();
      if (backdropPath != null && backdropPath.isNotEmpty) {
        final backdropUrl = 'https://image.tmdb.org/t/p/w1280$backdropPath';
        if (!images.contains(backdropUrl)) {
          images.insert(0, backdropUrl); // Add at the beginning
        }
      }
    }
    
    // Add posters if no backdrops available
    if (images.isEmpty && _images != null) {
      final posters = _images!['posters'] as List? ?? [];
      for (var poster in posters) {
        final filePath = poster['file_path']?.toString();
        if (filePath != null && filePath.isNotEmpty) {
          images.add('https://image.tmdb.org/t/p/w500$filePath');
        }
      }
    }
    
    // Fallback to main poster if no images
    if (images.isEmpty && _movieDetails != null) {
      final posterPath = _movieDetails!['poster_path']?.toString();
      if (posterPath != null && posterPath.isNotEmpty) {
        images.add('https://image.tmdb.org/t/p/w500$posterPath');
      }
    }
    
    return images;
  }

  Widget _buildImageCarousel(List<String> images) {
    if (images.isEmpty) {
      return Container(
        color: AppColors.surface,
        child: const Center(
          child: Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
        ),
      );
    }

    final hasMultipleImages = images.length > 1;

    return Stack(
      children: [
        PageView.builder(
          controller: _imagePageController,
          onPageChanged: (index) {
            setState(() {
              _currentImageIndex = index;
            });
          },
          itemCount: images.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => _viewImageFullscreen(images, index),
              child: Image.network(
                images[index],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppColors.surface,
                  child: const Icon(Icons.movie, size: 64, color: AppColors.textSecondary),
                ),
              ),
            );
          },
        ),
        // Page indicator dots at the bottom (only if multiple images)
        if (hasMultipleImages)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: images.length > 20
                      ? [
                          // Show first few dots
                          ...List.generate(
                            5,
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
                          // Show current indicator if it's beyond the first 5
                          if (_currentImageIndex >= 5 && _currentImageIndex < images.length - 5)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          // Show last few dots
                          ...List.generate(
                            5,
                            (index) {
                              final dotIndex = images.length - 5 + index;
                              return Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentImageIndex == dotIndex
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.4),
                                ),
                              );
                            },
                          ),
                        ]
                      : List.generate(
                          images.length,
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
            ),
          ),
        // Image counter (e.g., "1 / 3") at the top right
        if (hasMultipleImages)
          Positioned(
            top: 12,
            right: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentImageIndex + 1} / ${images.length}',
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

  void _viewImageFullscreen(List<String> images, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageFullscreenView(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _viewCastMemberFullscreen(String imageUrl, int personId, String name, String character) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CastMemberFullscreenView(
          imageUrl: imageUrl,
          personId: personId,
          name: name,
          character: character,
        ),
      ),
    );
  }

  String _getGenreNames(List<dynamic>? genres) {
    if (genres == null || genres.isEmpty) return '';
    return genres.map((g) => g['name']?.toString() ?? '').where((n) => n.isNotEmpty).join(' / ');
  }

  String _formatRuntime(int? minutes) {
    if (minutes == null) return '';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _isLoading || _error != null
          ? AppBar(
              backgroundColor: AppColors.background,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
        ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text('Error: $_error', style: const TextStyle(color: AppColors.textPrimary)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadMovieData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_movieDetails == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final movieDetails = _movieDetails!;
    final title = movieDetails['title']?.toString() ?? widget.movieTitle ?? 'Unknown Movie';
    final rating = (movieDetails['vote_average'] as num?)?.toDouble() ?? 0.0;
    final genres = _getGenreNames(movieDetails['genres'] as List?);
    final runtime = _formatRuntime(movieDetails['runtime'] as int?);
    final overview = movieDetails['overview']?.toString() ?? '';
    final releaseDate = movieDetails['release_date']?.toString() ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
    final posterUrl = _getPosterUrl(movieDetails['poster_path']?.toString());
    final imdbId = movieDetails['imdb_id']?.toString();
    
    // Get all movie images (backdrops and posters) for carousel
    final List<String> movieImages = _getMovieImagesList();

    return NestedScrollView(
      headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
        return [
          // App Bar with backdrop
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.background,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onPressed: () {},
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: () {},
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildImageCarousel(movieImages),
            ),
          ),

          // Movie Info Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if ((movieDetails['adult'] as bool?) == false) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PG',
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (year.isNotEmpty) ...[
                        Text(year, style: const TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                      ],
                      if (genres.isNotEmpty) ...[
                        Text(genres, style: const TextStyle(color: AppColors.textSecondary)),
                        const SizedBox(width: 8),
                      ],
                      if (runtime.isNotEmpty)
                        Text(runtime, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Ratings - Only show TMDB rating (not fake IMDb/Fandango)
                  if (rating > 0) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, size: 16, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                '${rating.toStringAsFixed(1)}/10',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'TMDB',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (imdbId != null) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _launchUrl('https://www.imdb.com/title/$imdbId'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'View on IMDb',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Tabs
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                isScrollable: false, // Ensure all tabs are visible
                tabs: [
                  const Tab(text: 'Overview'),
                  const Tab(text: 'Cast'),
                  if (_isInTheaters) const Tab(text: 'Showtimes'),
                  const Tab(text: 'Trailers & clips'),
                  const Tab(text: 'Reviews'),
                ],
              ),
            ),
          ),
        ];
      },
                      body: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(overview, posterUrl),
                          _buildCastTab(),
                          if (_isInTheaters) _buildShowtimesTab(),
                          _buildTrailersTab(),
                          _buildReviewsTab(),
                        ],
                      ),
    );
  }

  Widget _buildOverviewTab(String overview, String posterUrl) {
    final rating = (_movieDetails?['vote_average'] as num?)?.toDouble() ?? 0.0;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ TMDB Rating under poster (in Overview tab)
          if (rating > 0) ...[
            Row(
              children: [
                const Icon(Icons.star, size: 20, color: Colors.amber),
                const SizedBox(width: 8),
                Text(
                  '${rating.toStringAsFixed(1)}/10',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'TMDB',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          if (overview.isNotEmpty) ...[
            const Text(
              'Overview',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              overview,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
          ],
          // Core Details Section
          _buildCoreDetailsSection(),
          const SizedBox(height: 32),
          // Box Office & Reception Section
          _buildBoxOfficeSection(),
        ],
      ),
    );
  }

  Widget _buildCoreDetailsSection() {
    final crew = _credits?['crew'] as List? ?? [];
    final cast = _credits?['cast'] as List? ?? [];
    final movieDetails = _movieDetails ?? {};
    
    // Extract director
    final director = crew.firstWhere(
      (c) => c['job'] == 'Director',
      orElse: () => null,
    );
    
    // Extract composer
    final composer = crew.firstWhere(
      (c) => c['job'] == 'Original Music Composer' || c['job'] == 'Music',
      orElse: () => null,
    );
    
    // Extract top cast (starring)
    final topCast = cast.take(3).toList();
    
    // Extract runtime
    final runtime = _formatRuntime(movieDetails['runtime'] as int?);
    
    // Extract storyline (overview)
    final storyline = movieDetails['overview']?.toString() ?? '';
    
    if (director == null && topCast.isEmpty && runtime.isEmpty && storyline.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Core Details',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        if (director != null) ...[
          _buildDetailRow('Director', '${director['name']?.toString() ?? 'Unknown'}.'),
          const SizedBox(height: 12),
        ],
        if (topCast.isNotEmpty) ...[
          _buildDetailRow(
            'Starring',
            topCast.asMap().entries.map((entry) {
              final index = entry.key;
              final actor = entry.value;
              final name = actor['name']?.toString() ?? 'Unknown';
              final character = actor['character']?.toString();
              if (character != null && character.isNotEmpty) {
                return '$name (as $character)';
              }
              if (index == topCast.length - 1 && topCast.length > 1) {
                return 'and $name';
              }
              return name;
            }).join(', '),
          ),
          const SizedBox(height: 12),
        ],
        if (storyline.isNotEmpty) ...[
          _buildDetailRow('Storyline', '"$storyline"'),
          const SizedBox(height: 12),
        ],
        if (composer != null) ...[
          _buildDetailRow('Music', 'Composed by ${composer['name']?.toString() ?? 'Unknown'}.'),
          const SizedBox(height: 12),
        ],
        if (runtime.isNotEmpty) ...[
          _buildDetailRow('Running Time', 'Approximately $runtime.'),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxOfficeSection() {
    final movieDetails = _movieDetails ?? {};
    final budget = movieDetails['budget'] as int?;
    final revenue = movieDetails['revenue'] as int?;
    final rating = (movieDetails['vote_average'] as num?)?.toDouble() ?? 0.0;
    final voteCount = movieDetails['vote_count'] as int? ?? 0;
    
    // Format currency
    String formatCurrency(int? amount) {
      if (amount == null || amount == 0) return '';
      if (amount >= 1000000000) {
        return '\$${(amount / 1000000000).toStringAsFixed(2)}B';
      } else if (amount >= 1000000) {
        return '\$${(amount / 1000000).toStringAsFixed(2)}M';
      } else if (amount >= 1000) {
        return '\$${(amount / 1000).toStringAsFixed(2)}K';
      }
      return '\$$amount';
    }
    
    final budgetFormatted = formatCurrency(budget);
    final revenueFormatted = formatCurrency(revenue);
    
    // Generate box office content
    final List<String> boxOfficeItems = [];
    
    if (budgetFormatted.isNotEmpty || revenueFormatted.isNotEmpty) {
      if (budgetFormatted.isNotEmpty && revenueFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film had a production budget of $budgetFormatted and grossed $revenueFormatted worldwide.');
      } else if (budgetFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film had a production budget of $budgetFormatted.');
      } else if (revenueFormatted.isNotEmpty) {
        boxOfficeItems.add('**Opening:** The film grossed $revenueFormatted worldwide.');
      }
    }
    
    if (revenueFormatted.isNotEmpty && budgetFormatted.isNotEmpty && budget != null && budget > 0) {
      final profit = revenue! - budget;
      final profitFormatted = formatCurrency(profit);
      if (profit > 0) {
        boxOfficeItems.add('**Weekend Performance:** The film generated a profit of $profitFormatted.');
      }
    }
    
    if (rating > 0 && voteCount > 0) {
      final ratingText = rating >= 7.0 
          ? 'positive' 
          : rating >= 5.0 
              ? 'mixed' 
              : 'negative';
      boxOfficeItems.add('**Critical Response:** The film has received $ratingText reviews, with an average rating of ${rating.toStringAsFixed(1)}/10 based on ${voteCount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} votes.');
    }
    
    if (boxOfficeItems.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Box Office & Reception',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        ...boxOfficeItems.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildBoxOfficeItem(item),
        )),
      ],
    );
  }

  Widget _buildBoxOfficeItem(String text) {
    // Parse format: "**Label:** content"
    final match = RegExp(r'\*\*(.+?):\*\*\s*(.+)').firstMatch(text);
    if (match != null) {
      final label = match.group(1) ?? '';
      final content = match.group(2) ?? '';
      return RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: content,
              style: const TextStyle(
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      );
    }
    // Fallback if format doesn't match
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        color: AppColors.textPrimary,
        height: 1.5,
      ),
    );
  }

  Widget _buildCastTab() {
    final cast = _credits?['cast'] as List? ?? [];
    final crew = _credits?['crew'] as List? ?? [];
    final director = crew.firstWhere(
      (c) => c['job'] == 'Director',
      orElse: () => null,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (director != null) ...[
            const Text(
              'Director',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            _buildCastMember(director),
            const SizedBox(height: 24),
          ],
          const Text(
            'Cast',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...cast.take(10).map((actor) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildCastMember(actor),
              )),
        ],
      ),
    );
  }

  Widget _buildCastMember(Map<String, dynamic> person) {
    final personId = person['id'] as int?;
    final name = person['name'] ?? 'Unknown';
    final character = person['character'] ?? person['job'] ?? '';
    final profilePath = person['profile_path']?.toString();
    final imageUrl = profilePath != null && profilePath.isNotEmpty
        ? 'https://image.tmdb.org/t/p/w185$profilePath'
        : null;
    
    // Get full-size image URL for fullscreen view
    final fullSizeImageUrl = profilePath != null && profilePath.isNotEmpty
        ? 'https://image.tmdb.org/t/p/original$profilePath'
        : null;

    return Row(
      children: [
        GestureDetector(
          onTap: fullSizeImageUrl != null && personId != null
              ? () => _viewCastMemberFullscreen(fullSizeImageUrl, personId, name, character)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 60,
                      height: 60,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.person, color: AppColors.textSecondary),
                    ),
                  )
                : Container(
                    width: 60,
                    height: 60,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.person, color: AppColors.textSecondary),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (character.isNotEmpty)
                Text(
                  character,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildShowtimesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Location header
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Near Salt Lake City',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {},
                child: const Text('Choose area', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date selector
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _dates.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedDateIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDateIndex = index;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _dates[index],
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Theater listings
          ..._theaters.map((theater) => _buildTheaterCard(theater)),
        ],
      ),
    );
  }

  Widget _buildTheaterCard(Map<String, dynamic> theater) {
    final name = theater['name'] ?? 'Unknown Theater';
    final address = theater['address'] ?? '';
    final distance = theater['distance'] ?? '';
    final showtimes = theater['showtimes'] as List? ?? [];

    // Group showtimes by format
    final Map<String, List<Map<String, dynamic>>> groupedShowtimes = {};
    for (var st in showtimes) {
      final format = st['format'] ?? 'Standard';
      if (!groupedShowtimes.containsKey(format)) {
        groupedShowtimes[format] = [];
      }
      groupedShowtimes[format]!.add(st);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$distance · $address',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ...groupedShowtimes.entries.map((entry) {
            final format = entry.key;
            final times = entry.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  format,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: times.map((st) {
                    final time = st['time'] ?? '';
                    final isSelected = _selectedTheater == name &&
                        _selectedShowtime == time &&
                        _selectedFormat == format;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedTheater = name;
                          _selectedShowtime = time;
                          _selectedFormat = format;
                        });
                        _showTicketBookingDialog(name, time, format);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? AppColors.primary : AppColors.border,
                          ),
                        ),
                        child: Text(
                          time,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (format != groupedShowtimes.keys.toList().last) const SizedBox(height: 16),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _showTicketBookingDialog(String theater, String time, String format) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Buy tickets',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: AppColors.textSecondary),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _movieDetails?['title']?.toString() ?? widget.movieTitle ?? 'Unknown Movie',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _buildBookingDetailRow('Standard', format),
              _buildBookingDetailRow('Theater', theater),
              _buildBookingDetailRow('Date', _dates[_selectedDateIndex]),
              _buildBookingDetailRow('Time', time),
              _buildBookingDetailRow('Features', 'Atmos · Recliner'),
              const SizedBox(height: 24),
              const Text(
                'Buy from',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ..._buildTicketRetailers(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookingDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTicketRetailers() {
    final retailers = [
      {'name': 'Atom Tickets', 'url': 'https://www.atomtickets.com'},
      {'name': 'Fandango', 'url': 'https://www.fandango.com'},
      {'name': 'Flixster', 'url': 'https://www.flixster.com'},
      {'name': 'Megaplex Theatres', 'url': 'https://www.megaplextheatres.com'},
      {'name': 'MovieTickets.com', 'url': 'https://www.movietickets.com'},
    ];

    return retailers.map((retailer) {
      return InkWell(
        onTap: () => _launchUrl(retailer['url']!),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_movies, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  retailer['name']!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTrailersTab() {
    if (_videos == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    final videos = _videos?['results'] as List? ?? [];
    final trailers = videos.where((v) => 
      v['type'] == 'Trailer' && 
      (v['site'] == 'YouTube' || v['site'] == 'Vimeo')
    ).toList();
    
    // Also include teasers and clips
    final teasers = videos.where((v) => 
      (v['type'] == 'Teaser' || v['type'] == 'Clip') && 
      (v['site'] == 'YouTube' || v['site'] == 'Vimeo')
    ).toList();
    
    final allVideos = [...trailers, ...teasers];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allVideos.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.video_library_outlined, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'No trailers or clips available',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...allVideos.map((trailer) {
              final title = trailer['name'] ?? 'Trailer';
              final key = trailer['key']?.toString() ?? '';
              final site = trailer['site']?.toString() ?? 'YouTube';
              
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (site == 'YouTube') {
                          _playYouTubeVideo(key, title);
                        } else {
                          // For Vimeo, fallback to external link
                          final url = 'https://vimeo.com/$key';
                          _launchUrl(url);
                        }
                      },
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 200,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: 'https://img.youtube.com/vi/$key/maxresdefault.jpg',
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Center(
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: AppColors.surfaceVariant,
                                  child: const Icon(Icons.play_circle_outline, size: 64, color: AppColors.textSecondary),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // ✅ "Watch on YouTube" button
                    if (site == 'YouTube')
                      GestureDetector(
                        onTap: () {
                          _playYouTubeVideo(key, title);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.network(
                                'https://www.youtube.com/img/desktop/yt_1200.png',
                                height: 20,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.play_circle_outline,
                                  size: 20,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Watch on YouTube',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _playYouTubeVideo(String videoId, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => _YouTubeVideoPlayerDialog(
        videoId: videoId,
        title: title,
      ),
    );
  }

  Future<void> _loadReviewSummary() async {
    final reviews = _reviews?['results'] as List? ?? [];
    if (reviews.isEmpty) return;

    setState(() {
      _isLoadingSummary = true;
    });

    try {
      final movieTitle = _movieDetails?['title']?.toString();
      final summary = await AgentService.getMovieReviewsSummary(
        widget.movieId,
        reviews,
        movieTitle,
      );
      setState(() {
        _reviewSummary = summary;
        _isLoadingSummary = false;
      });
    } catch (e) {
      print('❌ Error loading review summary: $e');
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  Widget _buildReviewsTab() {
    if (_reviews == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    final reviews = _reviews?['results'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Review Summary Section (Collapsible)
          if (reviews.isNotEmpty) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _isSummaryExpanded = !_isSummaryExpanded;
                  // Load summary only when user expands for the first time
                  if (_isSummaryExpanded && _reviewSummary == null && !_isLoadingSummary) {
                    _loadReviewSummary();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.summarize, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Review Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          _isSummaryExpanded ? Icons.expand_less : Icons.expand_more,
                          color: AppColors.textSecondary,
                          size: 24,
                        ),
                      ],
                    ),
                    if (_isSummaryExpanded) ...[
                      const SizedBox(height: 12),
                      if (_isLoadingSummary)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        )
                      else if (_reviewSummary != null)
                        Text(
                          _reviewSummary!,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            height: 1.6,
                          ),
                        )
                      else
                        const Text(
                          'Loading summary...',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),
            const Text(
              'Individual Reviews',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (reviews.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.reviews_outlined, size: 64, color: AppColors.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'No reviews available yet',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reviews will appear here once they are available on TMDB.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...reviews.map((review) {
              final author = review['author']?.toString() ?? 'Anonymous';
              final content = review['content']?.toString() ?? '';
              final rating = review['author_details']?['rating']?.toDouble();
              final createdAt = review['created_at']?.toString() ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.surfaceVariant,
                          child: Text(
                            author.isNotEmpty ? author[0].toUpperCase() : '?',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                author,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (createdAt.isNotEmpty)
                                Text(
                                  _formatDate(createdAt),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (rating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        content,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// Full-screen YouTube video player dialog using WebView
class _YouTubeVideoPlayerDialog extends StatefulWidget {
  final String videoId;
  final String title;

  const _YouTubeVideoPlayerDialog({
    required this.videoId,
    required this.title,
  });

  @override
  State<_YouTubeVideoPlayerDialog> createState() => _YouTubeVideoPlayerDialogState();
}

class _YouTubeVideoPlayerDialogState extends State<_YouTubeVideoPlayerDialog> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;
  
  Future<void> _openInYouTube(String videoId) async {
    final Uri uri = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    // Create YouTube embed URL with proper parameters for mobile WebView
    // Using enablejsapi=1 and proper iframe parameters to avoid Error 153
    final embedUrl = 'https://www.youtube.com/embed/${widget.videoId}?autoplay=1&rel=0&enablejsapi=1&origin=${Uri.encodeComponent('https://www.youtube.com')}&playsinline=1';
    
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ WebView error: ${error.description}');
            // If embed fails (Error 153 or other), show fallback option
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        color: Colors.black,
        child: Stack(
          children: [
            // Video player
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    // Fallback button if embed fails (Error 153 or other issues)
                    if (_hasError)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.white,
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Unable to play video',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _openInYouTube(widget.videoId),
                                  icon: const Icon(Icons.play_circle_outline, size: 24),
                                  label: const Text('Watch on YouTube'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // Title
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverAppBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

// Full screen image viewer class
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
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1}/${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: PageView.builder(
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
              child: Image.network(
                widget.images[index],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 64,
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
}

class _CastMemberFullscreenView extends StatefulWidget {
  final String imageUrl;
  final int personId;
  final String name;
  final String character;

  const _CastMemberFullscreenView({
    required this.imageUrl,
    required this.personId,
    required this.name,
    required this.character,
  });

  @override
  State<_CastMemberFullscreenView> createState() => _CastMemberFullscreenViewState();
}

class _CastMemberFullscreenViewState extends State<_CastMemberFullscreenView> {
  Map<String, dynamic>? _personDetails;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPersonDetails();
  }

  Future<void> _loadPersonDetails() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final personDetails = await AgentService.getPersonDetails(widget.personId);
      if (mounted) {
        setState(() {
          _personDetails = personDetails;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading person details for ID ${widget.personId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final biography = _personDetails?['biography']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen image
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 64,
                    ),
                  );
                },
              ),
            ),
          ),
          // Close button at top left
          SafeArea(
            child: Positioned(
              top: 8,
              left: 8,
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
          // Overview at the bottom
          if (biography.isNotEmpty || _isLoading)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.character.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.character,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ],
                    if (_isLoading) ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ] else if (biography.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        biography,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

