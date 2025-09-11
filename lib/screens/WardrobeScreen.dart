import 'package:flutter/material.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class WardrobeScreen extends StatelessWidget {
  const WardrobeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Wardrobe',
          style: AppTypography.title1,
        ),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.checkroom,
              size: 80,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 24),
            Text(
              'Coming Soon',
              style: AppTypography.headline2.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Wardrobe feature is under development',
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
