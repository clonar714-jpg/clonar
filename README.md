# Clonar App

A Flutter app for shopping, styling, and cloning fashion agents.

## Features

- **Shop Screen**: Main home screen with logo, search bar, and quick actions
- **Navigation**: Bottom navigation with 5 tabs (Shop, Feed, Wardrobe, Wishlist, Account)
- **Dark Theme**: Modern dark UI with gradient accents
- **Responsive Design**: Optimized for Android emulator and mobile devices

## Project Structure

```
lib/
├── main.dart                 # App entry point with navigation
├── screens/
│   ├── ShopScreen.dart      # Main home screen (Shop)
│   ├── FeedScreen.dart      # Feed placeholder
│   ├── WardrobeScreen.dart  # Wardrobe placeholder
│   ├── WishlistScreen.dart  # Wishlist placeholder
│   └── AccountScreen.dart   # Account placeholder
└── theme/
    ├── AppColors.dart       # Color palette
    └── Typography.dart      # Text styles
```

## Getting Started

### Prerequisites

- Flutter SDK (>=3.0.0)
- Android Studio / VS Code
- Android Emulator or physical device

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Install dependencies:
   ```bash
   flutter pub get
   ```

### Running the App

1. Ensure your emulator/device is running
2. Run the app:
   ```bash
   flutter run
   ```

## Design Features

### Shop Screen (Home)
- **Logo & Branding**: Circular logo with gradient, centered "Clonar" title
- **Top Icons**: Notification bell and chat icons in top-right corner
- **Search Bar**: Rounded container with upload button, placeholder text, and mic icon
- **Quick Actions**: Horizontal scrollable pill-shaped buttons for various features

### Theme
- **Dark Background**: Black to dark gray gradient
- **Primary Colors**: Indigo/purple accent colors
- **Typography**: Consistent text styles with proper hierarchy
- **Material Design**: Follows Material Design guidelines

### Navigation
- **Bottom Navigation Bar**: 5 tabs with Material icons
- **Tab Routing**: Each tab routes to its respective screen
- **Active State**: Shop tab is active by default

## Development Notes

- All screens use `const` constructors where possible
- Material Design widgets only (no Cupertino)
- Responsive layout with proper spacing
- Placeholder screens for future development
- Clean separation of concerns with theme files

## Future Enhancements

- Implement actual functionality for quick action buttons
- Add real content to placeholder screens
- Integrate with backend services
- Add user authentication
- Implement shopping and styling features
