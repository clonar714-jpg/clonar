import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/Persona.dart';
import '../services/persona_service.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../utils/ImageHelper.dart';
import '../core/api_client.dart';
import 'CollageEditorPage.dart';
import 'SimilarImagesSearchPage.dart';
import 'PerplexityAnswerScreen.dart';
import '../widgets/DualActionButtons.dart';

class PersonaDetailPage extends StatefulWidget {
  final Persona persona;
  const PersonaDetailPage({super.key, required this.persona});

  @override
  State<PersonaDetailPage> createState() => _PersonaDetailPageState();
}

class _PersonaDetailPageState extends State<PersonaDetailPage> {
  int _currentImageIndex = 0;
  late Future<Persona> _personaFuture;
  late Persona _currentPersona;
  
  // Editing state
  bool _isEditing = false;
  bool _isLoading = false;
  
  // Controllers for editing
  TextEditingController? _titleController;
  TextEditingController? _descriptionController;
  TextEditingController? _tagController;
  List<String> _editableTags = [];
  
  // Image picker
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _currentPersona = widget.persona;
    // Initialize with fresh data from backend
    _personaFuture = PersonaService.fetchPersona(widget.persona.id);
    _initializeControllers();
  }

  void _initializeControllers() {
    _titleController = TextEditingController(text: _currentPersona.title);
    _descriptionController = TextEditingController(text: _currentPersona.description ?? '');
    _editableTags = List.from(_currentPersona.tags);
    _tagController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController?.dispose();
    _descriptionController?.dispose();
    _tagController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          color: AppColors.textPrimary,
        ),
        title: _isEditing 
            ? TextField(
                controller: _titleController ?? TextEditingController(text: _currentPersona.title),
                style: AppTypography.title1.copyWith(fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              )
            : Text(
                _currentPersona.title,
                style: AppTypography.title1.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isEditing) ...[
          IconButton(
              icon: const Icon(Icons.check),
              color: AppColors.primary,
              onPressed: _saveChanges,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: AppColors.textSecondary,
              onPressed: _cancelEditing,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.auto_awesome_mosaic),
              color: AppColors.primary,
              onPressed: _createCollage,
          ),
          IconButton(
              icon: const Icon(Icons.edit),
              color: AppColors.textPrimary,
              onPressed: _startEditing,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert),
              color: AppColors.textPrimary,
              onPressed: _showMoreOptions,
            ),
          ],
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<Persona>(
              future: _personaFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
            children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading persona',
                          style: AppTypography.title2,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.error.toString(),
                          style: AppTypography.body1.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
          ),
        ],
      ),
                  );
                }

                final persona = snapshot.data!;
                return _buildPersonaContent(persona);
              },
            ),
    );
  }

  Widget _buildPersonaContent(Persona persona) {
    return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image
          _buildCoverImage(persona),
          
          const SizedBox(height: 20),
          
          // Persona Info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  persona.title,
                  style: AppTypography.title1.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Description (editable when in edit mode)
          if (_isEditing)
                  TextField(
                    controller: _descriptionController ?? TextEditingController(text: _currentPersona.description ?? ''),
                    maxLines: 3,
                style: AppTypography.body1.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Description',
                      hintText: 'Add a description...',
              ),
            )
          else
                  Text(
                    persona.description?.isNotEmpty == true
                        ? persona.description!
                        : 'No description available.',
                    style: AppTypography.body1.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Tags
                _buildTagsSection(persona),
                
                const SizedBox(height: 24),
                
                // Additional Images
                _buildItemsGrid(persona),
                    ],
                ),
                ),
              ],
            ),
    );
  }

  Widget _buildCoverImage(Persona persona) {
    return GestureDetector(
      onTap: _isEditing ? _changeCoverPhoto : () => _viewImageFullscreen(),
      child: Container(
        height: 300,
        child: Stack(
          children: [
            // Main cover image
            persona.imageUrl != null && persona.imageUrl!.isNotEmpty
                ? Stack(
                    children: [
                      ClipRRect(
                child: Image.network(
                          ImageHelper.resolve(persona.imageUrl!),
                  fit: BoxFit.cover,
                          width: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                            return _buildImagePlaceholder();
                          },
                        ),
                      ),
                      // Dual action buttons for persona image
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: DualActionButtons(
                          onSearchTap: () => _openSearchWithImage(ImageHelper.resolve(persona.imageUrl!)),
                          onShopTap: () => _openShopWithImage(ImageHelper.resolve(persona.imageUrl!)),
                          size: 40,
                          spacing: 8,
                        ),
                      ),
                    ],
                  )
                : _buildImagePlaceholder(),
            
            // Overlay for editing
            if (_isEditing)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Stack(
                  children: [
                    const Center(
              child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                children: [
                          Icon(Icons.camera_alt, color: Colors.white, size: 48),
                          SizedBox(height: 8),
                    Text(
                            'Tap to change cover photo',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                        ],
                      ),
                    ),
                    // Delete button for cover image
                    if (persona.imageUrl != null && persona.imageUrl!.isNotEmpty)
                      Positioned(
                        top: 16,
                        left: 16,
                        child: GestureDetector(
                          onTap: () => _removeCoverImage(),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                          ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            
            // Image counter if there are additional images
            if (persona.items != null && persona.items!.isNotEmpty)
              Positioned(
                top: 16,
                right: 16,
                            child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(12),
                              ),
                  child: Text(
                    '${_currentImageIndex + 1}/${(persona.items?.length ?? 0) + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
    );
  }

  Widget _buildTagsSection(Persona persona) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
              'Tags',
                        style: AppTypography.title2.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                        ),
                      ),
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addTag,
                color: AppColors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
        if (_isEditing) ...[
          // Tag input field
          TextField(
            controller: _tagController ?? TextEditingController(),
                decoration: const InputDecoration(
              hintText: 'Add a tag...',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.add),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                _addTagFromText(value.trim());
              }
            },
          ),
          const SizedBox(height: 8),
        ],
        
        // Tags display
        if (_editableTags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _editableTags.map((tag) => _buildTagChip(tag)).toList(),
            )
          else
            Text(
            'No tags available.',
            style: AppTypography.body1.copyWith(
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  Widget _buildTagChip(String tag) {
    return Chip(
      label: Text(tag),
      backgroundColor: AppColors.surfaceVariant,
      deleteIcon: _isEditing ? const Icon(Icons.close, size: 18) : null,
      onDeleted: _isEditing ? () => _removeTag(tag) : null,
    );
  }

  Widget _buildItemsGrid(Persona persona) {
    if (persona.items == null || persona.items!.isEmpty) {
      // Show placeholder when no additional images
      return Container(
        padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
          color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceVariant),
                      ),
                        child: Column(
                          children: [
                            Icon(
              Icons.auto_awesome_mosaic,
                              size: 48,
              color: AppColors.textSecondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
              'No additional images yet',
              style: AppTypography.title2.copyWith(
                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
              _isEditing 
                  ? 'Tap the + button to add images'
                  : 'Add items to this persona to see them here',
              style: AppTypography.body1.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (_isEditing) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _addAdditionalImages,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Add Images'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                              ),
                            ),
                          ],
        ],
      ),
    );
  }

    // Show additional images in a grid
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
            Text(
              'Additional Images',
              style: AppTypography.title2.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                        ),
                      ),
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.add_photo_alternate),
                onPressed: _addAdditionalImages,
                color: AppColors.primary,
              ),
          ],
        ),
        const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
                      ),
          itemCount: persona.items!.length,
                      itemBuilder: (context, index) {
            final item = persona.items![index];
            return _buildImageItem(item, index);
          },
        ),
      ],
    );
  }

  Widget _buildImageItem(PersonaItem item, int index) {
    return GestureDetector(
      onTap: () => _viewImageFullscreen(index + 1), // +1 because cover is index 0
      child: Container(
                          decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
              ),
            ],
                          ),
                          child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Image.network(
                              item.imageUrl,
                              fit: BoxFit.cover,
                  width: double.infinity,
                height: double.infinity,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                    color: AppColors.surfaceVariant,
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_not_supported,
                                      color: Colors.grey,
                        size: 32,
                                    ),
                                  ),
                                );
                              },
                            ),
              // Dual action buttons for all images
              Positioned(
                bottom: 4,
                right: 4,
                child: DualActionButtons(
                  onSearchTap: () => _openSearchWithImage(item.imageUrl),
                  onShopTap: () => _openShopWithImage(item.imageUrl),
                  size: 32,
                  spacing: 6,
                ),
              ),
              if (_isEditing)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _removeAdditionalImage(index),
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
            ],
          ),
        ),
      ),
    );
  }

  void _openSearchWithImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimilarImagesSearchPage(
          imageUrl: imageUrl,
          query: 'Find similar images to this persona',
        ),
      ),
    );
  }

  void _openShopWithImage(String imageUrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: PerplexityAnswerScreen(
          query: 'fashion clothing',
          imageUrl: imageUrl,
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 300,
                  decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
            Icon(
              Icons.image_not_supported,
              size: 60,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              'No image available',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
                      ],
                    ),
                  ),
    );
  }

  void _viewImageFullscreen([int? imageIndex]) async {
    final images = <String>[];
    
    // Add cover image
    if (_currentPersona.imageUrl != null && _currentPersona.imageUrl!.isNotEmpty) {
      images.add(_currentPersona.imageUrl!);
    }
    
    // Add additional images
    if (_currentPersona.items != null) {
      for (final item in _currentPersona.items!) {
        images.add(item.imageUrl);
      }
    }
    
    if (images.isEmpty) return;
    
    final initialIndex = imageIndex ?? 0;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImageFullscreenView(
          images: images,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  // Action methods
  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _initializeControllers(); // Reset to original values
    });
  }

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Persona'),
              onTap: () {
                Navigator.pop(context);
                _startEditing();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Implement share functionality
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation();
                      },
                    ),
                ],
              ),
            ),
                    );
  }

  void _changeCoverPhoto() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (image != null) {
        setState(() {
          _isLoading = true;
        });
        
        // Upload new cover image
        final response = await ApiClient.upload('/upload/single', File(image.path), 'image');
        final body = await response.stream.bytesToString();
        
        if (response.statusCode == 200) {
          final data = jsonDecode(body);
          final newImageUrl = data['url'];
          
          // Update persona with new cover image
          final updatedPersona = Persona(
            id: _currentPersona.id,
            title: _currentPersona.title,
            description: _currentPersona.description,
            imageUrl: newImageUrl,
            tags: _currentPersona.tags,
            items: _currentPersona.items,
          );
          
          setState(() {
            _currentPersona = updatedPersona;
            _personaFuture = Future.value(updatedPersona);
            _isLoading = false;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cover photo updated successfully!')),
          );
        } else {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update cover photo')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _addAdditionalImages() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (images.isNotEmpty) {
        setState(() {
          _isLoading = true;
        });
        
        print('🧪 Dev mode: skipping token injection');
        
        for (final image in images) {
          // Upload image first
          final uploadRes = await ApiClient.upload('/upload/single', File(image.path), 'image');
          final body = await uploadRes.stream.bytesToString();
          final uploadedUrl = jsonDecode(body)['url'];
          
          print('✅ Uploaded image: $uploadedUrl');
          
          // Add to persona items
          await ApiClient.post('/personas/${_currentPersona.id}/items', {
            'image_url': uploadedUrl,
            'title': '',
            'description': '',
            'position': 0,
          });
          await Future.delayed(const Duration(milliseconds: 300)); // throttle requests
          
          print('✅ Saved item: ${_currentPersona.id}');
        }
        
        // Refresh persona from backend
        await _refreshPersona();
        
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${images.length} image(s) successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _removeCoverImage() async {
    try {
      // Show confirmation dialog
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Cover Image'),
          content: const Text('Are you sure you want to delete the cover image?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      setState(() {
        _isLoading = true;
      });

      // Update persona with empty cover image
      final updatedPersona = Persona(
        id: _currentPersona.id,
        title: _currentPersona.title,
        description: _currentPersona.description,
        imageUrl: '', // Clear the cover image
        tags: _currentPersona.tags,
        items: _currentPersona.items,
      );

      // Save the change
      await PersonaService.updatePersona(
        _currentPersona.id,
        _currentPersona.description ?? '',
        _currentPersona.tags,
      );

      setState(() {
        _currentPersona = updatedPersona;
        _personaFuture = Future.value(updatedPersona);
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cover image deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete cover image: $e'),
          backgroundColor: Colors.red,
      ),
    );
  }
}

  void _removeAdditionalImage(int index) async {
    try {
      final itemToDelete = _currentPersona.items![index];
      
      // Show confirmation dialog
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Image'),
          content: const Text('Are you sure you want to delete this image?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      setState(() {
        _isLoading = true;
      });

      // Delete from backend
      await PersonaService.deletePersonaItem(_currentPersona.id, itemToDelete.id);

      // Update UI
      setState(() {
        final updatedItems = List<PersonaItem>.from(_currentPersona.items ?? <PersonaItem>[]);
        updatedItems.removeAt(index);
        
        final updatedPersona = Persona(
          id: _currentPersona.id,
          title: _currentPersona.title,
          description: _currentPersona.description,
          imageUrl: _currentPersona.imageUrl,
          tags: _currentPersona.tags,
          items: updatedItems.isNotEmpty ? updatedItems : null,
        );
        
        _currentPersona = updatedPersona;
        _personaFuture = Future.value(updatedPersona);
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Image deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _addTag() {
    final controller = _tagController ?? TextEditingController();
    if (controller.text.trim().isNotEmpty) {
      _addTagFromText(controller.text.trim());
    }
  }

  void _addTagFromText(String tag) {
    if (!_editableTags.contains(tag)) {
      setState(() {
        _editableTags.add(tag);
        (_tagController ?? TextEditingController()).clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _editableTags.remove(tag);
    });
  }

  void _saveChanges() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      // Call API to save changes
      print("🔄 Saving persona changes...");
      print("Persona ID: ${_currentPersona.id}");
      print("🔍 Original tags: ${_currentPersona.tags}");
      print("🔍 Editable tags: $_editableTags");

      final body = {
        'name': _currentPersona.title,
        'description': _descriptionController?.text.trim() ?? '',
        'cover_image_url': _currentPersona.imageUrl ?? '',
        'tags': _editableTags, // ✅ Use the edited tags, not the original ones
        'is_secret': false,
      };

      print("📦 PUT Body: $body");
      print("📦 Tags being sent: ${body['tags']}");

      final response = await ApiClient.put('/personas/${_currentPersona.id}', body);
      print("📡 API Response Status: ${response.statusCode}");
      print("✅ Save successful: ${response.body}");

      if (response.statusCode == 200) {
        // Force UI update with fresh data
        final refreshedPersona = await PersonaService.fetchPersona(_currentPersona.id);
        setState(() {
          _currentPersona = refreshedPersona;
          _isEditing = false;
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Navigate back with success indicator
        Navigator.pop(context, true);
      } else {
        final errorBody = response.body;
        print('❌ Save failed: ${response.statusCode} - $errorBody');
        
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save changes: ${response.statusCode} - $errorBody')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving changes: $e')),
      );
    }
  }

  Future<void> _refreshPersona() async {
    try {
      final res = await ApiClient.get('/personas/${_currentPersona.id}');
      if (res.statusCode == 200) {
        final jsonData = jsonDecode(res.body);
        final updated = Persona.fromJson(jsonData);
        setState(() {
          _currentPersona = updated;
          _personaFuture = Future.value(updated);
        });
        print('✅ Persona refreshed: ${updated.id}, ${updated.items?.length ?? 0} items');
      } else {
        print('❌ Failed to refresh persona: ${res.statusCode}');
      }
    } catch (e) {
      print('💥 Error refreshing persona: $e');
    }
  }


  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Persona'),
        content: const Text('Are you sure you want to delete this persona? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePersona();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
        ],
      ),
    );
  }

  Future<void> _deletePersona() async {
    try {
      setState(() {
        _isLoading = true;
      });

      await PersonaService.deletePersona(_currentPersona.id);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Persona deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to the previous screen
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete persona: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _createCollage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollageEditorPage(persona: _currentPersona),
      ),
    );
  }
}

// Fullscreen image viewer
class _ImageFullscreenView extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _ImageFullscreenView({
    required this.images,
    required this.initialIndex,
  });

  @override
  State<_ImageFullscreenView> createState() => _ImageFullscreenViewState();
}

class _ImageFullscreenViewState extends State<_ImageFullscreenView> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1}/${widget.images.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.images.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                widget.images[index],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 64,
                      ),
                    );
                  },
                ),
            ),
          );
        },
      ),
    );
  }
}