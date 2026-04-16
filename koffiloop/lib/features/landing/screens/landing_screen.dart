import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/features/auth/screens/login_screen.dart';

// ✅ FIXED: Convert to StatefulWidget to manage ScrollController
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _shopListKey = GlobalKey();

  void _scrollToShops() {
    _scrollController.animateTo(
      250, // Adjust based on banner height (~250px)
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose(); // ✅ Now valid in State class
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Dynamic theme-aware colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgGradient = isDark
        ? LinearGradient(
            colors: [
              AppTheme.primary.withValues(alpha: 0.9),
              AppTheme.secondary.withValues(alpha: 0.7)
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [AppTheme.primary, AppTheme.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBackground : AppTheme.background,
      appBar: AppBar(
        title: const Text('☕ KofiLoop'),
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.login, color: Colors.white),
            label: const Text('Sign In', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // 🎨 Hero Banner with Background Image
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: bgGradient,
              image: DecorationImage(
                image: AssetImage('assets/images/coffee_bg.jpeg'),
                fit: BoxFit.cover,
                opacity: isDark ? 0.1 : 0.15, // Subtle overlay
              ),
            ),
            child: Column(
              children: [
                // Logo Image
                Image.asset(
                  'assets/images/logo-white.png',
                  height: 80,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.local_cafe, size: 56, color: Colors.white),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Discover Amazing Coffee Near You',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Browse cafés, view menus, and order ahead — no account needed to explore!',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // ✅ FIXED: Single onPressed, beautiful button
                ElevatedButton.icon(
                  onPressed: _scrollToShops,
                  icon: const Icon(Icons.search),
                  label: const Text('Start Exploring'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 4,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            key: _shopListKey,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('shops')
                  .where('isOpen', isEqualTo: true)
                  .snapshots(),
              builder: (context, snapshot) {
                // ✅ 1. Loading state
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: isDark ? AppTheme.secondary : AppTheme.primary,
                    ),
                  );
                }
                
                // ✅ 2. Error state
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: isDark ? Colors.red.shade300 : Colors.red),
                    ),
                  );
                }
                
                // ✅ 3. Safe null check for data
                final docs = snapshot.data?.docs;
                if (docs == null || docs.isEmpty) {
                  return _buildEmptyState(isDark);
                }
                
                // ✅ 4. Now safe to build list
                return RefreshIndicator(
                  onRefresh: () async =>
                      await Future.delayed(const Duration(milliseconds: 500)),
                  color: AppTheme.primary,
                  backgroundColor:
                      isDark ? AppTheme.darkSurface : Colors.white,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length, // ✅ Using safe 'docs' variable
                    itemBuilder: (context, index) {
                      final shop = docs[index]; // ✅ Safe access
                      return _ShopPreviewCard(shop: shop, isDark: isDark);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.small(
        onPressed: () => _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        ),
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primary,
        tooltip: 'Back to top', 
        child: const Icon(Icons.keyboard_arrow_up, color: Colors.white), 
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_cafe_outlined,
            size: 72,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No cafés listed yet',
            style: TextStyle(
                fontSize: 18,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            'Check back soon or become a seller!',
            style: TextStyle(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// 🛍️ Reusable Shop Preview Card (Public View)
class _ShopPreviewCard extends StatelessWidget {
  final QueryDocumentSnapshot shop;
  final bool isDark;
  const _ShopPreviewCard({required this.shop, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final shopData = shop.data() as Map<String, dynamic>;
    final shopImageUrl = shopData['shopImageUrl'] ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: isDark ? AppTheme.darkSurface : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showShopPreview(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // ✅ Shop Logo/Image with Fallback
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  image: shopImageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(shopImageUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: shopImageUrl.isEmpty
                    ? const Icon(Icons.local_cafe,
                        size: 36, color: AppTheme.primary)
                    : null,
              ),
              const SizedBox(width: 16),
              // Shop Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop['name'] ?? 'Unknown Café',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          shop['city'] ?? 'Location not set',
                          style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Preview Products (Public)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('shops')
                          .doc(shop.id)
                          .collection('products')
                          .where('inStock', isEqualTo: true)
                          .limit(3)
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox();
                        final products = snap.data!.docs
                            .take(3)
                            .map((d) => d.data() as Map<String, dynamic>)
                            .toList();
                        return Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: products.map((p) {
                            return Chip(
                              label: Text(
                                '${p['name']} · \$${(p['price'] as num).toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.textPrimary),
                              ),
                              backgroundColor:
                                  AppTheme.secondary.withValues(alpha: 0.15),
                              labelStyle: TextStyle(
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.textPrimary),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: isDark ? Colors.grey.shade400 : Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showShopPreview(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Header with Shop Image
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    // Shop Logo in Header
                    if (shop['shopImageUrl'] != null &&
                        (shop['shopImageUrl'] as String).isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          shop['shopImageUrl'],
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.storefront,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      )
                    else
                      const Icon(Icons.storefront,
                          color: Colors.white, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop['name'] ?? 'Café',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                          Text(
                            shop['city'] ?? '',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              // Products List
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('shops')
                      .doc(shop.id)
                      .collection('products')
                      .where('inStock', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return Center(
                          child:
                              CircularProgressIndicator(color: AppTheme.primary));
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No products available yet',
                            style: TextStyle(
                                color: isDark
                                    ? AppTheme.darkTextSecondary
                                    : Colors.grey),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: snap.data!.docs.length,
                      separatorBuilder: (_, __) => Divider(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200),
                      itemBuilder: (context, index) {
                        final doc = snap.data!.docs[index];
                        final p = doc.data() as Map<String, dynamic>;
                        final productImage = p['imageUrl'] ?? '';

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: productImage.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    productImage,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: AppTheme.secondary
                                            .withValues(alpha: 0.2),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.coffee,
                                          color: AppTheme.primary),
                                    ),
                                  ),
                                )
                              : Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: AppTheme.secondary
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.coffee,
                                      color: AppTheme.primary),
                                ),
                          title: Text(
                            p['name'] ?? 'Item',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppTheme.darkTextPrimary
                                  : AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: Text(p['description'] ?? ''),
                          trailing: Text(
                            '\$${(p['price'] as num).toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              // CTA to Login
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkBackground : AppTheme.background,
                  border: Border(
                      top: BorderSide(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200)),
                ),
                child: Column(
                  children: [
                    Text(
                      'Want to order? Sign in to get started!',
                      style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Sign In to Order'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}