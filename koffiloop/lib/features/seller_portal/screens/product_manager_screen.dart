import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:koffiloop/core/theme/app_theme.dart';

class ProductManagerScreen extends StatefulWidget {
  final String shopId;
  final bool manageStock;
  const ProductManagerScreen({super.key, required this.shopId, this.manageStock = false});

  @override State<ProductManagerScreen> createState() => _ProductManagerScreenState();
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
  final ImagePicker _picker = ImagePicker();

  @override void dispose() {
    _nameCtrl.dispose(); _priceCtrl.dispose(); _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _imageFile = File(image.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return _existingImageUrl;
    
    setState(() => _uploading = true);
    try {
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_${_nameCtrl.text.replaceAll(' ', '_')}';
      final Reference ref = FirebaseStorage.instance
          .ref()
          .child('products')
          .child(widget.shopId)
          .child(fileName);
      
      await ref.putFile(_imageFile!);
      final String downloadUrl = await ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    
    final imageUrl = await _uploadImage();
    if (imageUrl == null && _imageFile != null) return;
    
    final product = {
      'name': _nameCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text) ?? 0.0,
      'description': _descCtrl.text.trim(),
      'imageUrl': imageUrl ?? _existingImageUrl ?? '',
      'inStock': true,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_editingId != null) {
        await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.shopId)
            .collection('products')
            .doc(_editingId)
            .update(product);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Product updated'), behavior: SnackBarBehavior.floating),
          );
        }
      } else {
        await FirebaseFirestore.instance
            .collection('shops')
            .doc(widget.shopId)
            .collection('products')
            .add(product);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✓ Product added'), behavior: SnackBarBehavior.floating),
          );
        }
      }
      _clearForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleStock(String productId, bool current) async {
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('products')
          .doc(productId)
          .update({'inStock': !current});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteProduct(String productId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .collection('products')
          .doc(productId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Product deleted'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _nameCtrl.clear(); _priceCtrl.clear(); _descCtrl.clear();
    setState(() {
      _editingId = null;
      _imageFile = null;
      _existingImageUrl = null;
    });
  }

  void _editProduct(String id, Map<String, dynamic> data) {
    setState(() {
      _editingId = id;
      _nameCtrl.text = data['name'] ?? '';
      _priceCtrl.text = (data['price'] ?? 0.0).toString();
      _descCtrl.text = data['description'] ?? '';
      _existingImageUrl = data['imageUrl'] ?? '';
    });
    // Scrollable.ensureVisible(context.findRenderObject()!, duration: const Duration(milliseconds: 300));
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.manageStock ? '📦 Manage Stock' : '➕ Add Product'),
        actions: [
          if (_editingId != null)
            IconButton(icon: const Icon(Icons.close), onPressed: _clearForm),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_editingId != null ? '✏️ Edit Product' : '✨ New Product', 
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    // Image Picker
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 150,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade400),
                        ),
                        child: _imageFile != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(_imageFile!, fit: BoxFit.cover),
                              )
                            : _existingImageUrl != null && _existingImageUrl!.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(_existingImageUrl!, fit: BoxFit.cover),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey),
                                      SizedBox(height: 8),
                                      Text('Tap to add product image', style: TextStyle(color: Colors.grey)),
                                    ],
                                  ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Product Name *', prefixIcon: Icon(Icons.coffee)),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Price (\$) *', prefixIcon: Icon(Icons.attach_money)),
                      validator: (v) => v == null || double.tryParse(v) == null || double.parse(v) <= 0 ? 'Valid price required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.description), alignLabelWithHint: true),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _uploading 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Icon(_editingId != null ? Icons.save : Icons.add),
                            label: Text(_editingId != null ? 'Update Product' : 'Add to Menu'),
                            onPressed: _uploading ? null : _saveProduct,
                          ),
                        ),
                        if (_editingId != null) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.cancel),
                              label: const Text('Cancel'),
                              onPressed: _clearForm,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('shops')
                  .doc(widget.shopId)
                  .collection('products')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(widget.manageStock ? Icons.inventory_2_outlined : Icons.menu_book_outlined, 
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(widget.manageStock ? 'No products to manage' : 'Your menu is empty', 
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final p = doc.data() as Map<String, dynamic>;
                    return _ProductListItem(
                      id: doc.id,
                      name: p['name'] ?? 'Unnamed',
                      price: (p['price'] as num?)?.toDouble() ?? 0.0,
                      imageUrl: p['imageUrl'] ?? '',
                      inStock: p['inStock'] ?? true,
                      onEdit: () => _editProduct(doc.id, p),
                      onDelete: () => _deleteProduct(doc.id),
                      onToggleStock: () => _toggleStock(doc.id, p['inStock'] ?? true),
                      manageStockMode: widget.manageStock,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductListItem extends StatelessWidget {
  final String id;
  final String name;
  final double price;
  final String imageUrl;
  final bool inStock;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleStock;
  final bool manageStockMode;

  const _ProductListItem({
    required this.id, required this.name, required this.price, 
    required this.imageUrl, required this.inStock,
    required this.onEdit, required this.onDelete, 
    required this.onToggleStock, required this.manageStockMode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: imageUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(imageUrl, width: 60, height: 60, fit: BoxFit.cover),
              )
            : Container(
                width: 60, height: 60,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.coffee, color: Colors.grey),
              ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text('\$${price.toStringAsFixed(2)}${manageStockMode ? ' · ${inStock ? 'In Stock' : 'Out of Stock'}' : ''}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (manageStockMode)
              IconButton(
                icon: Icon(inStock ? Icons.check_circle : Icons.cancel_outlined, 
                    color: inStock ? AppTheme.success : Colors.grey),
                tooltip: inStock ? 'Mark as Out of Stock' : 'Mark as In Stock',
                onPressed: onToggleStock,
              ),
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit', onPressed: onEdit),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Delete', onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}