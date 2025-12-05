class ImageHelper {
  static const String baseUrl = 'http://10.0.2.2:4000';

  static String resolve(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$baseUrl$path';
  }
}
