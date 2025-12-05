import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http_parser/http_parser.dart';
import '../theme/AppColors.dart';
import '../theme/Typography.dart';
import '../models/Persona.dart';
import '../services/persona_service.dart'; // ✅ Express backend dev route
import '../core/api_client.dart'; // ✅ Express backend dev route

// State management enum
enum PersonaState { idle, creating, uploading, done, error }

// Data class for isolate communication
class UploadImageData {
  final String imagePath;
  final String token;
  
  UploadImageData(this.imagePath, this.token);
}

// Isolate function for heavy file operations
Future<String?> uploadImageInIsolate(UploadImageData data) async {
  final imagePath = data.imagePath;
  final token = data.token;
  try {
    final file = File(imagePath);
    final size = await file.length();
    final ext = imagePath.split('.').last.toLowerCase();

    final mimeType = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('http://10.0.2.2:4000/api/upload/single'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath(
      'image',
      file.path,
      contentType: MediaType.parse(mimeType),
    ));

    final streamed = await request.send().timeout(const Duration(seconds: 10));
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return 'http://10.0.2.2:4000${(data['data']['url'] as String?) ?? ''}'; // ✅ null-safe
      }
    }
    return null;
  } catch (e) {
    if (kDebugMode) print('Upload isolate error: $e');
    return null;
  }
}

// Safe HTTP request wrapper
Future<http.Response> safeRequest(Future<http.Response> future) async {
  try {
    return await future.timeout(const Duration(seconds: 8));
  } on TimeoutException {
    return http.Response(jsonEncode({'success': false, 'error': 'Request timeout'}), 408);
  } catch (e) {
    return http.Response(jsonEncode({'success': false, 'error': e.toString()}), 500);
  }
}

class CreatePersonaPage extends StatefulWidget {
  const CreatePersonaPage({super.key});

  @override
  State<CreatePersonaPage> createState() => _CreatePersonaPageState();
}

