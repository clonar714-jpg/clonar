import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/Collage.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../services/collage_service.dart';
import 'CollageEditorPage.dart';
import 'CollageItemFullScreenPage.dart';

class CollageViewPage extends StatefulWidget {
  final Collage collage;

  const CollageViewPage({super.key, required this.collage});

  @override
  State<CollageViewPage> createState() => _CollageViewPageState();
}

class _CollageViewPageState extends State<CollageViewPage> {
  late Collage _currentCollage;

  @override
  void initState() {
    super.initState();
    _currentCollage = widget.collage;
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          _currentCollage.title,
          style: AppTypography.title1.copyWith(color: Colors.black),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: AppColors.primary),
            onPressed: () {
              // Navigate to CollageEditorPage with existing collage
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CollageEditorPage(
                    existingCollage: _currentCollage,
                  ),
                ),
              ).then((result) {
                // Refresh the page when returning from editor
                if (result == true) {
                  setState(() {
                    // Refresh the collage data
                    _currentCollage = widget.collage; // This will be updated with fresh data
                  });
                  print('Collage updated successfully');
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black87),
            onPressed: () {
              // Optional: implement share
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),

      // 🔽 Body
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            // 🎨 Collage canvas
            LayoutBuilder(
              builder: (context, constraints) {
                final double previewWidth = constraints.maxWidth;
                // Use a fixed height instead of percentage to avoid infinite constraints
                final double previewHeight = 680; // Compact height to fit everything on single page

                // ✅ We won't scale based on a hardcoded editor width anymore.
                // We'll use the same logical coordinates directly.
                return Container(
                  width: previewWidth,
                  height: previewHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      ..._currentCollage.items.map((item) {
                      // 💡 Use item coordinates directly (no shrinking)
                      return Positioned(
                        left: item.position.dx,
                        top: item.position.dy,
                        width: item.size.width,
                        height: item.size.height,
                        child: GestureDetector(
                          onTap: () {
                            final itemIndex = _currentCollage.items.indexOf(item);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CollageItemFullScreenPage(
                                  item: item,
                                  allItems: _currentCollage.items,
                                  initialIndex: itemIndex,
                                ),
                              ),
                            );
                          },
                          child: Transform.rotate(
                            angle: item.rotation,
                            child: Opacity(
                              opacity: item.opacity.isFinite ? item.opacity : 1.0,
                              child: _buildCollageItem(item),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // 🏷 Title & Description (smaller size)
            Text(
              _currentCollage.title,
              style: AppTypography.body1.copyWith(
                color: Colors.black,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (_currentCollage.description != null &&
                _currentCollage.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _currentCollage.description!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: Colors.grey[600],
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ✅ Helper for meta tags
  // ✅ Fix for text items — full display + correct Google font
  Widget _buildCollageItem(CollageItem item) {
    if (item.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image, color: Colors.redAccent),
          ),
        ),
      );
    }

    // ✅ Fix for text items — full display + correct Google font
    if (item.type == 'text' && item.text != null && item.text!.isNotEmpty) {
      final fontFamily = item.fontFamily ?? 'Roboto';
      final fontSize = item.fontSize ?? 24.0;
      final textColor = Color(item.textColor ?? 0xFF000000);

      return Container(
        width: item.size.width,
        // Allow height to grow automatically
        constraints: const BoxConstraints(minHeight: 50, maxHeight: double.infinity),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: item.hasBackground == true
            ? BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Text(
          item.text!,
          softWrap: true,
          textAlign: TextAlign.center,
          overflow: TextOverflow.visible,
          style: GoogleFonts.getFont(
            fontFamily,
            fontSize: fontSize,
            color: textColor,
            fontWeight:
                item.isBold == true ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    if (item.type == 'shape') {
      return Container(
        decoration: BoxDecoration(
          color: Color(item.color ?? 0xFF2196F3),
          shape: item.shapeType == 'circle'
              ? BoxShape.circle
              : BoxShape.rectangle,
          borderRadius: item.shapeType == 'rectangle'
              ? BorderRadius.circular(8)
              : null,
        ),
      );
    }

    return const SizedBox();
  }

  // ✅ Delete confirmation dialog
  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Collage'),
          content: Text('Are you sure you want to delete "${_currentCollage.title}"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteCollage(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // ✅ Delete collage functionality
  Future<void> _deleteCollage(BuildContext context) async {
    print('🗑️ Starting delete operation for collage: ${_currentCollage.id}');
    
    // Store context reference to avoid deactivated widget issues
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      // Call delete service with timeout
      print('🗑️ Calling CollageService.deleteCollage...');
      await CollageService.deleteCollage(_currentCollage.id).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Delete operation timed out');
        },
      );
      print('🗑️ Delete service completed successfully');

      // Hide loading indicator
      if (mounted) {
        print('🗑️ Hiding loading indicator');
        navigator.pop();
      }

      // Show success message
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('✅ Collage "${_currentCollage.title}" deleted successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Navigate back to previous screen
      if (mounted) {
        navigator.pop(true); // Return true to indicate deletion
      }
    } catch (e) {
      print('❌ Error deleting collage: $e');
      
      // Hide loading indicator
      if (mounted) {
        navigator.pop();
      }

      // Show error message
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('❌ Failed to delete collage: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}