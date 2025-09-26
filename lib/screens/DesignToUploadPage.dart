import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class DesignToUploadPage extends StatefulWidget {
  const DesignToUploadPage({super.key});

  @override
  State<DesignToUploadPage> createState() => _DesignToUploadPageState();
}

class _DesignToUploadPageState extends State<DesignToUploadPage> {
  final ImagePicker _picker = ImagePicker();
  List<File> _selectedImages = [];
  List<Widget> _imageWidgets = [];
  String _selectedLayout = 'grid';
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  final List<String> _layoutOptions = [
    'grid',
    'masonry',
    'carousel',
    'stack',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        setState(() {
          _selectedImages = images.map((xFile) => File(xFile.path)).toList();
          _buildImageWidgets();
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick images: $e');
    }
  }

  void _buildImageWidgets() {
    _imageWidgets = _selectedImages.asMap().entries.map((entry) {
      final index = entry.key;
      final image = entry.value;
      return _buildImageItem(image, index);
    }).toList();
  }

  Widget _buildImageItem(File image, int index) {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              image,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _buildImageWidgets();
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _uploadDesign() {
    if (_selectedImages.isEmpty) {
      _showErrorSnackBar('Please add at least one image');
      return;
    }
    if (_titleController.text.isEmpty) {
      _showErrorSnackBar('Please enter a title');
      return;
    }

    // TODO: Implement upload logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Design uploaded successfully!'),
        backgroundColor: AppColors.primary,
      ),
    );
    Navigator.pop(context);
  }

  Widget _buildLayoutSelector() {
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _layoutOptions.length,
        itemBuilder: (context, index) {
          final layout = _layoutOptions[index];
          final isSelected = _selectedLayout == layout;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedLayout = layout;
              });
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  layout.toUpperCase(),
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageGrid() {
    if (_selectedImages.isEmpty) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey[300]!,
            style: BorderStyle.solid,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Add images to create your design',
              style: AppTypography.body1.copyWith(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Images'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _imageWidgets.length,
            itemBuilder: (context, index) => _imageWidgets[index],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add More'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Implement reorder functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Drag to reorder images'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.reorder, size: 20),
              label: const Text('Reorder'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[200],
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Design to Upload',
          style: AppTypography.title1.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: _selectedImages.isNotEmpty ? _uploadDesign : null,
              child: Text(
                'Upload',
                style: AppTypography.body1.copyWith(
                  color: _selectedImages.isNotEmpty ? AppColors.primary : Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Layout selector
            Text(
              'Choose Layout',
              style: AppTypography.title2.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            _buildLayoutSelector(),
            
            // Image grid
            Text(
              'Your Design',
              style: AppTypography.title2.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildImageGrid(),
            
            const SizedBox(height: 32),
            
            // Title and Description
            Text(
              'Design Details',
              style: AppTypography.title2.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            
            // Title field
            Text(
              'Title',
              style: AppTypography.body1.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _titleController,
                style: AppTypography.body1.copyWith(color: Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Enter design title',
                  hintStyle: AppTypography.body1.copyWith(
                    color: Colors.grey[500],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Description field
            Text(
              'Description (Optional)',
              style: AppTypography.body1.copyWith(
                color: Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: TextField(
                controller: _descriptionController,
                style: AppTypography.body1.copyWith(color: Colors.black87),
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter design description',
                  hintStyle: AppTypography.body1.copyWith(
                    color: Colors.grey[500],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