class _CreatePersonaPageState extends State<CreatePersonaPage> {
  final TextEditingController _personaNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  // Optimized state management
  final ValueNotifier<PersonaState> _personaState = ValueNotifier<PersonaState>(PersonaState.idle);
  final ValueNotifier<bool> _isSecret = ValueNotifier<bool>(false);
  final ValueNotifier<List<File>> _selectedImages = ValueNotifier<List<File>>([]);
  final ValueNotifier<File?> _coverImage = ValueNotifier<File?>(null);
  final ValueNotifier<List<String>> _tags = ValueNotifier<List<String>>([]);
  final ValueNotifier<String?> _errorMessage = ValueNotifier<String?>(null);
  final ValueNotifier<bool> _createButtonEnabled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _personaNameController.addListener(_updateCreateButtonState);
  }

  @override
  void dispose() {
    _personaNameController.removeListener(_updateCreateButtonState);
    _personaNameController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _personaState.dispose();
    _isSecret.dispose();
    _selectedImages.dispose();
    _coverImage.dispose();
    _tags.dispose();
    _errorMessage.dispose();
    _createButtonEnabled.dispose();
    super.dispose();
  }

  void _updateCreateButtonState() {
    // Trigger UI rebuild when text changes
    _personaNameController.addListener(() {
      _createButtonEnabled.value = _personaNameController.text.trim().isNotEmpty;
    });
  }

  bool get _isCreateButtonEnabled => _createButtonEnabled.value;

  Future<void> _pickCoverImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        _coverImage.value = File(image.path);
        _errorMessage.value = null;
      }
    } catch (e) {
      _errorMessage.value = 'Failed to pick image: $e';
    }
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage();
      if (images.isNotEmpty) {
        _selectedImages.value = images.map((image) => File(image.path)).toList();
        _errorMessage.value = null;
      }
    } catch (e) {
      _errorMessage.value = 'Failed to pick images: $e';
      }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.value.contains(tag)) {
      _tags.value = [..._tags.value, tag];
        _tagController.clear();
    }
  }

  void _removeTag(String tag) {
    _tags.value = _tags.value.where((t) => t != tag).toList();
  }

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');
      
      // 🔥 Dev Mode Bypass: Allow fake user even without token
      if (token == null || token.isEmpty) {
        debugPrint('🧪 Dev Mode: Using fake token for testing');
        token = 'dev-mode-token';
      }
      
      return token;
    } catch (e) {
      if (kDebugMode) print('Token retrieval error: $e');
      // Even on error, return fake token in dev mode
      debugPrint('🧪 Dev Mode: Using fake token due to error');
      return 'dev-mode-token';
    }
  }

  Future<void> _createPersona() async {
    if (!_isCreateButtonEnabled) return;

    _personaState.value = PersonaState.creating;
    _errorMessage.value = null;

    try {
      // 1️⃣ Upload cover image
      String? coverImageUrl;
      if (_coverImage.value != null) {
        _personaState.value = PersonaState.uploading;
        coverImageUrl = await _uploadImage(_coverImage.value!);
        if (coverImageUrl == null) {
          _errorMessage.value = 'Failed to upload cover image';
          _personaState.value = PersonaState.error;
          return;
        }
      }

      // 2️⃣ Upload additional images (if any)
      final List<String> extraUrls = [];
      for (final img in _selectedImages.value) {
        final url = await _uploadImage(File(img.path));
        if (url != null) extraUrls.add(url);
      }

      // 3️⃣ Create persona using PersonaService (✅ Express backend dev route)
      final persona = await PersonaService.createPersona(
        name: _personaNameController.text.trim(),
        description: _descriptionController.text.trim(),
        coverImageUrl: coverImageUrl,
        tags: _tags.value,
        extraImageUrls: extraUrls,
        isSecret: _isSecret.value,
      );

      _personaState.value = PersonaState.done;
      _showSuccessAndNavigate();
    } catch (e) {
      _errorMessage.value = 'Error creating persona: $e';
      _personaState.value = PersonaState.error;
    }
  }

  Future<String?> _uploadImage(File image) async {
    try {
      // ✅ Express backend dev route - Use ApiClient for upload
      final response = await ApiClient.upload('/upload/single', image, 'image');
      final body = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        return data["url"];
      }
      if (kDebugMode) print("❌ Upload failed: $body");
      return null;
    } catch (e) {
      if (kDebugMode) print("❌ Upload error: $e");
      return null;
    }
  }

  Future<void> _uploadAdditionalImages(String personaId, String token) async {
    try {
      for (final imageFile in _selectedImages.value) {
        final imageUrl = await compute(uploadImageInIsolate, UploadImageData(imageFile.path, token));
        if (imageUrl != null) {
          await safeRequest(
            http.post(
              Uri.parse('http://10.0.2.2:4000/api/personas/$personaId/items'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode({
                'image_url': imageUrl,
                'title': '',
                'description': '',
              }),
            ),
          );
        }
      }
      _personaState.value = PersonaState.done;
      _showSuccessAndNavigate();
    } catch (e) {
      if (kDebugMode) print('Error uploading additional images: $e');
      _personaState.value = PersonaState.done;
      _showSuccessAndNavigate();
    }
  }

  void _showSuccessAndNavigate() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Persona created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            if (mounted) Navigator.of(context).maybePop();
          },
        ),
        title: Text(
          'Create Persona',
          style: AppTypography.headline2.copyWith(color: AppColors.textPrimary),
        ),
        centerTitle: true,
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: _createButtonEnabled,
            builder: (context, isEnabled, child) {
              return TextButton(
                onPressed: isEnabled ? _createPersona : null,
                style: TextButton.styleFrom(
                  foregroundColor: isEnabled ? AppColors.primary : AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              child: Text(
                'Create',
                  style: AppTypography.title2.copyWith(
                    color: isEnabled ? AppColors.primary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<PersonaState>(
        valueListenable: _personaState,
        builder: (context, state, child) {
          if (state == PersonaState.creating || state == PersonaState.uploading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Creating persona...'),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Persona Name
              Text(
                'Persona Name',
                  style: AppTypography.headline3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
                TextField(
                  controller: _personaNameController,
                  decoration: InputDecoration(
                    hintText: 'Enter persona name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              
              // Description
              Text(
                'Description (Optional)',
                  style: AppTypography.headline3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Describe your persona',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              
                // Cover Image
              Text(
                'Cover Image',
                  style: AppTypography.headline3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
                ValueListenableBuilder<File?>(
                  valueListenable: _coverImage,
                  builder: (context, coverImage, child) {
                    return GestureDetector(
                      onTap: _pickCoverImage,
                      child: Container(
                        height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                ),
                        child: coverImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                                  coverImage,
                              fit: BoxFit.cover,
                            ),
                              )
                            : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                                    Icon(Icons.add_photo_alternate, size: 32, color: AppColors.textSecondary),
                                    SizedBox(height: 8),
                                    Text('Tap to add cover image'),
                                  ],
                                ),
                        ),
                      ),
                    );
                  },
              ),
              const SizedBox(height: 24),
              
                // Additional Images
                Text(
                  'Additional Images',
                  style: AppTypography.headline3.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<List<File>>(
                  valueListenable: _selectedImages,
                  builder: (context, images, child) {
                    return GestureDetector(
                      onTap: _pickImages,
                              child: Container(
                        height: 80,
                        width: double.infinity,
                                decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(8),
                        ),
                        child: images.isNotEmpty
                            ? ListView.builder(
                                key: const PageStorageKey('persona_images'),
                                scrollDirection: Axis.horizontal,
                                itemCount: images.length,
                                itemBuilder: (context, index) {
                                  return Container(
                                    margin: const EdgeInsets.all(4),
                                    width: 70,
                                    height: 70,
                                child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                  child: Image.file(
                                        images[index],
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                  );
                                },
                              )
                            : const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, size: 24, color: AppColors.textSecondary),
                                    Text('Tap to add images'),
                                  ],
                              ),
                            ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),
              
                // Tags
              Text(
                'Tags',
                  style: AppTypography.headline3.copyWith(color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                        controller: _tagController,
                        decoration: InputDecoration(
                          hintText: 'Add a tag',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addTag,
                    child: const Text('Add'),
                  ),
                ],
              ),
                const SizedBox(height: 8),
                ValueListenableBuilder<List<String>>(
                  valueListenable: _tags,
                  builder: (context, tags, child) {
                    return Wrap(
                      children: tags.map((tag) => Chip(
                    label: Text(tag),
                    onDeleted: () => _removeTag(tag),
                        deleteIcon: const Icon(Icons.close, size: 16),
                  )).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Secret toggle
                ValueListenableBuilder<bool>(
                  valueListenable: _isSecret,
                  builder: (context, isSecret, child) {
                    return Row(
                  children: [
                        Checkbox(
                          value: isSecret,
                          onChanged: (value) => _isSecret.value = value ?? false,
                        ),
                        const Text('Keep this persona private'),
                      ],
                    );
                  },
                          ),
                const SizedBox(height: 32),

                // Error message
                ValueListenableBuilder<String?>(
                  valueListenable: _errorMessage,
                  builder: (context, errorMessage, child) {
                    if (errorMessage == null) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red),
                    ),
                    );
                  },
              ),
              
            ],
          ),
          );
        },
      ),
    );
  }
}
