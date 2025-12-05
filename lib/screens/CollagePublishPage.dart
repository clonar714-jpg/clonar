import 'package:flutter/material.dart';
import 'dart:convert';
import '../models/Collage.dart';
import '../models/Persona.dart';
import '../services/collage_service.dart';
import 'AccountScreen.dart';

class CollagePublishPage extends StatefulWidget {
  final List<CollageItem> collageItems;
  final String layout;
  final Persona? persona;

  const CollagePublishPage({
    super.key,
    required this.collageItems,
    required this.layout,
    this.persona,
  });

  @override
  State<CollagePublishPage> createState() => _CollagePublishPageState();
}

class _CollagePublishPageState extends State<CollagePublishPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _enableRemixing = false;
  bool _isCreating = false;

  // Match logical design space used in CollageEditorPage
  static const double editorCanvasWidth = 1080;
  static const double editorCanvasHeight = 1920;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create Collage',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Collage Preview (100% accurate replication of editor)
              Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Use phone width dynamically
                    final double previewWidth = constraints.maxWidth - 32; // 16px padding on each side
                    const double editorCanvasWidth = 1080;
                    const double editorCanvasHeight = 1920;

                    // Keep aspect ratio same as editor
                    final double previewHeight = previewWidth * (editorCanvasHeight / editorCanvasWidth);

                    // Compute scaling factors
                    final double scaleX = previewWidth / editorCanvasWidth;
                    final double scaleY = previewHeight / editorCanvasHeight;

                    return Container(
                      width: previewWidth,
                      height: previewHeight,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: widget.collageItems.map((item) {
                          final double left = item.position.dx * scaleX;
                          final double top = item.position.dy * scaleY;
                          final double width = item.size.width * scaleX;
                          final double height = item.size.height * scaleY;

                          return Positioned(
                            left: left,
                            top: top,
                            width: width,
                            height: height,
                            child: Transform.rotate(
                              angle: item.rotation,
                              child: Opacity(
                                opacity: item.opacity.isFinite ? item.opacity : 1,
                                child: _buildPreviewItem(item, width, height, scaleY),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),

              // ✅ Title field
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.white24, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.white70, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ✅ Description field
              TextField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.white24, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Colors.white70, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // ✅ Publish to (Profile)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.person, color: Colors.white70),
                      SizedBox(width: 10),
                      Text('Publish to Profile',
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                  Switch(
                    value: true,
                    onChanged: (_) {},
                    activeColor: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ✅ Enable Remixing
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Enable remixing\nLet people use your collage as a starting point to create their own',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ),
                  Switch(
                    value: _enableRemixing,
                    onChanged: (val) =>
                        setState(() => _enableRemixing = val),
                    activeColor: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // ✅ Save / Create buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Save for later',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _createCollage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _isCreating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(color: Colors.white))
                          : const Text('Create',
                              style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCollage() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add a title')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      final validItems = widget.collageItems
          .where((item) =>
              (item.imageUrl.isNotEmpty && Uri.tryParse(item.imageUrl)?.hasAbsolutePath == true) ||
              (item.text != null && item.text!.isNotEmpty))
          .map((item) => {
                'type': item.type ?? (item.text?.isNotEmpty == true ? 'text' : 'image'),
                if (item.imageUrl.isNotEmpty) 'image_url': item.imageUrl,
                if (item.text?.isNotEmpty == true) 'text': item.text,
                'position': {
                  'x': item.position.dx.isFinite ? item.position.dx : 0,
                  'y': item.position.dy.isFinite ? item.position.dy : 0,
                },
                'size': {
                  'width': item.size.width.isFinite ? item.size.width : 100,
                  'height': item.size.height.isFinite ? item.size.height : 100,
                },
                'rotation': item.rotation.isFinite ? item.rotation : 0,
                'opacity': item.opacity.isFinite ? item.opacity : 1,
                'z_index': item.zIndex,
                'fontFamily': item.fontFamily ?? 'Roboto',
                'fontSize': item.fontSize ?? 20,
                'textColor': item.textColor ?? 0xFF000000,
                'isBold': item.isBold ?? false,
                'hasBackground': item.hasBackground ?? false,
              })
          .toList();

      // Find the first item with a valid image URL for cover image
      final coverImageUrl = widget.collageItems
          .where((item) => item.imageUrl.isNotEmpty && item.type != 'text' && item.type != 'shape')
          .isNotEmpty
          ? widget.collageItems
              .where((item) => item.imageUrl.isNotEmpty && item.type != 'text' && item.type != 'shape')
              .first
              .imageUrl
          : widget.collageItems
              .where((item) => item.imageUrl.isNotEmpty)
              .isNotEmpty
              ? widget.collageItems.where((item) => item.imageUrl.isNotEmpty).first.imageUrl
              : null;
      
      print('🔍 CollagePublishPage - Cover image detection:');
      print('🔍 Total items: ${widget.collageItems.length}');
      for (int i = 0; i < widget.collageItems.length; i++) {
        print('🔍 Item $i: type=${widget.collageItems[i].type}, imageUrl=${widget.collageItems[i].imageUrl.isNotEmpty ? "has_url" : "empty"}');
      }
      print('🔍 Selected cover image URL: $coverImageUrl');

      // Optional sanity check
      print(jsonEncode({
        'title': _titleController.text,
        'layout': widget.layout,
        'cover_image_url': coverImageUrl,
        'items': validItems,
      }));

      final collage = await CollageService.createCollage(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        coverImageUrl: coverImageUrl,
        layout: widget.layout,
        tags: widget.persona?.tags ?? [],
        items: validItems,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Collage "${collage.title}" created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      print('🎨 Collage created successfully: ${collage.title}');
      print('🎨 Collage isPublished: ${collage.isPublished}');
      print('🎨 Cover image URL: ${collage.coverImageUrl}');

      // ✅ Navigate to AccountScreen and switch to Collages tab
      if (mounted) {
        print('🧭 Navigating to AccountScreen from CollagePublishPage...');
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => const AccountScreen(),
            settings: const RouteSettings(arguments: {'tab': 'collages'}),
          ),
          (route) => false,
        );
        print('🧭 Navigation completed');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating collage: $e')));
    } finally {
      setState(() => _isCreating = false);
    }
  }

  Widget _buildPreviewItem(CollageItem item, double width, double height, double scaleY) {
    if (item.imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.imageUrl,
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.broken_image, color: Colors.redAccent),
        ),
      );
    } else if (item.text != null && item.text!.isNotEmpty) {
      final fontSize = (item.fontSize ?? 22) * scaleY;
      return Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        decoration: item.hasBackground == true
            ? BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            item.text!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: item.fontFamily ?? 'Roboto',
              color: Color(item.textColor ?? 0xFF000000),
              fontSize: fontSize.clamp(8, 200),
              fontWeight: item.isBold == true ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
    } else if (item.type == 'shape') {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Color(item.color ?? 0xFF2196F3),
          shape: item.shapeType == 'circle' ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: item.shapeType == 'rectangle'
              ? BorderRadius.circular(8)
              : null,
        ),
      );
    }
    return const SizedBox();
  }
}
