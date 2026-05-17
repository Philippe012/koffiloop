import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});

  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  File? _imageFile;
  String? _existingImageUrl;
  bool _saving = false;
  bool _isOpen = true;
  bool _locating = false;
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    _loadShopData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShopData() async {
    final auth = context.read<AuthService>();
    final doc = await FirebaseFirestore.instance
        .collection('shops')
        .doc(auth.uid)
        .get();
    if (doc.exists && mounted) {
      final data = doc.data()!;
      setState(() {
        _nameCtrl.text = data['name'] ?? '';
        _cityCtrl.text = data['city'] ?? '';
        _descCtrl.text = data['description'] ?? '';
        _existingImageUrl = data['shopImageUrl'] ?? '';
        _isOpen = data['isOpen'] ?? true;
        _lat = (data['latitude'] as num?)?.toDouble();
        _lng = (data['longitude'] as num?)?.toDouble();
      });
    }
  }

  Future<void> _pickImage() async {
    final XFile? img =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null && mounted) {
      setState(() => _imageFile = File(img.path));
    }
  }

  Future<void> _fetchLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _showError('Location permission denied. Enable it in settings.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
        _showSuccess('Location captured successfully.');
      }
    } catch (e) {
      _showError('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<String?> _uploadImageToCloudinary(File file) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/dyyzgowpd/upload',
    );
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = 'koffiloop_upload';
    request.fields['folder'] = 'koffiloop';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (streamedResponse.statusCode >= 200 &&
        streamedResponse.statusCode < 300) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String?;
    }

    throw Exception(
      'Cloudinary upload failed (${streamedResponse.statusCode}): ${response.body}',
    );
  }

 Future<void> _saveShop() async {
  if (!_formKey.currentState!.validate()) return;
  final auth = context.read<AuthService>();

  setState(() => _saving = true);

  try {
    String? imageUrl = _existingImageUrl;

    if (_imageFile != null) {
      imageUrl = await _uploadImageToCloudinary(_imageFile!);
    }

    await FirebaseFirestore.instance
        .collection('shops')
        .doc(auth.uid)
        .set({
      'sellerId': auth.uid,
      'name': _nameCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'shopImageUrl': imageUrl ?? '',
      'isOpen': _isOpen,
      if (_lat != null) 'latitude': _lat,
      if (_lng != null) 'longitude': _lng,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _showSuccess('Shop settings saved.');
  } on FirebaseException catch (e) {
    _showError('Failed to save: ${e.message ?? e.code}');
  } catch (e) {
    _showError('Failed to save: $e');
  } finally {
    if (mounted) setState(() => _saving = false);
  }
} 
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg), backgroundColor: AppTheme.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Shop Settings'),
        backgroundColor:
            isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Georgia',
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo picker
              _SectionCard(
                isDark: isDark,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 180,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppTheme.darkElevated
                                  : AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _imageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.file(_imageFile!, fit: BoxFit.cover),
                                )
                              : (_existingImageUrl != null && _existingImageUrl!.isNotEmpty)
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.network(_existingImageUrl!, fit: BoxFit.cover),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate_rounded,
                                            size: 48,
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.textSecondary),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Tap to upload shop photo',
                                          style: TextStyle(
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                          ),
                          Positioned(
                            bottom: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Shop info
              _SectionCard(
                isDark: isDark,
                child: Column(
                  children: [
                    _FormField(
                      controller: _nameCtrl,
                      label: 'Shop Name',
                      icon: Icons.storefront_rounded,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _FormField(
                      controller: _cityCtrl,
                      label: 'City',
                      icon: Icons.location_city_rounded,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    _FormField(
                      controller: _descCtrl,
                      label: 'Description (optional)',
                      icon: Icons.description_outlined,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Location
              _SectionCard(
                isDark: isDark,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shop Location',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Used to show your café on the map and calculate distances',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_lat != null && _lng != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded,
                                color: AppTheme.success, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
                              style: const TextStyle(
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    GestureDetector(
                      onTap: _locating ? null : _fetchLocation,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.darkElevated
                              : AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.darkDivider
                                : AppTheme.divider,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_locating)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary),
                              )
                            else
                              const Icon(Icons.my_location_rounded,
                                  color: AppTheme.primary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _locating
                                  ? 'Getting location...'
                                  : 'Use current location',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Status toggle
              _SectionCard(
                isDark: isDark,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shop Status',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            _isOpen
                                ? 'Visible and accepting orders'
                                : 'Hidden from customers',
                            style: TextStyle(
                              fontSize: 13,
                              color: _isOpen
                                  ? AppTheme.success
                                  : (isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isOpen,
                      onChanged: (v) => setState(() => _isOpen = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Save button
              GestureDetector(
                onTap: _saving ? null : _saveShop,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _saving
                          ? [Colors.grey.shade400, Colors.grey.shade400]
                          : [AppTheme.primary, AppTheme.primaryDark],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _saving ? [] : AppTheme.buttonShadow,
                  ),
                  child: Center(
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text(
                            'Save Shop Settings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: child,
    );
  }
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}