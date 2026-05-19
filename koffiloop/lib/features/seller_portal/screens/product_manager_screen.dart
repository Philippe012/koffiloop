import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'dart:io';

class ProductManagerScreen extends StatefulWidget {
  final String shopId;
  final bool manageStock;

  const ProductManagerScreen(
      {super.key, required this.shopId, this.manageStock = false});

  @override
  State<ProductManagerScreen> createState() =>
      _ProductManagerScreenState();
}

class _ProductManagerScreenState extends State<ProductManagerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String? _editingId;
  File? _imageFile;
  String? _existingImageUrl;
  bool _uploading = false;
  bool _showForm = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? img = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null && mounted) setState(() => _imageFile = File(img.path));
  }

    Future<String?> _uploadImage() async {
    if (_imageFile == null) return _existingImageUrl;
    return await _uploadImageToCloudinary(_imageFile!);
  }

  Future<String> _uploadImageToCloudinary(File file) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/dyyzgowpd/upload',
    );

    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = 'koffiloop_upload';
    request.fields['folder'] = 'koffiloop';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String;
    }

    throw Exception(
      'Cloudinary upload failed (${response.statusCode}): ${response.body}',
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _uploading = true);
    try {
      final imageUrl = await _uploadImage();
      final product = {
        'name': _nameCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'description': _descCtrl.text.trim(),
        'imageUrl': imageUrl ?? '',
        'inStock': true,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final col = FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('products');

      if (_editingId != null) {
        await col.doc(_editingId).update(product);
        _showSnack('Product updated', AppTheme.success);
      } else {
        await col.add(product);
        _showSnack('Product added to menu', AppTheme.success);
      }
      _clearForm();
    } catch (e) {
      _showSnack('Error: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleStock(String id, bool current) async {
    await FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .collection('products')
        .doc(id)
        .update({'inStock': !current});
  }

  Future<void> _deleteProduct(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FirebaseFirestore.instance
        .collection('shops')
        .doc(widget.shopId)
        .collection('products')
        .doc(id)
        .delete();
    _showSnack('Product deleted', AppTheme.warning);
  }

  void _editProduct(String id, Map<String, dynamic> data) {
    setState(() {
      _editingId = id;
      _nameCtrl.text = data['name'] ?? '';
      _priceCtrl.text = (data['price'] ?? 0.0).toString();
      _descCtrl.text = data['description'] ?? '';
      _existingImageUrl = data['imageUrl'] ?? '';
      _imageFile = null;
      _showForm = true;
    });
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _nameCtrl.clear();
    _priceCtrl.clear();
    _descCtrl.clear();
    setState(() {
      _editingId = null;
      _imageFile = null;
      _existingImageUrl = null;
      _showForm = false;
    });
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.manageStock ? 'Manage Stock' : 'Products'),
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Georgia',
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_showForm)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: _clearForm,
            )
          else if (!widget.manageStock)
            IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              onPressed: () => setState(() => _showForm = true),
              tooltip: 'Add Product',
            ),
        ],
      ),
      
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          bottom: keyboardHeight + 20, 
          top: 8,
          left: 16,
          right: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showForm)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: _buildForm(isDark),
              ),

            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: _buildProductList(isDark),
            ),
            
            SizedBox(height: 80),
          ],
        ),
      ),
      
      floatingActionButton: !widget.manageStock && !_showForm
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = true),
              backgroundColor: AppTheme.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add Product',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
    );
  }

  Widget _buildForm(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _editingId != null ? 'Edit Product' : 'New Product',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                fontFamily: 'Georgia',
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.textPrimary,
              ),
            ),

            const SizedBox(height: 14),

            Row(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 90,
                    height: 90,
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
                        : _existingImageUrl != null &&
                                _existingImageUrl!.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: CachedNetworkImage(
                                  imageUrl: _existingImageUrl!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_rounded),
                  ),
                ),
                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Name required' : null,
                        decoration: const InputDecoration(
                          hintText: 'Product name',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Price required';
                          if (double.tryParse(v) == null) return 'Invalid price';
                          return null;
                        },
                        decoration: const InputDecoration(
                          hintText: 'Price',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            TextFormField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Description',
              ),
            ),

            const SizedBox(height: 16),

            GestureDetector(
              onTap: _uploading ? null : _saveProduct,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _uploading
                        ? [Colors.grey, Colors.grey]
                        : [AppTheme.primary, AppTheme.primaryDark],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _uploading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _editingId != null ? 'Update Product' : 'Add to Menu',
                          style: const TextStyle(color: Colors.white),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductList(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('products')
          .orderBy('updatedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child:
                  CircularProgressIndicator(color: AppTheme.primary));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.manageStock
                      ? Icons.inventory_2_outlined
                      : Icons.menu_book_outlined,
                  size: 64,
                  color: isDark
                      ? Colors.grey.shade600
                      : Colors.grey.shade300,
                ),
                const SizedBox(height: 16),
                Text(
                  'No products yet',
                  style: TextStyle(
                    fontSize: 17,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap + to add your first product',
                  style: TextStyle(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 
                MediaQuery.of(context).viewInsets.bottom + 100),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (_, i) {
            final doc = snapshot.data!.docs[i];
            final p = doc.data() as Map<String, dynamic>;
            return _ProductItem(
              id: doc.id,
              data: p,
              isDark: isDark,
              manageStock: widget.manageStock,
              onEdit: () => _editProduct(doc.id, p),
              onDelete: () => _deleteProduct(doc.id),
              onToggle: () => _toggleStock(doc.id, p['inStock'] ?? true),
            );
          },
        );
      },
    );
  }
}

class _ProductItem extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final bool isDark;
  final bool manageStock;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _ProductItem({
    required this.id,
    required this.data,
    required this.isDark,
    required this.manageStock,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final inStock = data['inStock'] ?? true;
    final imgUrl = data['imageUrl'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Row(
        children: [
          // Image
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkElevated
                  : AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: imgUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: imgUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.coffee_rounded,
                          color: AppTheme.primary),
                    ),
                  )
                : const Icon(Icons.coffee_rounded,
                    color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name'] ?? '',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '\$${(data['price'] as num).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: inStock
                            ? AppTheme.success.withValues(alpha: 0.12)
                            : Colors.grey.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        inStock ? 'In Stock' : 'Out of Stock',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: inStock
                              ? AppTheme.success
                              : (isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions
          if (manageStock)
            IconButton(
              icon: Icon(
                inStock
                    ? Icons.toggle_on_rounded
                    : Icons.toggle_off_rounded,
                color: inStock ? AppTheme.success : Colors.grey,
                size: 30,
              ),
              onPressed: onToggle,
              tooltip:
                  inStock ? 'Mark out of stock' : 'Mark in stock',
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: AppTheme.error,
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
          ],
        ],
      ),
    );
  }
}