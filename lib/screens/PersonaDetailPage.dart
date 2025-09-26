import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Persona.dart';

class PersonaDetailPage extends StatefulWidget {
  final Persona persona;
  
  const PersonaDetailPage({
    super.key,
    required this.persona,
  });

  @override
  State<PersonaDetailPage> createState() => _PersonaDetailPageState();
}

class _PersonaDetailPageState extends State<PersonaDetailPage> {
  final ImagePicker _picker = ImagePicker();
  late Persona _persona;
  bool _isEditing = false;
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _persona = widget.persona;
    _descriptionController.text = _persona.description ?? '';
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
        setState(() {
          // In a real app, you'd save these to the persona
          // For now, we'll just show a success message
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${images.length} images added to persona'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick images: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        setState(() {
          // In a real app, you'd save this to the persona
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Photo added to persona'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('Failed to take photo: $e');
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_persona.tags.contains(tag)) {
      setState(() {
        _persona = _persona.copyWith(
          tags: [..._persona.tags, tag],
        );
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _persona = _persona.copyWith(
        tags: _persona.tags.where((t) => t != tag).toList(),
      );
    });
  }

  void _saveChanges() {
    setState(() {
      _persona = _persona.copyWith(
        description: _descriptionController.text.trim().isEmpty 
            ? null 
            : _descriptionController.text.trim(),
        updatedAt: DateTime.now(),
      );
      _isEditing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Persona updated successfully'),
        backgroundColor: AppColors.primary,
      ),
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

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                'Add to Persona',
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Options
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Add from Gallery'),
              subtitle: const Text('Select multiple photos'),
              onTap: () {
                Navigator.pop(context);
                _pickImages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take Photo'),
              subtitle: const Text('Capture a new photo'),
              onTap: () {
                Navigator.pop(context);
                _pickFromCamera();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
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
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _persona.name,
          style: AppTypography.title1.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEditing ? Icons.check : Icons.edit,
              color: AppColors.primary,
            ),
            onPressed: () {
              if (_isEditing) {
                _saveChanges();
              } else {
                setState(() {
                  _isEditing = true;
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            onPressed: () {
              // TODO: Show more options menu
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image
            if (_persona.coverImageUrl != null)
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                ),
                child: Image.network(
                  _persona.coverImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: Colors.grey,
                        ),
                      ),
                    );
                  },
                ),
              ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  if (_persona.description != null || _isEditing) ...[
                    Text(
                      'Description',
                      style: AppTypography.title2.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isEditing)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            hintText: 'Describe your persona...',
                            hintStyle: AppTypography.body1.copyWith(color: Colors.grey[500]),
                            border: InputBorder.none,
                          ),
                        ),
                      )
                    else
                      Text(
                        _persona.description ?? '',
                        style: AppTypography.body1.copyWith(color: Colors.black87),
                      ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Tags
                  if (_persona.tags.isNotEmpty || _isEditing) ...[
                    Text(
                      'Tags',
                      style: AppTypography.title2.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_isEditing) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: TextField(
                                controller: _tagController,
                                style: AppTypography.body1.copyWith(color: Colors.black87),
                                decoration: InputDecoration(
                                  hintText: 'Add tags...',
                                  hintStyle: AppTypography.body1.copyWith(color: Colors.grey[500]),
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _addTag(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _addTag,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _persona.tags.map((tag) => Chip(
                        label: Text(tag),
                        deleteIcon: _isEditing ? const Icon(Icons.close, size: 16) : null,
                        onDeleted: _isEditing ? () => _removeTag(tag) : null,
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        labelStyle: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      )).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Items Grid
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Items (${_persona.items.length})',
                        style: AppTypography.title2.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _showAddOptions,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Items Grid
                  if (_persona.items.isEmpty)
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Center(
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
                              'No items yet',
                              style: AppTypography.body1.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap "Add" to get started',
                              style: AppTypography.caption.copyWith(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.8,
                      ),
                      itemCount: _persona.items.length,
                      itemBuilder: (context, index) {
                        final item = _persona.items[index];
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              item.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_not_supported,
                                      color: Colors.grey,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
