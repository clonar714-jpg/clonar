# Flutter Freeze Risk Analysis

## File Classification

### UI_ONLY (Pure widgets, no heavy logic)

1. **lib/theme/AppColors.dart** - Color constants
2. **lib/theme/Typography.dart** - Text style definitions
3. **lib/widgets/AnswerHeaderRow.dart** - Pure UI widget
4. **lib/widgets/CustomDatePicker.dart** - Date picker UI
5. **lib/widgets/DualActionButtons.dart** - Button widget
6. **lib/widgets/StylishSearchButton.dart** - Button widget
7. **lib/widgets/room_card.dart** - Room card widget
8. **lib/widgets/HotelCardPerplexity.dart** - Hotel card widget
9. **lib/widgets/StreamingTextWidget.dart** - Text animation widget (isolated)
10. **lib/widgets/PerplexityTypingAnimation.dart** - Animation widget
11. **lib/widgets/GoogleMapWidget.dart** - Map widget (uses Google Maps)
12. **lib/widgets/HotelMapView.dart** - Map widget (uses Google Maps)
13. **lib/widgets/HotelsMapView.dart** - Map widget (uses Google Maps)
14. **lib/models/Product.dart** - Data model
15. **lib/models/query_session_model.dart** - Data model
16. **lib/models/Collage.dart** - Data model
17. **lib/models/Persona.dart** - Data model
18. **lib/models/room.dart** - Data model
19. **lib/models/Variant.dart** - Data model
20. **lib/screens/LoginPage.dart** - Login UI
21. **lib/screens/RegisterPage.dart** - Registration UI
22. **lib/screens/SplashScreen.dart** - Splash screen UI
23. **lib/screens/AccountScreen.dart** - Account UI
24. **lib/screens/WishlistScreen.dart** - Wishlist UI
25. **lib/screens/WardrobeScreen.dart** - Wardrobe UI
26. **lib/screens/FeedScreen.dart** - Feed UI
27. **lib/screens/FullScreenMapScreen.dart** - Full screen map UI
28. **lib/screens/HotelPhotoGalleryScreen.dart** - Photo gallery UI
29. **lib/widgets/SessionRenderer.dart** - Pure rendering widget (delegates to providers)

### AGENTIC_ONLY (AI/API logic, no UI)

1. **lib/core/api_client.dart** - HTTP client
2. **lib/core/emulator_detector.dart** - Emulator detection utility
3. **lib/core/provider_observer.dart** - Provider observer (logging only)
4. **lib/services/AgentService.dart** - Agent API service
5. **lib/services/ApiService.dart** - General API service
6. **lib/services/CacheService.dart** - Cache service
7. **lib/services/ChatHistoryService.dart** - Chat history service
8. **lib/services/ChatHistoryServiceCloud.dart** - Cloud chat history (uses compute)
9. **lib/services/GeocodingService.dart** - Geocoding service
10. **lib/services/ProductService.dart** - Product API service
11. **lib/services/rooms_service.dart** - Rooms API service
12. **lib/services/collage_service.dart** - Collage API service
13. **lib/services/persona_service.dart** - Persona API service
14. **lib/providers/agent_provider.dart** - Agent controller (FIXED: uses compute)
15. **lib/providers/query_state_provider.dart** - Query state provider
16. **lib/providers/session_history_provider.dart** - Session history provider
17. **lib/providers/scroll_provider.dart** - Scroll controller provider
18. **lib/providers/loading_provider.dart** - Loading state provider
19. **lib/providers/autocomplete_provider.dart** - Autocomplete provider (disabled)
20. **lib/providers/chat_history_provider.dart** - Chat history provider
21. **lib/providers/follow_up_controller_provider.dart** - Follow-up controller
22. **lib/providers/follow_up_engine_provider.dart** - Follow-up suggestion engine
23. **lib/providers/follow_up_dedupe_provider.dart** - Follow-up deduplication
24. **lib/providers/streaming_text_provider.dart** - Streaming text provider
25. **lib/isolates/text_parsing_isolate.dart** - Text parsing isolate
26. **lib/isolates/content_normalization_isolate.dart** - Content normalization isolate
27. **lib/utils/ImageHelper.dart** - Image utility

