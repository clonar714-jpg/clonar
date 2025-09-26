import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';

class AddToListPage extends StatefulWidget {
  const AddToListPage({super.key});

  @override
  State<AddToListPage> createState() => _AddToListPageState();
}

class _AddToListPageState extends State<AddToListPage> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  String? _webUrl;
  List<File> _selectedImages = [];
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _selectedImages = []; // Clear gallery selection when taking photo
          _webUrl = null; // Clear web URL when selecting local image
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image from camera: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      // Show gallery options in a bottom sheet
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildGalleryOptionsBottomSheet(),
      );
    } catch (e) {
      _showErrorSnackBar('Failed to access gallery: $e');
    }
  }

  Widget _buildGalleryOptionsBottomSheet() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select from Gallery',
              style: AppTypography.title2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Options
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppColors.primary),
            title: const Text('Single Photo'),
            subtitle: const Text('Pick one photo from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickSingleFromGallery();
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
            title: const Text('Multiple Photos'),
            subtitle: const Text('Pick multiple photos from gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickMultipleFromGallery();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _pickSingleFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _selectedImages = []; // Clear multiple selection
          _webUrl = null; // Clear web URL
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image from gallery: $e');
    }
  }

  Future<void> _pickMultipleFromGallery() async {
    try {
      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        setState(() {
          _selectedImages = images.map((xFile) => File(xFile.path)).toList();
          _selectedImage = null; // Clear single image when selecting multiple
          _webUrl = null; // Clear web URL when selecting gallery images
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick images from gallery: $e');
    }
  }

  Future<void> _pickFromWeb(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            "Pick from Web",
            style: AppTypography.title2.copyWith(color: AppColors.textPrimary),
          ),
          content: TextField(
            controller: controller,
            style: AppTypography.body1,
            decoration: InputDecoration(
              hintText: "Enter image URL",
              hintStyle: AppTypography.body1.copyWith(color: AppColors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.searchBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                "Cancel",
                style: AppTypography.body1.copyWith(color: AppColors.textSecondary),
              ),
            ),
            ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    setState(() {
                      _webUrl = controller.text;
                      _selectedImage = null; // Clear local image when selecting web URL
                      _selectedImages = []; // Clear gallery selection when selecting web URL
                    });
                    Navigator.pop(context);
                  }
                },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _addToList() {
    if (_selectedImage == null && _webUrl == null && _selectedImages.isEmpty) {
      _showErrorSnackBar('Please select an image, enter a web URL, or choose from gallery');
      return;
    }

    if (_titleController.text.isEmpty) {
      _showErrorSnackBar('Please enter a persona title');
      return;
    }

    // TODO: Save to your list data structure
    // For now, just show success message
    int itemCount = _selectedImages.isNotEmpty ? _selectedImages.length : 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$itemCount persona${itemCount > 1 ? 's' : ''} added to Collections"),
        backgroundColor: AppColors.primary,
      ),
    );
    
    // Navigate back
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Add to Collections",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Choose how to create content
              Text(
                "Choose how to create content",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),

              // Picker Options
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildOption(Icons.camera_alt, "Camera", _pickFromCamera),
                  _buildOption(Icons.photo_library, "Gallery", _pickFromGallery),
                  _buildOption(Icons.public, "Web", () => _pickFromWeb(context)),
                ],
              ),
              const SizedBox(height: 32),

              // Persona Details
              Text(
                "Persona Details",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                "Title",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
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
                  style: TextStyle(color: Colors.black87),
                  decoration: InputDecoration(
                    hintText: "Enter persona title",
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              Text(
                "Description (Optional)",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
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
                  style: TextStyle(color: Colors.black87),
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "Enter persona description",
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Preview
              Text(
                "Preview",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _selectedImages.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: GridView.builder(
                          padding: const EdgeInsets.all(4),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                          ),
                          itemCount: _selectedImages.length,
                          itemBuilder: (context, index) {
                            final imageFile = _selectedImages[index];
                            return Image.file(
                              imageFile,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      )
                    : _selectedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              _selectedImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : _webUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.network(
                                  _webUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.error_outline,
                                            size: 48,
                                            color: Colors.grey[500],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            "Failed to load image",
                                            style: TextStyle(color: Colors.grey[500]),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              )
                            : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 48,
                                      color: Colors.grey[500],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      "No media selected",
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Choose from camera, gallery, or web",
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
              ),
              const SizedBox(height: 32),

              // Add Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _addToList,
                  icon: const Icon(Icons.check, size: 20),
                  label: Text(
                    "Add to Collections",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Icon(
              icon, 
              color: AppColors.primary, 
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
