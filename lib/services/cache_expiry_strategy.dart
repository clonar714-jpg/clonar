/// Cache expiry strategy based on query content
/// Determines how long to cache responses based on query keywords
class CacheExpiryStrategy {
  /// Get smart expiry duration based on query content
  static Duration getSmartExpiry(String query) {
    final lower = query.toLowerCase();
    
    // NO CACHE: Stock/availability queries (real-time data)
    if ((lower.contains('in stock') || 
         lower.contains('stock status')) &&
        !lower.contains('place') &&
        !lower.contains('attraction')) {
      return Duration.zero; 
    }
    
    if (lower.contains('available now') && 
        !lower.contains('place') &&
        !lower.contains('attraction')) {
      return Duration.zero; 
    }
    
    // SHORT CACHE (15 min): Price-sensitive queries
    if (lower.contains('under') || 
        lower.contains('cheap') ||
        lower.contains('sale') ||
        lower.contains('discount') ||
        lower.contains('price') ||
        lower.contains('cost') ||
        lower.contains('affordable')) {
      return Duration(minutes: 15);
    }
    
    // MEDIUM CACHE (30 min): Shopping queries
    if (lower.contains('buy') ||
        lower.contains('shop') ||
        lower.contains('product') ||
        lower.contains('shopping')) {
      return Duration(minutes: 30);
    }
    
    // MEDIUM-LONG CACHE (1 hour): Reviews/comparisons
    if (lower.contains('best') || 
        lower.contains('top') ||
        lower.contains('review') ||
        lower.contains('compare')) {
      return Duration(hours: 1);
    }
    
    // LONG CACHE (2 hours): Brand/model searches
    if (lower.contains('nike') || 
        lower.contains('adidas') ||
        lower.contains('iphone') ||
        lower.contains('samsung') ||
        lower.contains('gucci') ||
        lower.contains('puma')) {
      return Duration(hours: 2);
    }
    
    // VERY LONG CACHE (7 days): Hotels, restaurants, places
    if (lower.contains('hotel') ||
        lower.contains('resort') ||
        lower.contains('restaurant') ||
        lower.contains('cafe') ||
        lower.contains('dining') ||
        lower.contains('places to visit') ||
        lower.contains('place to visit') ||
        lower.contains('things to do') ||
        lower.contains('attraction') ||
        lower.contains('attractions') ||
        lower.contains('tourist spot') ||
        lower.contains('tourist attraction') ||
        lower.contains('landmark') ||
        lower.contains('landmarks') ||
        lower.contains('sightseeing') ||
        lower.contains('must visit') ||
        lower.contains('city to visit') ||
        lower.contains('heritage site') ||
        lower.contains('cultural site') ||
        lower.contains('cultural sites') ||
        lower.contains('temple') ||
        lower.contains('temples') ||
        lower.contains('park') ||
        lower.contains('parks') ||
        lower.contains('beach') ||
        lower.contains('beaches') ||
        lower.contains('island') ||
        lower.contains('islands') ||
        lower.contains('mountain') ||
        lower.contains('mountains') ||
        lower.contains('waterfall') ||
        lower.contains('waterfalls') ||
        lower.contains('museum') ||
        lower.contains('museums') ||
        lower.contains('monument') ||
        lower.contains('monuments')) {
      return Duration(days: 7);
    }
    
    // DEFAULT: 30 minutes
    return Duration(minutes: 30);
  }
}