### MIXED_UI_AND_AGENTIC (HIGH RISK - UI + Heavy Logic)

1. **lib/main.dart** - App root (FIXED: GlobalKey removed, ThemeData static)
2. **lib/screens/ShopScreen.dart** - Search screen with API calls, setState, initState
3. **lib/screens/ShoppingResultsScreen.dart** - Results screen with 83+ .map()/.toList() operations, setState, initState, heavy processing
4. **lib/screens/HotelDetailScreen.dart** - Hotel detail with jsonDecode, .map().toList(), setState, API calls
5. **lib/screens/ProductDetailScreen.dart** - Product detail with API calls
6. **lib/screens/ShoppingGridScreen.dart** - Product grid with data processing
7. **lib/screens/HotelResultsScreen.dart** - Hotel results with data processing
8. **lib/screens/MovieDetailScreen.dart** - Movie detail with API calls
9. **lib/screens/TravelScreen.dart** - Travel screen with API calls
10. **lib/screens/CollageViewPage.dart** - Collage view with data processing
11. **lib/screens/CollageEditorPage.dart** - Collage editor with data processing
12. **lib/screens/CollagePublishPage.dart** - Collage publish with API calls
13. **lib/screens/CollageItemFullScreenPage.dart** - Full screen collage with data processing
14. **lib/screens/CreatePersonaPage.dart** - Persona creation with API calls
15. **lib/screens/PersonaDetailPage.dart** - Persona detail with API calls
16. **lib/screens/DesignToUploadPage.dart** - Design upload with API calls
17. **lib/screens/AddToListPage.dart** - Add to list with API calls
18. **lib/screens/SimilarImagesSearchPage.dart** - Image search with API calls
19. **lib/screens/rooms_page.dart** - Rooms page with API calls
20. **lib/screens/RoomDetailsScreen.dart** - Room details with API calls
21. **lib/providers/parsed_agent_output_provider.dart** - Provider with .map() operations (uses compute for heavy work)
22. **lib/providers/display_content_provider.dart** - Provider with many .map() operations (uses compute for normalization)

---

## TOP 5 FREEZE-RISK FILES

### 1. lib/screens/ShoppingResultsScreen.dart
**Category:** MIXED_UI_AND_AGENTIC  
**Risk Level:** CRITICAL  
**Why Risky:**
- 83+ `.map()` / `.toList()` operations throughout the file
- Heavy list transformations in `build()` method (lines 807-848, 853-922, 1312-1315)
- Multiple `.map()` chains executed synchronously on UI thread
- Session restoration with `.map()` operations in `addPostFrameCallback` (lines 1306-1320)
- Large data structures (locations, places, products) processed synchronously
- `initState()` triggers heavy work
- Multiple `setState()` calls

**Blocking Operations:**
- Line 807-848: `preprocessedLocations.map(...).toList()` - processes entire locations array
- Line 853-922: `preprocessedPlaces.map(...).toList()` - processes entire places array
- Line 1312-1315: Session restoration with multiple `.map()` operations
- Lines 1432-1447: History conversion with nested `.map()` operations

**Suggested Fix:**
- Move all `.map()` / `.toList()` operations to `compute()` isolates
- Pre-process data in providers before passing to UI
- Use `ListView.builder` instead of `.map().toList()` for rendering
- Defer session restoration to background isolate

---

### 2. lib/providers/display_content_provider.dart
**Category:** MIXED_UI_AND_AGENTIC  
**Risk Level:** HIGH  
**Why Risky:**
- 15+ `.map()` / `.toList()` operations in provider (lines 100, 104, 117, 170, 187, 190, 226, 228)
- Multiple synchronous list transformations before compute() calls
- Provider runs on every session update
- Large loops iterating over cards, results, hotels (lines 131-143, 157-175, 196-211)
- Product.fromJson() called in loop (line 133) - can fail and block

