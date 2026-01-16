# Frontend Architecture: Screen Flow and Result Display

## 🎯 Overview

The Flutter frontend uses a **dedicated results screen architecture** where:
1. **ShopScreen** - User input screen (where queries are typed)
2. **ShoppingResultsScreen** - Main results display screen (navigated to after query submission)
3. **Specialized Result Screens** - HotelResultsScreen, ProductDetailScreen, etc. (for specific content types)

---

## 📱 Screen Flow

### **1. ShopScreen** (`lib/screens/ShopScreen.dart`)
- **Purpose**: Main search input screen
- **What it does**:
  - Displays search bar
  - Handles user input (text, voice, image)
  - Shows chat history
  - **Navigates to ShoppingResultsScreen** when user submits query

**Key Code**:
```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => ShoppingResultsScreen(
      query: finalQuery,
      imageUrl: imageUrl,
      conversationId: chatId,
    ),
  ),
);
```

---

### **2. ShoppingResultsScreen** (`lib/screens/ShoppingResultsScreen.dart`)
- **Purpose**: Main results display screen
- **What it does**:
  1. Receives query from ShopScreen
  2. Submits query to `agentControllerProvider` (if not already submitted)
  3. Watches `sessionHistoryProvider` for session updates
  4. Uses `SessionRenderer` widget to display results
  5. Handles follow-up queries
  6. Can navigate to specialized screens (HotelResultsScreen, etc.)

**Key Components**:
- `SessionRenderer` - Renders each query session
- `PerplexityAnswerWidget` - Displays answer, cards, sources, images (used inside SessionRenderer)
- Follow-up input field
- Scroll controller for smooth scrolling

**Key Code**:
```dart
// Submit query on init (if not replay mode)
if (!widget.isReplayMode) {
  ref.read(agentControllerProvider.notifier).submitQuery(
    widget.query, 
    imageUrl: widget.imageUrl,
  );
}

// Watch sessions and render
Consumer(
  builder: (context, ref, child) {
    final sessions = ref.watch(sessionHistoryProvider);
    return SessionRenderer(
      sessions: sessions,
      // ...
    );
  },
)
```

---

### **3. SessionRenderer** (`lib/widgets/SessionRenderer.dart`)
- **Purpose**: Wrapper widget that renders query sessions
- **What it does**:
  - Iterates through sessions from `sessionHistoryProvider`
  - For each session, renders `PerplexityAnswerWidget`
  - Handles session-specific UI (loading states, streaming, etc.)

---

### **4. PerplexityAnswerWidget** (`lib/widgets/PerplexityAnswerWidget.dart`)
- **Purpose**: Main answer display widget
- **What it displays**:
  - Answer text (streaming or final)
  - Cards (hotels, products, places, movies)
  - Sources section
  - Media section (images)
  - Follow-up suggestions
  - Map view (if applicable)

**Navigation from PerplexityAnswerWidget**:
- Can navigate to `HotelResultsScreen` for hotel-specific queries
- Can navigate to detail screens (ProductDetailScreen, PlaceDetailScreen, MovieDetailScreen)

---

### **5. Specialized Result Screens**

#### **HotelResultsScreen** (`lib/screens/HotelResultsScreen.dart`)
- **Purpose**: Hotel-specific results display
- **When used**:
  - Navigated to from ShoppingResultsScreen/PerplexityAnswerWidget
  - Can be accessed directly from TravelScreen
- **Features**:
  - Date picker (check-in/check-out)
  - Guest count selector
  - Map view / List view toggle
  - Hotel cards with booking links

#### **ProductDetailScreen** (`lib/screens/ProductDetailScreen.dart`)
- **Purpose**: Product detail view
- **When used**: When user taps on a product card

#### **PlaceDetailScreen** (`lib/screens/PlaceDetailScreen.dart`)
- **Purpose**: Place/restaurant detail view
- **When used**: When user taps on a place card

#### **MovieDetailScreen** (`lib/screens/MovieDetailScreen.dart`)
- **Purpose**: Movie detail view
- **When used**: When user taps on a movie card

---

## 🔄 Complete Flow

