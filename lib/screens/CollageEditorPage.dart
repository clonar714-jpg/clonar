import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as Math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Collage.dart';
import '../models/Persona.dart';
import '../core/api_client.dart';
import '../utils/ImageHelper.dart';
import '../services/collage_service.dart';
import 'CollagePublishPage.dart';
import 'AccountScreen.dart';
import 'SimilarImagesSearchPage.dart';
import 'ClonarAnswerScreen.dart';
import '../widgets/DualActionButtons.dart';

class CollageEditorPage extends StatefulWidget {
  final Collage? existingCollage;
  final Persona? persona; // Optional persona to associate with collage
  
  const CollageEditorPage({
    super.key,
    this.existingCollage,
    this.persona,
  });

  @override
  State<CollageEditorPage> createState() => _CollageEditorPageState();
}

// ✅ Google Fonts Helper Function
TextStyle getFontByName(String fontName,
    {Color? color, double? size, FontWeight? weight}) {
  switch (fontName) {
    case 'Roboto':
      return GoogleFonts.roboto(color: color, fontSize: size, fontWeight: weight);
    case 'OpenSans':
      return GoogleFonts.openSans(color: color, fontSize: size, fontWeight: weight);
    case 'Lobster':
      return GoogleFonts.lobster(color: color, fontSize: size, fontWeight: weight);
    case 'Pacifico':
      return GoogleFonts.pacifico(color: color, fontSize: size, fontWeight: weight);
    case 'Montserrat':
      return GoogleFonts.montserrat(color: color, fontSize: size, fontWeight: weight);
    case 'PlayfairDisplay':
      return GoogleFonts.playfairDisplay(color: color, fontSize: size, fontWeight: weight);
    case 'Raleway':
      return GoogleFonts.raleway(color: color, fontSize: size, fontWeight: weight);
    case 'Oswald':
      return GoogleFonts.oswald(color: color, fontSize: size, fontWeight: weight);
    case 'Caveat':
      return GoogleFonts.caveat(color: color, fontSize: size, fontWeight: weight);
    default:
      return GoogleFonts.roboto(color: color, fontSize: size, fontWeight: weight);
  }
}

