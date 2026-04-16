import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/cart_service.dart';
import 'package:koffiloop/features/cart_checkout/screens/checkout_screen.dart';
import 'package:koffiloop/features/order_tracking/screens/order_status_screen.dart';

class CustomerDashboard extends StatelessWidget {
  const CustomerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('☕ My Coffee Feed'),
        actions: [
          // Cart with badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () {
                  if (context.read<CartService>().cart.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Your cart is empty'), behavior: SnackBarBehavior.floating),
                    );
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                },
              ),
              Consumer<CartService>(
                builder: (context, cart, _) => cart.itemCount > 0
                    ? Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.warning,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${cart.itemCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
          // Orders
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderStatusScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome Banner
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppTheme.primary, AppTheme.secondary]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.waving_hand, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Good day, Coffee Lover!', 
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Discover your next favorite brew', 
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Shop Grid
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('shops')
                  .where('isOpen', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async => await Future.delayed(const Duration(milliseconds: 500)),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final shop = snapshot.data!.docs[index];
                      return _CustomerShopCard(shop: shop);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.local_cafe_outlined, size: 72, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No cafés available right now', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text('Try again later or invite your favorite café to join!', 
              style: TextStyle(color: Colors.grey.shade500), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// Customer-facing Shop Card (with Add to Cart)
class _CustomerShopCard extends StatelessWidget {
  final QueryDocumentSnapshot shop;
  const _CustomerShopCard({required this.shop});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shop Header
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.secondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.local_cafe, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop['name'] ?? 'Café', 
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      Text(shop['city'] ?? '', 
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Chip(
                  label: const Text('Open', style: TextStyle(fontSize: 12, color: Colors.white)),
                  backgroundColor: AppTheme.success,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Products Grid
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('shops')
                  .doc(shop.id)
                  .collection('products')
                  .where('inStock', isEqualTo: true)
                  .limit(4)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                final products = snap.data!.docs;
                if (products.isEmpty) return const Text('No items in stock', style: TextStyle(color: Colors.grey));
                
                return SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final doc = products[index];
                      final p = doc.data() as Map<String, dynamic>;
                      return _ProductChip(
                        name: p['name'] ?? 'Item',
                        price: (p['price'] as num).toDouble(),
                        onAdd: () {
                          context.read<CartService>().setShop(shop.id);
                          context.read<CartService>().add(doc.id, p['name'], (p['price'] as num).toDouble());
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✓ ${p['name']} added'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
            // View All Button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('View Full Menu'),
                onPressed: () => _showFullMenu(context, shop.id, shop['name']),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullMenu(BuildContext context, String shopId, String shopName) {
    context.read<CartService>().setShop(shopId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.restaurant_menu, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$shopName Menu',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('shops')
                      .doc(shopId)
                      .collection('products')
                      .where('inStock', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('Menu loading...', style: TextStyle(color: Colors.grey)),
                      ));
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: snap.data!.docs.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final doc = snap.data!.docs[index];
                        final p = doc.data() as Map<String, dynamic>;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p['name'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(p['description'] ?? ''),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('\$${(p['price'] as num).toStringAsFixed(2)}', 
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                                onPressed: () {
                                  context.read<CartService>().add(doc.id, p['name'], (p['price'] as num).toDouble());
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✓ ${p['name']} added to cart'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Cart Summary
              Consumer<CartService>(
                builder: (context, cart, _) => cart.cart.isEmpty 
                    ? const SizedBox() 
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          border: Border(top: BorderSide(color: Colors.grey.shade200)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${cart.itemCount} items · \$${cart.total.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                              },
                              child: const Text('Checkout'),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Reusable Product Chip Widget
class _ProductChip extends StatelessWidget {
  final String name;
  final double price;
  final VoidCallback onAdd;
  const _ProductChip({required this.name, required this.price, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\$${price.toStringAsFixed(2)}', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
              IconButton(
                icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 24),
                onPressed: onAdd,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}