```
User Types Query in ShopScreen
  ↓
User Presses Submit
  ↓
ShopScreen navigates to ShoppingResultsScreen
  ↓
ShoppingResultsScreen.initState()
  ↓
ShoppingResultsScreen calls agentControllerProvider.submitQuery()
  ↓
AgentProvider creates SSE connection
  ↓
SSE events stream in
  ↓
AgentProvider updates sessionHistoryProvider
  ↓
ShoppingResultsScreen rebuilds (watches sessionHistoryProvider)
  ↓
SessionRenderer renders sessions
  ↓
PerplexityAnswerWidget displays:
  - Answer text
  - Cards (hotels, products, etc.)
  - Sources
  - Images
  - Follow-ups
  ↓
User can:
  - Tap follow-up → New query in same screen
  - Tap hotel card → Navigate to HotelResultsScreen
  - Tap product card → Navigate to ProductDetailScreen
  - Navigate back → Returns to ShopScreen
```

---

## 📁 Key Files

### **Screens**
- `lib/screens/ShopScreen.dart` - Main input screen
- `lib/screens/ShoppingResultsScreen.dart` - Main results screen ⭐ **PRIMARY RESULTS SCREEN**
- `lib/screens/HotelResultsScreen.dart` - Hotel-specific results
- `lib/screens/ProductDetailScreen.dart` - Product details
- `lib/screens/PlaceDetailScreen.dart` - Place details
- `lib/screens/MovieDetailScreen.dart` - Movie details

### **Widgets**
- `lib/widgets/PerplexityAnswerWidget.dart` - Answer display widget ⭐ **PRIMARY ANSWER WIDGET**
- `lib/widgets/SessionRenderer.dart` - Session renderer wrapper
- `lib/widgets/GoogleMapWidget.dart` - Map display
- `lib/widgets/HotelMapView.dart` - Hotel map view

### **Providers**
- `lib/providers/agent_provider.dart` - Agent state management
- `lib/providers/session_history_provider.dart` - Session history state
- `lib/providers/query_state_provider.dart` - Query state

### **Services**
- `lib/services/agent_stream_service.dart` - SSE client
- `lib/services/ChatHistoryServiceCloud.dart` - Chat persistence

---

## ✅ Answer to Your Question

**Yes, you ARE using ShoppingResultsScreen and HotelResultsScreen!**

- **ShoppingResultsScreen** is the **PRIMARY** results display screen
- It's navigated to from ShopScreen when user submits a query
- It uses SessionRenderer → PerplexityAnswerWidget to display results
- **HotelResultsScreen** is a specialized screen for hotel queries
- It can be navigated to from ShoppingResultsScreen or directly from TravelScreen

**The architecture is**:
```
ShopScreen (input) 
  → ShoppingResultsScreen (main results) 
    → PerplexityAnswerWidget (answer display)
      → HotelResultsScreen / ProductDetailScreen / etc. (specialized views)
```

---

## 🎨 UI Components Hierarchy

```
ShoppingResultsScreen
  ├── AppBar (with query display)
  ├── ScrollView
  │   └── SessionRenderer
  │       └── PerplexityAnswerWidget (for each session)
  │           ├── Answer Text
  │           ├── Cards Section
  │           │   ├── Hotel Cards → Navigate to HotelResultsScreen
  │           │   ├── Product Cards → Navigate to ProductDetailScreen
  │           │   ├── Place Cards → Navigate to PlaceDetailScreen
  │           │   └── Movie Cards → Navigate to MovieDetailScreen
  │           ├── Sources Section
  │           ├── Media Section (Images)
  │           └── Follow-up Suggestions
  └── Follow-up Input Field
```

---

## 🔍 Important Notes

1. **ShoppingResultsScreen is NOT obsolete** - It's the main results screen
2. **HotelResultsScreen is a specialized view** - Used for hotel-specific queries
3. **PerplexityAnswerWidget is the display component** - Used inside ShoppingResultsScreen
4. **Navigation flow**: ShopScreen → ShoppingResultsScreen → (optional) Specialized screens
5. **State management**: All screens watch `sessionHistoryProvider` for updates

---

**Last Updated**: 2024
**Version**: 1.0

