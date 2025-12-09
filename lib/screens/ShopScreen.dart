import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../services/AgentService.dart';
import '../core/api_client.dart';
import 'ShoppingResultsScreen.dart';
import 'TravelScreen.dart';

class ShopScreen extends StatefulWidget {
  final String? imageUrl;
  final String? preloadedQuery;

  const ShopScreen({
    super.key,
    this.imageUrl,
    this.preloadedQuery,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isVoiceModeActive = false; // Track voice mode state
  bool _hasText = false; // Track if text field has content
  bool _isListening = false; // Track if currently listening
  bool _isSpeechAvailable = false; // Track if speech recognition is available
  String _lastWords = ''; // Store last recognized words
  bool _isWebSearchMode = false; // Track if web search mode is active
  String? _uploadedImageUrl; // ✅ Store uploaded image URL in state
  
  // Autocomplete suggestions
  List<String> _suggestions = [];
  bool _isLoadingSuggestions = false;
  Timer? _debounceTimer;
  
  // ✅ FIX 1: Flags to prevent recursion & rebuild storm
  bool _isProgrammaticUpdate = false;
  bool _isSuggestionRequestOngoing = false;

  @override
  void initState() {
    super.initState();
    // Pre-load query if provided
    if (widget.preloadedQuery != null) {
      _searchController.text = widget.preloadedQuery!;
      _hasText = widget.preloadedQuery!.isNotEmpty;
    }
    // Pre-load image URL if provided
    if (widget.imageUrl != null) {
      _uploadedImageUrl = widget.imageUrl;
    }
    // ✅ FIX 2: Modified listener to STOP firing during speech + rapid typing
    _searchController.addListener(() {
      if (_isProgrammaticUpdate) return; // ⛔ prevents infinite loops
      
      final text = _searchController.text.trim();
      final hasTextNow = text.isNotEmpty;
      
      if (_hasText != hasTextNow) {
        setState(() {
          _hasText = hasTextNow;
        });
      }
      
      // Debounce autocomplete
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted && !_isSuggestionRequestOngoing && text.length >= 2) {
          _fetchSuggestions(text);
        }
      });
    });
    // Listen to focus changes
    _searchFocusNode.addListener(() {
      setState(() {
        // Update state when focus changes to show/hide voice controls
      });
    });
    // Ensure search field is not focused when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.unfocus();
      _initializeSpeech();
    });
  }

  Future<void> _initializeSpeech() async {
    try {
      bool available = await _speech.initialize(
        onStatus: (status) {
          setState(() {
            _isListening = status == 'listening';
          });
          if (status == 'done' || status == 'notListening') {
            // When speech recognition stops, update the text field
            if (_lastWords.isNotEmpty && _isVoiceModeActive) {
              // ✅ FIX 4: Prevent speech-to-text from refiring listener infinitely
              _isProgrammaticUpdate = true;
              _searchController.text = _lastWords;
              _isProgrammaticUpdate = false;
              _lastWords = '';
            }
          }
        },
        onError: (error) {
          print('Speech recognition error: $error');
          setState(() {
            _isListening = false;
          });
          if (mounted) {
            String errorMessage = 'Voice input error';
            // Provide user-friendly error messages
            if (error.errorMsg.contains('timeout')) {
              errorMessage = 'No speech detected. Please try speaking again.';
            } else if (error.errorMsg.contains('error_no_match')) {
              errorMessage = 'Could not understand. Please try speaking again.';
            } else if (error.errorMsg.contains('error_audio')) {
              errorMessage = 'Audio error. Please check your microphone.';
            } else if (error.errorMsg.contains('error_network')) {
              errorMessage = 'Network error. Please check your connection.';
            } else {
              errorMessage = 'Voice input temporarily unavailable. Please try again.';
            }
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      );
      setState(() {
        _isSpeechAvailable = available;
      });
    } catch (e) {
      print('Failed to initialize speech recognition: $e');
      setState(() {
        _isSpeechAvailable = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input is not available. Please restart the app after installing plugins.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }


  @override
  void dispose() {
    _debounceTimer?.cancel();
    _speech.stop();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ✅ FIX 3: Modified _fetchSuggestions() to avoid UI jank & duplicate calls
  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().length < 2) return;
    
    // ⛔ Prevent multiple API calls at once
    if (_isSuggestionRequestOngoing) return;
    _isSuggestionRequestOngoing = true;
    
    try {
      setState(() {
        _isLoadingSuggestions = true;
      });
      
      final results = await AgentService.getAutocompleteSuggestions(query)
          .timeout(const Duration(seconds: 4), onTimeout: () => []);
      
      if (!mounted) return;
      
      // Only update UI if suggestions still match current query
      if (_searchController.text.trim() == query.trim()) {
        setState(() {
          _suggestions = results.take(8).toList(); // Limit results ⛑️ prevents heavy rebuild
        });
      }
    } catch (e) {
      print('Error fetching suggestions: $e');
      if (mounted) {
        setState(() {
          _suggestions = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSuggestions = false;
        });
      }
      _isSuggestionRequestOngoing = false;
    }
  }

  void _onSuggestionTap(String suggestion) {
    _searchController.text = suggestion;
    _searchFocusNode.unfocus();
    setState(() {
      _suggestions = [];
    });
    // Optionally auto-submit or just fill the field
    // _onSearchSubmitted();
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.request();
    if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required for voice input'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _startListening() async {
    try {
      if (!_isSpeechAvailable) {
        await _initializeSpeech();
      }
      
      if (!_isSpeechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Speech recognition is not available. Please restart the app.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // Request microphone permission
      await _requestMicrophonePermission();

      setState(() {
        _isListening = true;
        _lastWords = '';
      });

      await _speech.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
            // Update text field in real-time with partial results
            if (result.recognizedWords.isNotEmpty) {
              // ✅ FIX 4: Prevent speech-to-text from refiring listener infinitely
              _isProgrammaticUpdate = true;
              _searchController.text = result.recognizedWords;
              _isProgrammaticUpdate = false;
            }
            if (result.finalResult) {
              // When final result is received, ensure text is set
              // ✅ FIX 4: Prevent speech-to-text from refiring listener infinitely
              _isProgrammaticUpdate = true;
              _searchController.text = result.recognizedWords;
              _isProgrammaticUpdate = false;
              _isListening = false;
              // If voice mode is active, keep it active for continuous listening
              if (!_isVoiceModeActive) {
                _lastWords = '';
              }
            }
          });
        },
        listenFor: const Duration(seconds: 60), // Increased timeout
        pauseFor: const Duration(seconds: 5), // Increased pause time
        localeId: 'en_US',
        cancelOnError: false, // Don't cancel on error, let user retry
        partialResults: true,
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
      setState(() {
        _isListening = false;
        _isSpeechAvailable = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start voice input. Please restart the app.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _toggleVoiceMode() {
    setState(() {
      _isVoiceModeActive = !_isVoiceModeActive;
    });

    if (_isVoiceModeActive) {
      // When voice mode is activated, start listening
      _startListening();
    } else {
      // When voice mode is deactivated, stop listening
      _stopListening();
    }
  }

  Future<void> _handleMicrophoneTap() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  // ✅ Show plus menu (Take photo, Add photos & files, Web search)
  void _showPlusMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Menu options
            _buildMenuOption(
              icon: Icons.camera_alt,
              label: 'Take photo',
              onTap: () {
                Navigator.pop(context);
                _handleTakePhoto();
              },
            ),
            _buildMenuOption(
              icon: Icons.attach_file,
              label: 'Add photos & files',
              onTap: () {
                Navigator.pop(context);
                _handleAddPhotosAndFiles();
              },
            ),
            _buildMenuOption(
              icon: Icons.language,
              label: 'Web search',
              onTap: () {
                Navigator.pop(context);
                _handleWebSearch();
              },
              isSelected: _isWebSearchMode,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // Helper to build menu option
  Widget _buildMenuOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.iconPrimary,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const Spacer(),
            if (isSelected)
              Icon(
                Icons.check,
                color: AppColors.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  // Handle "Take photo" option
  Future<void> _handleTakePhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        await _processImageForSearch(File(image.path), 'Camera photo');
      }
    } catch (e) {
      print('❌ Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to take photo. Please check camera permissions.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Handle "Add photos & files" option
  Future<void> _handleAddPhotosAndFiles() async {
    try {
      final List<XFile>? images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (images != null && images.isNotEmpty) {
        // Process the first image for search (you can extend this to handle multiple)
        await _processImageForSearch(File(images[0].path), 'Gallery photo');
        
        if (images.length > 1 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Using first image. ${images.length - 1} more image(s) selected.'),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error selecting photos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to select photos. Please check permissions.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ Process image: Upload and perform image search
  Future<void> _processImageForSearch(File imageFile, String source) async {
    if (!mounted) return;
    
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
    
    try {
      print('📤 Uploading image from $source: ${imageFile.path}');
      
      // Step 1: Upload image to get URL
      final uploadResponse = await ApiClient.upload('/upload/single', imageFile, 'image');
      final uploadBody = await uploadResponse.stream.bytesToString();
      
      if (uploadResponse.statusCode != 200) {
        throw Exception('Image upload failed: ${uploadResponse.statusCode}');
      }
      
      final uploadData = jsonDecode(uploadBody);
      final imageUrl = uploadData['url'] as String?;
      
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('No image URL returned from upload');
      }
      
      print('✅ Image uploaded successfully: $imageUrl');
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      // ✅ Store image URL in state and show preview (don't navigate yet)
      // ✅ FIX: Clear previous image URL first to ensure fresh search
      if (mounted) {
        setState(() {
          _uploadedImageUrl = null; // Clear old image first
        });
        // Set new image URL in next frame to ensure state is cleared
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _uploadedImageUrl = imageUrl;
            });
          }
        });
        // Note: No success message - image preview in search bar is sufficient feedback
      }
    } catch (e) {
      print('❌ Error processing image: $e');
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process image: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Handle "Web search" option
  void _handleWebSearch() {
    setState(() {
      _isWebSearchMode = !_isWebSearchMode;
    });
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isWebSearchMode 
              ? 'Web search mode enabled' 
              : 'Web search mode disabled'
          ),
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
    print('🌐 Web search mode: ${_isWebSearchMode ? "ON" : "OFF"}');
    // TODO: Use _isWebSearchMode flag when submitting search to enable web search
  }

  void _onSearchSubmitted() {
    final query = _searchController.text.trim();
    print('ShopScreen submitting query: "$query"');
    _searchFocusNode.unfocus(); // Unfocus the search field
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    setState(() {
      _suggestions = []; // Clear suggestions when submitting
    });
    
    // ✅ Only navigate if there's a query OR an image
    if (query.isNotEmpty || _uploadedImageUrl != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ShoppingResultsScreen(
            query: query.isNotEmpty ? query : 'Find similar items',
            imageUrl: _uploadedImageUrl, // ✅ Pass uploaded image URL
          ),
        ),
      ).then((_) {
        // Clear search text and image when returning from ShoppingResultsScreen
        _searchController.clear();
        setState(() {
          _uploadedImageUrl = null;
        });
      });
    }
  }

  // ✅ Remove uploaded image
  void _removeImage() {
    setState(() {
      _uploadedImageUrl = null;
    });
  }

  // ✅ Build image preview (ChatGPT style)
  Widget _buildImagePreview() {
    final imageUrl = _uploadedImageUrl ?? widget.imageUrl;
    if (imageUrl == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Stack(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.border.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.image_not_supported,
                    color: AppColors.textSecondary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          // Remove button (X) in top-right corner
          Positioned(
            top: -4,
            right: -4,
            child: GestureDetector(
              onTap: _removeImage,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.border,
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (_isLoadingSuggestions) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
      );
    }

    if (_suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 20, right: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.border.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _suggestions.asMap().entries.map((entry) {
          final index = entry.key;
          final suggestion = entry.value;
          final isLast = index == _suggestions.length - 1;
          return InkWell(
            onTap: () => _onSuggestionTap(suggestion),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: isLast ? null : BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.border.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.textSecondary.withOpacity(0.5),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Top Section with Logo and Icons (always at top)
              _buildTopSection(),
              
              // Middle Section (positioned near bottom)
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Search Suggestions (above search bar)
                              if (_suggestions.isNotEmpty || _isLoadingSuggestions)
                                _buildSuggestionsList(),
                              
                              // Search Bar
                              _buildSearchBar(),
                              
                              const SizedBox(height: 16),
                              
                              // Quick Actions
                              _buildQuickActions(context),
                              
                              SizedBox(height: isKeyboardVisible ? 8.0 : 40.0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          // Clonar name on top left
              Text(
                'Clonar',
                style: AppTypography.headline1,
              ),
        
        // Top Right Icons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Notification Icon
              GestureDetector(
                onTap: () {
                  // Dismiss keyboard when tapping notification
                  FocusScope.of(context).unfocus();
                },
                child: FaIcon(
                 FontAwesomeIcons.bell,
                color: AppColors.iconPrimary,
                size: 24,
                ),
              ),
              const SizedBox(width: 30),
              // Chat Icon
              GestureDetector(
                onTap: () {
                  // Dismiss keyboard when tapping chat
                  FocusScope.of(context).unfocus();
                },
                child: FaIcon(
                FontAwesomeIcons.facebookMessenger,
                color: AppColors.iconPrimary,
                size: 24,
                ),
              ),
            ],
        ),
      ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 56,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface, // Dark theme background
          borderRadius: BorderRadius.circular(16), // More rounded like Perplexity
          border: Border.all(
            color: AppColors.border.withOpacity(0.5),
            width: 1,
            ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ Image Preview (if uploaded) - ChatGPT style
              if (_uploadedImageUrl != null || widget.imageUrl != null)
                _buildImagePreview(),
              
              // Top Layer: Text Field (Enter here) + Send Button (rightmost)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TextField (expanded to take available space)
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  autofocus: false,
                  minLines: 1,
                      maxLines: null, // Allow unlimited lines to prevent overflow
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                      onSubmitted: (value) => _onSearchSubmitted(),
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                        height: 1.4, // Line height for better text spacing
                  ),
                      onChanged: (value) {
                        setState(() {
                          _hasText = value.trim().isNotEmpty;
                        });
                      },
                  decoration: const InputDecoration(
                    hintText: 'Shop, style, or clone an agent...',
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
              
                  const SizedBox(width: 8),
              
                  // Send Button (rightmost in same layer as text field)
              GestureDetector(
                onTap: (_hasText || _uploadedImageUrl != null || widget.imageUrl != null) 
                    ? _onSearchSubmitted 
                    : null,
                child: Container(
                      width: 28,
                      height: 28,
                  decoration: BoxDecoration(
                        color: (_hasText || _uploadedImageUrl != null || widget.imageUrl != null)
                          ? AppColors.primary // Blue when there's text or image
                          : AppColors.surfaceVariant, // Grey when empty
                        borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.arrow_upward,
                    color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // Bottom Layer: Icons Row (Plus, Search, Mic, Voice Mode)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: Plus and Search icons
                  Row(
                    children: [
                      // Plus icon - clickable (show image preview if uploaded)
                      GestureDetector(
                        onTap: _showPlusMenu,
                        child: (_uploadedImageUrl != null || widget.imageUrl != null)
                            ? Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.primary, width: 1.5),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: Image.network(
                                    _uploadedImageUrl ?? widget.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.image,
                                      color: AppColors.iconPrimary,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.add,
                                color: AppColors.iconPrimary,
                                size: 20,
                              ),
                      ),
                      
                      const SizedBox(width: 12),
                      
                      // Search icon - shows web search state
                      Icon(
                        _isWebSearchMode ? Icons.language : Icons.search,
                        color: _isWebSearchMode ? AppColors.primary : AppColors.iconPrimary,
                        size: 20,
                      ),
                    ],
                ),
                  
                  // Right: Microphone and Voice Mode
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Microphone icon
                      GestureDetector(
                        onTap: _handleMicrophoneTap,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.mic,
                            color: _isListening 
                              ? Colors.red // Red when actively listening
                              : AppColors.iconPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // Voice mode button (blue with three vertical lines)
                      GestureDetector(
                        onTap: _toggleVoiceMode,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: _isVoiceModeActive 
                              ? AppColors.primary // Blue when active
                              : AppColors.surfaceVariant, // Grey when inactive
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Three vertical lines of varying heights (sound waves)
                                Container(
                                  width: 1.5,
                                  height: _isVoiceModeActive ? 8 : 6,
                                  decoration: BoxDecoration(
                                    color: _isVoiceModeActive ? Colors.white : AppColors.textSecondary,
                                    borderRadius: BorderRadius.circular(0.75),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Container(
                                  width: 1.5,
                                  height: _isVoiceModeActive ? 12 : 8,
                                  decoration: BoxDecoration(
                                    color: _isVoiceModeActive ? Colors.white : AppColors.textSecondary,
                                    borderRadius: BorderRadius.circular(0.75),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Container(
                                  width: 1.5,
                                  height: _isVoiceModeActive ? 6 : 4,
                                  decoration: BoxDecoration(
                                    color: _isVoiceModeActive ? Colors.white : AppColors.textSecondary,
                                    borderRadius: BorderRadius.circular(0.75),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Row 1: Shop Anything, Clone others' Style, Suggest an Outfit
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(context, 'Shop Anything'),
              _buildActionButton(context, 'Clone  Style'),
              _buildActionButton(context, 'Suggest an Outfit'),
            ],
          ),
          const SizedBox(height: 12),
          // Row 2: Virtual Try On, Travel
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionButton(context, 'Virtual Try On'),
              const SizedBox(width: 12),
              _buildActionButton(
                context, 
                'Travel',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TravelScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String text, {VoidCallback? onTap}) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.28, // ~28% of screen width
      height: 36,
      child: ElevatedButton(
        onPressed: () {
          // Dismiss keyboard when tapping action button
          FocusScope.of(context).unfocus();
          // Call custom callback if provided, otherwise default action
          if (onTap != null) {
            onTap();
          } else {
            // TODO: Implement default action
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.buttonSecondary,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
        ),
        child: Text(
          text,
          style: AppTypography.button.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
