import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AnswerHeaderRow extends StatefulWidget {
  final List<String> baseTags;
  final List<Map<String, dynamic>> sources;

  const AnswerHeaderRow({
    super.key,
    required this.baseTags,
    required this.sources,
  });

  @override
  State<AnswerHeaderRow> createState() => _AnswerHeaderRowState();
}

class _AnswerHeaderRowState extends State<AnswerHeaderRow>
    with SingleTickerProviderStateMixin {
  bool showSources = false;
  final GlobalKey _sourcesKey = GlobalKey();

  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleOverlay() {
    if (showSources) {
      _removeOverlay();
      setState(() => showSources = false);
    } else {
      _showOverlay();
      setState(() => showSources = true);
    }
  }

  void _showOverlay() {
    
    _showSourcesBottomSheet(context);
  }

  void _showSourcesBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSourcesBottomSheet(context),
    );
  }

  Widget _buildSourcesBottomSheet(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
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
            child: Row(
              children: [
                const Text(
                  'Sources',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.sources.length}',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Sources list
          Flexible(
            child: widget.sources.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'No sources available',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.sources.length,
                    itemBuilder: (context, index) {
                      final s = widget.sources[index];
                      final title = s['title']?.toString() ?? 'Untitled';
                      final link = s['link']?.toString() ?? s['url']?.toString() ?? '';
                      final snippet = s['snippet']?.toString() ?? '';
                      
                      return ListTile(
                        leading: const Icon(
                          Icons.link,
                          color: Colors.blueGrey,
                          size: 20,
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: snippet.isNotEmpty
                            ? Text(
                                snippet,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              )
                            : null,
                        trailing: const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey,
                        ),
                        onTap: link.isNotEmpty
                            ? () async {
                                Navigator.pop(context);
                                final uri = Uri.parse(link);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              }
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Base static tags
          ...widget.baseTags.map(
            (tag) => Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Chip(
                label: Text(
                  tag,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              ),
            ),
          ),
          // Sources dropdown chip (only show when sources are available)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: widget.sources.isNotEmpty
                ? Padding(
                    key: const ValueKey('sources-chip'),
                    padding: const EdgeInsets.only(right: 8.0),
                    child: GestureDetector(
                      key: _sourcesKey,
                      onTap: () => _showSourcesBottomSheet(context),
                      child: Chip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Sources (${widget.sources.length})"),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 12,
                              color: Colors.blueGrey,
                            ),
                          ],
                        ),
                        backgroundColor: Colors.blue.shade50,
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no-sources')),
        ),
        ],
      ),
    );
  }
}