class _CollageEditorPageState extends State<CollageEditorPage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final GlobalKey _collageKey = GlobalKey();
  
  List<CollageItem> _items = [];
  String _selectedLayout = 'grid';
  String _selectedTool = 'select';
  CollageItem? _selectedItem;
  bool _isEditing = false;
  bool _isLoading = false;
  bool _isSaving = false;
  
  // ✅ Scale tracking for persistent zoom (now handled locally in StatefulBuilder)
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

  void _openSearchWithImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimilarImagesSearchPage(
          imageUrl: imageUrl,
          query: 'Find similar images',
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
        child: ClonarAnswerScreen(
          query: 'hoodie sweatshirt',
          imageUrl: imageUrl,
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final List<XFile>? images = await _picker.pickMultiImage();
      if (images != null && images.isNotEmpty) {
          for (int i = 0; i < images.length; i++) {
            final image = images[i];
          final uploadedUrl = await _uploadImage(File(image.path));
          if (uploadedUrl != null) {
            setState(() {
            final item = CollageItem(
              id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
                imageUrl: uploadedUrl,
              position: Offset(50.0 + (i * 20), 50.0 + (i * 20)),
              size: const Size(150, 150),
              zIndex: _items.length + i,
              addedAt: DateTime.now(),
            );
            _items.add(item);
            });
          }
        }
      }

      setState(() {
        _isLoading = false;
        });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to pick images: $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final XFile? image = await _picker.pickImage(source: ImageSource.camera);
      if (image != null) {
        final uploadedUrl = await _uploadImage(File(image.path));
        if (uploadedUrl != null) {
        setState(() {
          final item = CollageItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
              imageUrl: uploadedUrl,
            position: const Offset(50, 50),
            size: const Size(150, 150),
            zIndex: _items.length,
            addedAt: DateTime.now(),
          );
          _items.add(item);
        });
      }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to take photo: $e');
    }
  }

  void _selectItem(CollageItem item) {
    setState(() {
      _selectedItem = item;
      _selectedTool = 'select';
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

  Future<String?> _uploadImage(File imageFile) async {
    try {
      final response = await ApiClient.upload('/upload/single', imageFile, 'image');
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        return data['url'];
      } else {
        print('❌ Image upload failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Image upload error: $e');
      return null;
    }
  }

  Future<void> _saveCollage() async {
    if (_titleController.text.trim().isEmpty) {
      _showErrorSnackBar('Please enter a title for your collage');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final itemsData = _items.map((item) => {
        'image_url': item.imageUrl,
        'position': {'x': item.position.dx, 'y': item.position.dy},
        'size': {'width': item.size.width, 'height': item.size.height},
        'rotation': item.rotation,
        'opacity': item.opacity,
        'z_index': item.zIndex,
        'type': item.type,
        'text': item.text,
        'shape_type': item.shapeType,
        'color': item.color,
        'fontFamily': item.fontFamily,
        'fontSize': item.fontSize,
        'textColor': item.textColor,
        'isBold': item.isBold,
        'hasBackground': item.hasBackground,
      }).toList();

      // Find the first item with a valid image URL for cover image
      String? coverImageUrl;
      
      print('🔍 Cover image detection:');
      print('🔍 Total items: ${_items.length}');
      
      // First try to find image items (not text/shape)
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        print('🔍 Item $i: type=${item.type}, imageUrl=${item.imageUrl.isNotEmpty ? "has_url" : "empty"}');
        
        if (item.imageUrl.isNotEmpty && item.type != 'text' && item.type != 'shape') {
          coverImageUrl = item.imageUrl;
          print('🔍 Found image item with URL: $coverImageUrl');
          break;
        }
      }
      
      // If no image item found, try any item with URL
      if (coverImageUrl == null) {
        for (int i = 0; i < _items.length; i++) {
          final item = _items[i];
          if (item.imageUrl.isNotEmpty) {
            coverImageUrl = item.imageUrl;
            print('🔍 Found any item with URL: $coverImageUrl');
            break;
          }
        }
      }
      
      print('🔍 Final cover image URL: $coverImageUrl');

      final newCollage = widget.existingCollage != null
          ? await CollageService.updateCollage(
              widget.existingCollage!.id,
              title: _titleController.text.trim(),
              description: _descriptionController.text.trim(),
              layout: _selectedLayout,
              tags: widget.persona?.tags ?? [],
              items: itemsData,
            )
          : await CollageService.createCollage(
              title: _titleController.text.isEmpty
                  ? 'Untitled Collage'
                  : _titleController.text.trim(),
              description: _descriptionController.text.trim(),
              coverImageUrl: coverImageUrl,
              layout: _selectedLayout,
              tags: widget.persona?.tags ?? [],
              items: itemsData,
            );

      if (!mounted) return;

      // ✅ Success feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('✅ Collage "${newCollage.title}" created successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      print('🎨 Collage created successfully: ${newCollage.title}');
      print('🎨 Collage isPublished: ${newCollage.isPublished}');
      print('🎨 Cover image URL: ${newCollage.coverImageUrl}');

      // ✅ Short delay for user feedback
      await Future.delayed(const Duration(milliseconds: 800));

      // ✅ Clean navigation: Go back to AccountScreen (refresh feed)
      if (mounted) {
        print('🧭 Navigating to AccountScreen...');
        try {
          // Try pop first, then push if needed
          if (Navigator.canPop(context)) {
            Navigator.pop(context, true); // Return success signal
            print('🧭 Popped back with success signal');
          } else {
            // Fallback: push to AccountScreen
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const AccountScreen()),
            );
            print('🧭 Pushed to AccountScreen as fallback');
          }
        } catch (e) {
          print('❌ Navigation error: $e');
          // Final fallback
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const AccountScreen()),
            (route) => false,
          );
        }
      } else {
        print('❌ Widget not mounted, skipping navigation');
      }

    } catch (e) {
      _showErrorSnackBar('Failed to save collage: $e');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _saveAsImage() async {
    try {
      setState(() {
        _isLoading = true;
      });

      RenderRepaintBoundary boundary =
          _collageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Collage saved to: ${file.path}'),
        backgroundColor: AppColors.primary,
      ),
    );
    } catch (e) {
      _showErrorSnackBar('Failed to save collage as image: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
            icon: const Icon(Icons.image, color: AppColors.primary),
            onPressed: _saveAsImage,
          ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, color: AppColors.primary),
            onPressed: _isSaving ? null : _saveCollage,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.redAccent),
            onPressed: () {
              // If editing existing collage, save directly. Otherwise go to publish page
              if (widget.existingCollage != null) {
                _saveCollage();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CollagePublishPage(
                      collageItems: _items,
                      layout: _selectedLayout,
                      persona: widget.persona,
                    ),
                  ),
                );
              }
            },
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
                      } else if (tool['id'] == 'text') {
                        _openTextEditorOverlay(); // 👈 open Pinterest-style text editor
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
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                setState(() {
                  _selectedItem = null; // hide red X
                });
              },
              child: Listener(
                behavior: HitTestBehavior.translucent, // 👈 ensures child gestures aren't blocked
            child: Container(
              color: Colors.grey[100],
              child: Stack(
                children: [
                  // Grid Background
                  CustomPaint(
                    painter: GridPainter(),
                    size: Size.infinite,
                  ),
                  
                    // Collage Items with RepaintBoundary
                    _buildLayoutView(),

                    // Loading Overlay
                    if (_isLoading)
                      Container(
                        color: Colors.black.withOpacity(0.3),
                        child: const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ),
                  
                  // Empty State
                    if (_items.isEmpty && !_isLoading)
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
      // ✅ Pinterest-style floating action buttons
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Layers button
          FloatingActionButton(
            heroTag: 'layers',
            backgroundColor: AppColors.primary,
            onPressed: _openLayersPanel,
            child: const Icon(Icons.layers, color: Colors.white),
          ),
          const SizedBox(height: 16),
          // Add button
          FloatingActionButton(
            heroTag: 'add',
            backgroundColor: AppColors.primary,
            onPressed: _showAddOptions,
            child: const Icon(Icons.add, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _buildCollageItem(CollageItem item) {
    final isSelected = _selectedItem?.id == item.id;
    final transformNotifier = ValueNotifier<CollageItem>(item);
    
    return ValueListenableBuilder<CollageItem>(
      valueListenable: transformNotifier,
      builder: (context, liveItem, _) {
    return Positioned(
          left: liveItem.position.dx,
          top: liveItem.position.dy,
          child: Stack(
            clipBehavior: Clip.none, // allows delete icon to overflow
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
        onTap: () => _selectItem(item),
        onLongPress: () => _showItemOptions(item),
                onDoubleTap: () {
                  if (liveItem.type == 'text') {
                    _openTextEditorOverlay(existingItem: liveItem);
                  } else {
                    transformNotifier.value = liveItem.copyWith(
                      size: const Size(150, 150),
                      rotation: 0.0,
                    );
                  }
                },
                onScaleUpdate: (details) {
                  final current = transformNotifier.value;

                  if (details.pointerCount == 1) {
                    transformNotifier.value = current.copyWith(
                      position: Offset(
                        current.position.dx + details.focalPointDelta.dx,
                        current.position.dy + details.focalPointDelta.dy,
                      ),
                    );
                  } else if (details.pointerCount == 2) {
                    final newWidth = (current.size.width * details.scale)
                        .clamp(80.0, 800.0);
                    final newHeight = (current.size.height * details.scale)
                        .clamp(80.0, 800.0);
                    transformNotifier.value = current.copyWith(
                      size: Size(newWidth, newHeight),
                      rotation: current.rotation + details.rotation,
                    );
                  }
                },
                onScaleEnd: (_) {
                  setState(() {
                    final idx = _items.indexWhere((i) => i.id == item.id);
                    if (idx != -1) _items[idx] = transformNotifier.value;
                  });
                },
                child: Transform.rotate(
                  angle: liveItem.rotation,
        child: Container(
                    width: liveItem.size.width,
                    height: liveItem.size.height,
                    decoration: liveItem.type == 'text'
                        ? null
                        : BoxDecoration(
                            border: isSelected
                                ? Border.all(color: AppColors.primary, width: 2)
                                : null,
                            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
                    alignment: Alignment.center,
                    child: liveItem.type == 'text'
                        ? Container(
                            constraints: const BoxConstraints(
                              minWidth: 50,
                              minHeight: 30,
                              maxWidth: 300,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: liveItem.hasBackground == true
                                ? BoxDecoration(
                                    color: Colors.white.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[400]!),
                                  )
                                : null,
                            child: Text(
                              liveItem.text ?? '',
                              softWrap: true,
                              overflow: TextOverflow.visible,
                              textAlign: TextAlign.center,
                              style: getFontByName(
                                liveItem.fontFamily ?? 'Roboto',
                                color: liveItem.textColor != null 
                                    ? Color(liveItem.textColor!)
                                    : Colors.black,
                                size: liveItem.fontSize ?? 22,
                                weight: (liveItem.isBold ?? false)
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildImageWidget(liveItem),
                          ),
                  ),
                ),
              ),
              if (isSelected)
                Positioned(
                  right: -10,
                  top: -10,
                  child: GestureDetector(
                    onTap: () => _deleteItem(item),
                    child: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.red,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageWidget(CollageItem item) {
    // ✅ Handle different item types
    if (item.type == 'text') {
      return Center(
        child: Text(
          item.text ?? '',
          style: getFontByName(
            item.fontFamily ?? 'Roboto',
            color: item.textColor != null ? Color(item.textColor!) : Colors.black,
            size: item.fontSize ?? 20,
            weight: item.isBold == true ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    } else if (item.type == 'shape') {
      final color = Color(item.color ?? Colors.blueAccent.value);
      return Container(
        decoration: BoxDecoration(
          color: color,
          shape: item.shapeType == 'circle' ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: item.shapeType == 'rectangle' ? BorderRadius.circular(8) : null,
        ),
      );
    } else {
      // Regular image handling with search button
      Widget imageWidget;
      if (item.imageUrl.startsWith('http')) {
        imageWidget = Image.network(
          ImageHelper.resolve(item.imageUrl),
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
        );
      } else {
        imageWidget = Image.file(
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
        );
      }
      
      // Wrap image with dual action buttons
      return Stack(
        children: [
          imageWidget,
          Positioned(
            bottom: 2,
            right: 2,
            child: DualActionButtons(
              onSearchTap: () => _openSearchWithImage(item.imageUrl),
              onShopTap: () => _openShopWithImage(item.imageUrl),
              size: 24,
              spacing: 4,
            ),
          ),
        ],
      );
    }
  }

  // ✅ Layout rendering helper
  Widget _buildLayoutView() {
    switch (_selectedLayout) {
      case 'masonry':
        return _buildMasonryLayout();
      case 'carousel':
        return _buildCarouselLayout();
      case 'stack':
        return _buildStackLayout();
      case 'diagonal':
        return _buildDiagonalLayout();
      case 'spiral':
        return _buildSpiralLayout();
      default:
        // Grid layout (existing logic)
        return RepaintBoundary(
          key: _collageKey,
          child: Stack(
            clipBehavior: Clip.none,
            children: _items.map((item) => _buildCollageItem(item)).toList(),
          ),
        );
    }
  }

  // ✅ Layout builders
  Widget _buildMasonryLayout() {
    // Simple 2-column waterfall layout
    return RepaintBoundary(
      key: _collageKey,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth = (constraints.maxWidth - 16) / 2;
            double col1Y = 0;
            double col2Y = 0;
            final positioned = <Widget>[];

            for (final item in _items) {
              final isCol1 = col1Y <= col2Y;
              final dx = isCol1 ? 0.0 : columnWidth + 8;
              final dy = isCol1 ? col1Y : col2Y;
              final height = item.size.height;

              positioned.add(Positioned(
                left: dx,
                top: dy,
                width: columnWidth,
                child: _buildCollageItem(item),
              ));

              if (isCol1) {
                col1Y += height + 8;
              } else {
                col2Y += height + 8;
              }
            }

            return Stack(children: positioned);
          },
        ),
      ),
    );
  }

  Widget _buildCarouselLayout() {
    return RepaintBoundary(
      key: _collageKey,
      child: PageView.builder(
        itemCount: _items.length,
        controller: PageController(viewportFraction: 0.8),
        itemBuilder: (context, i) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
            child: Center(
              child: _buildCollageItem(_items[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStackLayout() {
    return RepaintBoundary(
      key: _collageKey,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: List.generate(_items.length, (i) {
            final angle = (i * 0.1) - 0.3; // slight rotation difference
            final offset = Offset(i * 8.0, i * 8.0);
            return Transform.translate(
              offset: offset,
              child: Transform.rotate(
                angle: angle,
                child: _buildCollageItem(_items[i]),
              ),
            );
        }),
      ),
      ),
    );
  }

  Widget _buildDiagonalLayout() {
    return RepaintBoundary(
      key: _collageKey,
      child: Stack(
        children: List.generate(_items.length, (i) {
          final offset = Offset(i * 40.0, i * 40.0);
          return Positioned(
            left: offset.dx,
            top: offset.dy,
            child: _buildCollageItem(_items[i]),
          );
        }),
      ),
    );
  }

  Widget _buildSpiralLayout() {
    return RepaintBoundary(
      key: _collageKey,
      child: Stack(
        children: List.generate(_items.length, (i) {
          final radius = 40.0 * i;
          final angle = 0.5 * i;
          final x = 200 + radius * Math.cos(angle);
          final y = 200 + radius * Math.sin(angle);
          return Positioned(
            left: x,
            top: y,
            child: Transform.rotate(
              angle: angle,
              child: _buildCollageItem(_items[i]),
            ),
          );
        }),
      ),
    );
  }

  // ✅ Layers panel with drag-to-reorder
  void _openLayersPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
        decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Layers',
                style: AppTypography.title2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final item = _items.removeAt(oldIndex);
                      _items.insert(newIndex, item);
                    });
                  },
                  children: [
                    for (final item in _items)
                      ListTile(
                        key: ValueKey(item.id),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: _buildThumbnailWidget(item),
                          ),
                        ),
                        title: Text('Layer ${_items.indexOf(item) + 1}'),
                        subtitle: Text(item.type ?? 'image'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteItem(item),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildThumbnailWidget(CollageItem item) {
    if (item.type == 'text') {
      return Container(
        color: Colors.grey[100],
        child: Center(
          child: Text(
            item.text ?? 'T',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
    } else if (item.type == 'shape') {
      return Container(
        decoration: BoxDecoration(
          color: Color(item.color ?? Colors.blueAccent.value),
          shape: item.shapeType == 'circle' ? BoxShape.circle : BoxShape.rectangle,
        ),
      );
    } else {
      return Image.network(
        ImageHelper.resolve(item.imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[200],
            child: const Icon(Icons.image, size: 20),
          );
        },
      );
    }
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
                _openTextEditorOverlay();
              },
            ),
            ListTile(
              leading: const Icon(Icons.crop_square, color: AppColors.primary),
              title: const Text('Add Rectangle'),
              subtitle: const Text('Add rectangular shape'),
              onTap: () {
                Navigator.pop(context);
                _addShapeItem('rectangle');
              },
            ),
            ListTile(
              leading: const Icon(Icons.circle, color: AppColors.primary),
              title: const Text('Add Circle'),
              subtitle: const Text('Add circular shape'),
              onTap: () {
                Navigator.pop(context);
                _addShapeItem('circle');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ✅ Final Pinterest-style text editor overlay (Clean UI)
  Future<void> _openTextEditorOverlay({CollageItem? existingItem}) async {
    String text = existingItem?.text ?? '';
    Color textColor = existingItem?.textColor != null 
        ? Color(existingItem!.textColor!) 
        : Colors.black;
    bool isBold = existingItem?.isBold ?? false;
    bool hasBackground = existingItem?.hasBackground ?? false;
    TextAlign alignment = TextAlign.center;
    String fontFamily = existingItem?.fontFamily ?? 'Roboto';
    double fontSize = existingItem?.fontSize ?? 28.0;
    
    // ✅ Preserve & Edit Existing Text
    final controller = TextEditingController(text: text);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.6), // slightly dimmed background
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 60,
                left: 16,
                right: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // 🔝 Top Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Text(
                        'Add Text',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context, {
                            'text': text,
                            'color': textColor,
                            'isBold': isBold,
                            'hasBackground': hasBackground,
                            'alignment': alignment,
                            'fontFamily': fontFamily,
                            'fontSize': fontSize,
                          });
                        },
                        child: const Text('Done',
                            style: TextStyle(
                                color: Colors.purpleAccent, fontSize: 16)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 60),

                  // 📝 Floating white box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20), // More rounded like Pinterest
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      textAlign: alignment,
                      style: getFontByName(
                        fontFamily,
                        color: textColor,
                        size: fontSize,
                        weight: isBold ? FontWeight.bold : FontWeight.normal,
                      ).copyWith(
                        backgroundColor: hasBackground
                            ? Colors.black.withOpacity(0.05)
                            : Colors.transparent,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Type something...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: fontSize,
                        ),
                        border: InputBorder.none,
                      ),
                      cursorColor: Colors.purpleAccent,
                      onChanged: (val) => setModalState(() => text = val),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // 🎨 Toolbar
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        // Font Style Picker
                        IconButton(
                          icon: const Icon(Icons.text_fields, color: Colors.white),
                          onPressed: () async {
                            await _showFontPicker(fontFamily, (font) {
                              setModalState(() => fontFamily = font);
                            });
                          },
                        ),

                        // Color Picker
                        IconButton(
                          icon: const Icon(Icons.color_lens, color: Colors.white),
                          onPressed: () async {
                            final color = await _pickColor(textColor);
                            if (color != null) {
                              setModalState(() => textColor = color);
                            }
                          },
                        ),

                        // Bold
                        IconButton(
                          icon: Icon(Icons.format_bold,
                              color: isBold ? Colors.purpleAccent : Colors.white),
                          onPressed: () => setModalState(() => isBold = !isBold),
                        ),

                        // Background toggle
                        IconButton(
                          icon: Icon(Icons.crop_square,
                              color: hasBackground ? Colors.purpleAccent : Colors.white),
                          onPressed: () => setModalState(() => hasBackground = !hasBackground),
                        ),

                        // Alignment
                        IconButton(
                          icon: Icon(
                            alignment == TextAlign.center
                                ? Icons.format_align_center
                                : alignment == TextAlign.left
                                    ? Icons.format_align_left
                                    : Icons.format_align_right,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setModalState(() {
                              alignment = alignment == TextAlign.center
                                  ? TextAlign.left
                                  : alignment == TextAlign.left
                                      ? TextAlign.right
                                      : TextAlign.center;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // ✅ Apply after closing overlay
    if (result != null && (result['text'] as String).trim().isNotEmpty) {
      final newItem = CollageItem(
        id: existingItem?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        imageUrl: '', // Required field
        type: 'text',
        text: result['text'],
        position: existingItem?.position ?? const Offset(100, 100),
        size: const Size(200, 50),
        fontFamily: result['fontFamily'],
        textColor: result['color'].value,
        isBold: result['isBold'],
        hasBackground: result['hasBackground'],
        fontSize: result['fontSize'],
        addedAt: DateTime.now(),
        zIndex: _items.length,
      );

      setState(() {
        if (existingItem != null) {
          final index = _items.indexWhere((i) => i.id == existingItem.id);
          _items[index] = newItem;
        } else {
          _items.add(newItem);
        }
      });
    }
  }

  // ✅ Corrected Font Picker (Pinterest/Instagram style)
  Future<void> _showFontPicker(
      String currentFont, Function(String) onFontSelected) async {
    final fonts = [
      'Roboto',
      'OpenSans',
      'Lobster',
      'Pacifico',
      'Montserrat',
      'PlayfairDisplay',
      'Raleway',
      'Oswald',
      'Caveat',
    ];

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          height: 140,
          padding: const EdgeInsets.only(top: 12, left: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 12, bottom: 8),
                child: Text(
                  'Font styles',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: fonts.length,
                  itemBuilder: (context, i) {
                    final font = fonts[i];
                    final isActive = font == currentFont;
                    return GestureDetector(
                      onTap: () {
                        onFontSelected(font); // apply instantly
                        Navigator.pop(context);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.purple.withOpacity(0.3)
                              : Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isActive
                                  ? Colors.purpleAccent
                                  : Colors.transparent,
                              width: 1),
                        ),
                        child: Center(
                          child: Text(
                            'Aa',
                            style: getFontByName(
                              font,
                              color: Colors.white,
                              size: 30,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ✅ Improved Color Picker
  Future<Color?> _pickColor(Color initialColor) async {
    final colors = [
      Colors.black,
      Colors.white,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.teal,
      Colors.blue,
      Colors.purple,
      Colors.pinkAccent,
      Colors.brown,
      Colors.grey,
    ];

    return showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors
              .map((c) => GestureDetector(
                    onTap: () => Navigator.pop(context, c),
                    child: Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade300, width: 1),
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }


  // ✅ Add shape item
  void _addShapeItem(String shape) {
    setState(() {
      final item = CollageItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imageUrl: '',
        position: const Offset(60, 60),
        size: const Size(120, 120),
        zIndex: _items.length,
        addedAt: DateTime.now(),
        type: 'shape',
        shapeType: shape,
        color: Colors.blueAccent.value,
      );
      _items.add(item);
    });
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