**Blocking Operations:**
- Line 100: `session.locationCards.map(...)` - synchronous transformation
- Line 104: `responseLocations.map(...).toList()` - synchronous transformation
- Line 117: `destination_images.map(...).where(...).toList()` - synchronous transformation
- Lines 131-143: Loop with Product.fromJson() - can block on parsing errors
- Line 170: `responseHotels.map(...).toList()` - synchronous transformation

**Suggested Fix:**
- Move all `.map()` operations before compute() into the isolate
- Batch all transformations in a single compute() call
- Pre-validate Product.fromJson() data before processing

---

### 3. lib/screens/HotelDetailScreen.dart
**Category:** MIXED_UI_AND_AGENTIC  
**Risk Level:** HIGH  
**Why Risky:**
- `jsonDecode()` on UI thread (line 177)
- Multiple `.map().toList()` operations (lines 120-124, 197-201, 223-224)
- API calls in `initState()` (line 89-90)
- `setState()` calls after async operations (lines 96, 263, 270, 335, 357, 378, 395, 401)
- Heavy data processing in `_loadHotelDetails()` method

**Blocking Operations:**
- Line 177: `jsonDecode(response.body)` - synchronous JSON parsing
- Lines 120-124: `.map().toList()` for amenities - synchronous transformation
- Lines 197-201: `.map().toList()` for amenities - synchronous transformation
- Line 223-224: `.map().toList()` for amenities - synchronous transformation

**Suggested Fix:**
- Move `jsonDecode()` to `compute()` isolate
- Move all `.map()` operations to isolate
- Pre-process hotel data in service layer

---

### 4. lib/providers/parsed_agent_output_provider.dart
**Category:** MIXED_UI_AND_AGENTIC  
**Risk Level:** MEDIUM  
**Why Risky:**
- 4 `.map().toList()` operations before compute() (lines 15-19)
- Synchronous list transformations on UI thread
- Provider runs on every agent response update
- Multiple Map transformations executed sequentially

**Blocking Operations:**
- Line 15: `locationCards.map(...).toList()` - synchronous transformation
- Line 16: `destination_images.map(...).where(...).toList()` - synchronous transformation
- Line 19: `cards.map(...).toList()` - synchronous transformation

**Suggested Fix:**
- Move all `.map()` operations into the compute() isolate
- Pass raw response to isolate, return fully processed data

---

### 5. lib/screens/ShopScreen.dart
**Category:** MIXED_UI_AND_AGENTIC  
**Risk Level:** MEDIUM  
**Why Risky:**
- Multiple `setState()` calls (19+ occurrences)
- API calls triggered from UI interactions
- `initState()` loads chat history (deferred but still risky)
- Image processing in `_processImageForSearch()` (uses compute - GOOD)
- Speech-to-text callbacks can trigger rebuilds

**Blocking Operations:**
- Lines 140, 167, 192, 216, 235, 263, 270, 335, 357, 378, 395, 401: `setState()` calls
- Chat history loading (deferred but still processes data)
- Image upload processing

**Suggested Fix:**
- Reduce `setState()` calls - use ValueNotifier for isolated updates
- Ensure all data processing uses compute()
- Verify chat history parsing is fully isolated

---

## Summary

**Total Files Analyzed:** 79  
**UI_ONLY:** 29 files  
**AGENTIC_ONLY:** 27 files  
**MIXED_UI_AND_AGENTIC:** 22 files  

**Critical Issues:**
1. **ShoppingResultsScreen.dart** - 83+ synchronous list operations
2. **display_content_provider.dart** - 15+ synchronous list operations
3. **HotelDetailScreen.dart** - JSON parsing + list operations on UI thread
4. **parsed_agent_output_provider.dart** - List operations before compute()
5. **ShopScreen.dart** - Excessive setState() calls

**Root Cause:** Synchronous `.map()` / `.toList()` operations on large data structures executed on UI thread during build/initState/setState.

**Recommended Action:** Move ALL list transformations to `compute()` isolates, especially in ShoppingResultsScreen.dart and display_content_provider.dart.

