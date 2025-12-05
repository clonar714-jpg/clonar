import 'package:flutter/material.dart';
import '../theme/AppColors.dart';

class StylishSearchButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const StylishSearchButton({
    super.key,
    required this.onTap,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(size / 2),
        ),
        child: Icon(
          Icons.search,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
}

