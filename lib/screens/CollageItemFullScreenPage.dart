import 'package:flutter/material.dart';
import '../models/Collage.dart';
import '../theme/AppColors.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CollageItemFullScreenPage extends StatefulWidget {
  final CollageItem item;
  final List<CollageItem> allItems;
  final int initialIndex;

  const CollageItemFullScreenPage({
    super.key,
    required this.item,
    required this.allItems,
    required this.initialIndex,
  });

  @override
  State<CollageItemFullScreenPage> createState() => _CollageItemFullScreenPageState();
}

class _CollageItemFullScreenPageState extends State<CollageItemFullScreenPage> {
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
          '${_currentIndex + 1} / ${widget.allItems.length}',
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
        itemCount: widget.allItems.length,
        itemBuilder: (context, index) {
          final item = widget.allItems[index];
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: item.type == 'text'
                  ? Container(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        item.text ?? '',
                        style: TextStyle(
                          fontFamily: item.fontFamily ?? 'Roboto',
                          fontSize: item.fontSize ?? 20,
                          color: Color(item.textColor ?? 0xFF000000),
                          fontWeight: item.isBold == true ? FontWeight.bold : FontWeight.normal,
                          backgroundColor: item.hasBackground == true 
                              ? Color(item.color ?? 0xFFFFFFFF) 
                              : Colors.transparent,
                        ),
                      ),
                    )
                  : item.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(Icons.error, color: Colors.white, size: 48),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.image, color: Colors.white, size: 48),
                        ),
            ),
          );
        },
      ),
    );
  }
}

