import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Collage.dart';

class CollageEditorPage extends StatefulWidget {
  final Collage? existingCollage;
  
  const CollageEditorPage({
    super.key,
    this.existingCollage,
  });

  @override
  State<CollageEditorPage> createState() => _CollageEditorPageState();
}

class _CollageEditorPageState extends State<CollageEditorPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  
  List<CollageItem> _items = [];
  String _selectedLayout = 'grid';
  String _selectedTool = 'select';
  CollageItem? _selectedItem;
  bool _isEditing = false;
  
  final List<String> _layouts = [
    'grid', 'masonry', 'carousel', 'stack', 'diagonal', 'spiral'
  ];
  
  final List<Map<String, dynamic>> _tools = [
    {'id': 'select', 'icon': Icons.touch_app, 'name': 'Select'},
    {'id': 'add', 'icon': Icons.add_photo_alternate, 'name': 'Add'},
    {'id': 'text', 'icon': Icons.text_fields, 'name': 'Text'},
    {'id': 'shapes', 'icon': Icons.crop_square, 'name': 'Shapes'},
    {'id': 'filters', 'icon': Icons.filter_vintage, 'name': 'Filters'},
    {'id': 'layers', 'icon': Icons.layers, 'name': 'Layers'},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existingCollage != null) {
      _titleController.text = widget.existingCollage!.title;
      _descriptionController.text = widget.existingCollage!.description ?? '';
      _items = List.from(widget.existingCollage!.items);
      _selectedLayout = widget.existingCollage!.layout;
    }
  }

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
          for (int i = 0; i < images.length; i++) {
            final image = images[i];
            final item = CollageItem(
              id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
              imageUrl: image.path,
              position: Offset(50.0 + (i * 20), 50.0 + (i * 20)),
              size: const Size(150, 150),
              zIndex: _items.length + i,
              addedAt: DateTime.now(),
            );
            _items.add(item);
          }
        });
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
          final item = CollageItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            imageUrl: image.path,
            position: const Offset(50, 50),
            size: const Size(150, 150),
            zIndex: _items.length,
            addedAt: DateTime.now(),
          );
          _items.add(item);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Failed to take photo: $e');
    }
  }

  void _selectItem(CollageItem item) {
    setState(() {
      _selectedItem = item;
      _selectedTool = 'select';
    });
  }

  void _updateItemPosition(CollageItem item, Offset newPosition) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        _items[index] = item.copyWith(position: newPosition);
      }
    });
  }

  void _updateItemSize(CollageItem item, Size newSize) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        _items[index] = item.copyWith(size: newSize);
      }
    });
  }

  void _deleteItem(CollageItem item) {
    setState(() {
      _items.removeWhere((i) => i.id == item.id);
      if (_selectedItem?.id == item.id) {
        _selectedItem = null;
      }
    });
  }

  void _duplicateItem(CollageItem item) {
    setState(() {
      final newItem = item.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        position: Offset(item.position.dx + 20, item.position.dy + 20),
        zIndex: _items.length,
      );
      _items.add(newItem);
    });
  }

  void _bringToFront(CollageItem item) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        final maxZIndex = _items.fold(0, (max, i) => i.zIndex > max ? i.zIndex : max);
        _items[index] = item.copyWith(zIndex: maxZIndex + 1);
      }
    });
  }

  void _sendToBack(CollageItem item) {
    setState(() {
      final index = _items.indexWhere((i) => i.id == item.id);
      if (index != -1) {
        final minZIndex = _items.fold(999999, (min, i) => i.zIndex < min ? i.zIndex : min);
        _items[index] = item.copyWith(zIndex: minZIndex - 1);
      }
    });
  }

  void _saveCollage() {
    if (_titleController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter a title for your collage');
      return;
    }

    // TODO: Implement actual collage saving logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Collage "${_titleController.text}" saved successfully!'),
        backgroundColor: AppColors.primary,
      ),
    );
    Navigator.pop(context);
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _showItemOptions(CollageItem item) {
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
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Item Options',
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.primary),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(context);
                _duplicateItem(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers, color: AppColors.primary),
              title: const Text('Bring to Front'),
              onTap: () {
                Navigator.pop(context);
                _bringToFront(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.layers_outlined, color: AppColors.primary),
              title: const Text('Send to Back'),
              onTap: () {
                Navigator.pop(context);
                _sendToBack(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteItem(item);
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
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Collage' : 'Create Collage',
          style: AppTypography.title1.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _isEditing ? Icons.check : Icons.edit,
              color: AppColors.primary,
            ),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.save, color: AppColors.primary),
            onPressed: _saveCollage,
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: [
                // Layout Selector
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _layouts.map((layout) {
                        final isSelected = _selectedLayout == layout;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(layout.toUpperCase()),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedLayout = layout;
                              });
                            },
                            selectedColor: AppColors.primary,
                            backgroundColor: Colors.white,
                            labelStyle: AppTypography.caption.copyWith(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide.none,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Tools
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!),
              ),
            ),
            child: Row(
              children: _tools.map((tool) {
                final isSelected = _selectedTool == tool['id'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedTool = tool['id'];
                      });
                      if (tool['id'] == 'add') {
                        _showAddOptions();
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            tool['icon'],
                            color: isSelected ? AppColors.primary : Colors.grey[600],
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tool['name'],
                            style: AppTypography.caption.copyWith(
                              color: isSelected ? AppColors.primary : Colors.grey[600],
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Canvas
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: Stack(
                children: [
                  // Grid Background
                  CustomPaint(
                    painter: GridPainter(),
                    size: Size.infinite,
                  ),
                  
                  // Collage Items
                  ..._items.map((item) => _buildCollageItem(item)).toList(),
                  
                  // Empty State
                  if (_items.isEmpty)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome_mosaic,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Start creating your collage',
                            style: AppTypography.title2.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap the Add tool to get started',
                            style: AppTypography.body1.copyWith(
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // Bottom Panel
          if (_isEditing)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    style: AppTypography.body1.copyWith(color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Collage title',
                      hintStyle: AppTypography.body1.copyWith(color: Colors.grey[500]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    style: AppTypography.body1.copyWith(color: Colors.black87),
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Description (optional)',
                      hintStyle: AppTypography.body1.copyWith(color: Colors.grey[500]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollageItem(CollageItem item) {
    final isSelected = _selectedItem?.id == item.id;
    
    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: GestureDetector(
        onTap: () => _selectItem(item),
        onLongPress: () => _showItemOptions(item),
        child: Container(
          width: item.size.width,
          height: item.size.height,
          decoration: BoxDecoration(
            border: isSelected ? Border.all(color: AppColors.primary, width: 2) : null,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                // Image
                Image.file(
                  File(item.imageUrl),
                  width: item.size.width,
                  height: item.size.height,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
                    );
                  },
                ),
                
                // Selection handles
                if (isSelected)
                  ..._buildSelectionHandles(item),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSelectionHandles(CollageItem item) {
    return [
      // Corner handles
      Positioned(
        top: -4,
        left: -4,
        child: _buildHandle(() {
          // Resize from top-left
        }),
      ),
      Positioned(
        top: -4,
        right: -4,
        child: _buildHandle(() {
          // Resize from top-right
        }),
      ),
      Positioned(
        bottom: -4,
        left: -4,
        child: _buildHandle(() {
          // Resize from bottom-left
        }),
      ),
      Positioned(
        bottom: -4,
        right: -4,
        child: _buildHandle(() {
          // Resize from bottom-right
        }),
      ),
    ];
  }

  Widget _buildHandle(VoidCallback onPan) {
    return GestureDetector(
      onPanUpdate: (details) => onPan(),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
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
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add to Collage',
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
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
            ListTile(
              leading: const Icon(Icons.text_fields, color: AppColors.primary),
              title: const Text('Add Text'),
              subtitle: const Text('Add text element'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Add text functionality
              },
            ),
            ListTile(
              leading: const Icon(Icons.crop_square, color: AppColors.primary),
              title: const Text('Add Shape'),
              subtitle: const Text('Add geometric shapes'),
              onTap: () {
                Navigator.pop(context);
                // TODO: Add shapes functionality
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 0.5;

    const gridSize = 20.0;
    
    // Vertical lines
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }
    
    // Horizontal lines
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
