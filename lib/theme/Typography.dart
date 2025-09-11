import 'package:flutter/material.dart';
import 'AppColors.dart';

class AppTypography {
  // Headline styles
  static const TextStyle headline1 = TextStyle(
    fontSize: 32.0,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );
  
  static const TextStyle headline2 = TextStyle(
    fontSize: 28.0,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: -0.25,
  );
  
  static const TextStyle headline3 = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.0,
  );
  
  // Title styles
  static const TextStyle title1 = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.15,
  );
  
  static const TextStyle title2 = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.15,
  );
  
  // Body styles
  static const TextStyle body1 = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );
  
  static const TextStyle body2 = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    letterSpacing: 0.25,
  );
  
  // Caption styles
  static const TextStyle caption = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    letterSpacing: 0.4,
  );
  
  static const TextStyle captionSmall = TextStyle(
    fontSize: 10.0,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    letterSpacing: 0.4,
  );
  
  // Button styles
  static const TextStyle button = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 1.25,
  );
  
  // Overline styles
  static const TextStyle overline = TextStyle(
    fontSize: 10.0,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 1.5,
  );
}
