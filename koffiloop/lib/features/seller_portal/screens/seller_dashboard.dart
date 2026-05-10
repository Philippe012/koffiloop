import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/services/notification_service.dart';
import 'package:koffiloop/features/seller_portal/screens/product_manager_screen.dart';
import 'package:koffiloop/features/seller_portal/screens/shop_settings_screen.dart';
import 'package:koffiloop/models/order_model.dart';

class SellerDashboard extends StatefulWidget {
  const SellerDashboard({super.key});

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  void _initNotifications() {
    if (!mounted) return;
    final uid = context.read<AuthService>().uid;
    if (uid.isNotEmpty) {
      NotificationService().init(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          _buildAppBar(isDark, auth),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              _StatsRow(sellerId: auth.uid, isDark: isDark),
              const SizedBox(height: 24),
              _SectionHeader(
                  title: 'Quick Actions', isDark: isDark),
              const SizedBox(height: 12),
              _buildQuickActions(context, auth.uid, isDark),
              const SizedBox(height: 24),
              _SectionHeader(
                  title: 'Active Orders', isDark: isDark),
              const SizedBox(height: 12),
              _OrdersList(sellerId: auth.uid, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(bool isDark, AuthService auth) {
    return SliverAppBar(
      pinned: true,
      backgroundColor:
          isDark ? AppTheme.darkSurface : AppTheme.primary,
      foregroundColor: Colors.white,
      title: const Text(
        'Seller Dashboard',
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        // Messages
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline_rounded,
              color: Colors.white),
          onPressed: () =>
              Navigator.pushNamed(context, '/seller-messages',
                  arguments: {'shopId': auth.uid}),
          tooltip: 'Customer Messages',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ShopSettingsScreen())),
          tooltip: 'Shop Settings',
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white),
          onPressed: () async {
            await context.read<AuthService>().logout();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/landing', (r) => false);
            }
          },
          tooltip: 'Sign Out',
        ),
      ],
    );
  }

  Widget _buildQuickActions(
      BuildContext context, String uid, bool isDark) {
    final actions = [
      _QuickAction(
        icon: Icons.add_circle_outline_rounded,
        label: 'Add Product',
        subtitle: 'List a new item',
        color: AppTheme.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProductManagerScreen(shopId: uid)),
        ),
      ),
      _QuickAction(
        icon: Icons.inventory_2_outlined,
        label: 'Manage Stock',
        subtitle: 'Update availability',
        color: AppTheme.secondary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ProductManagerScreen(shopId: uid, manageStock: true)),
        ),
      ),
      _QuickAction(
        icon: Icons.storefront_rounded,
        label: 'Shop Settings',
        subtitle: 'Edit your profile',
        color: AppTheme.info,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ShopSettingsScreen()),
        ),
      ),
      _QuickAction(
        icon: Icons.bar_chart_rounded,
        label: 'Analytics',
        subtitle: 'View performance',
        color: AppTheme.success,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Analytics coming soon')),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: actions.length,
      itemBuilder: (_, i) => _QuickActionCard(
          action: actions[i], isDark: isDark),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final String sellerId;
  final bool isDark;

  const _StatsRow({required this.sellerId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            label: "Today's Orders",
            icon: Icons.receipt_long_rounded,
            color: AppTheme.primary,
            isDark: isDark,
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('sellerId', isEqualTo: sellerId)
                .where('createdAt',
                    isGreaterThanOrEqualTo: DateTime.now()
                        .subtract(const Duration(hours: 24)))
                .snapshots(),
            builder: (snap) => Text(
              snap.hasData ? '${snap.data!.docs.length}' : '0',
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Georgia',
                  color: AppTheme.primary),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            label: 'Total Revenue',
            icon: Icons.attach_money_rounded,
            color: AppTheme.success,
            isDark: isDark,
            stream: FirebaseFirestore.instance
                .collection('orders')
                .where('sellerId', isEqualTo: sellerId)
                .where('status', isEqualTo: 'completed')
                .snapshots(),
            builder: (snap) {
              if (!snap.hasData) {
                return const Text('\$0.00',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success));
              }
              final total = snap.data!.docs.fold(0.0, (acc, doc) {
                final d = doc.data() as Map<String, dynamic>;
                return acc + ((d['total'] ?? 0) as num).toDouble();
              });
              return Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Georgia',
                    color: AppTheme.success),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isDark;
  final Stream<QuerySnapshot> stream;
  final Widget Function(AsyncSnapshot<QuerySnapshot>) builder;

  const _StatCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.stream,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot>(
              stream: stream, builder: (_, snap) => builder(snap)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _QuickActionCard extends StatelessWidget {
  final _QuickAction action;
  final bool isDark;

  const _QuickActionCard(
      {required this.action, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.cardShadow(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: action.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(action.icon, color: action.color, size: 22),
            ),
            const Spacer(),
            Text(
              action.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              action.subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: 'Georgia',
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
      ),
    );
  }
}

class _OrdersList extends StatelessWidget {
  final String sellerId;
  final bool isDark;

  const _OrdersList({required this.sellerId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: sellerId)
          .where('status', whereIn: ['pending', 'preparing', 'ready'])
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(
                      color: AppTheme.primary)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.cardShadow(isDark),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    size: 48,
                    color: isDark
                        ? Colors.grey.shade600
                        : Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  'All caught up!',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'No active orders right now',
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final order = OrderModel.fromFirestore(
                doc.data() as Map<String, dynamic>, doc.id);
            return _OrderCard(
              order: order,
              isDark: isDark,
              onUpdate: (status) async {
                await FirebaseFirestore.instance
                    .collection('orders')
                    .doc(order.id)
                    .update({'status': status});
                // Notify customer via FCM
                await NotificationService().sendOrderUpdate(
                  orderId: order.id,
                  customerId: order.customerId,
                  status: status,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final bool isDark;
  final void Function(String) onUpdate;

  const _OrderCard(
      {required this.order, required this.isDark, required this.onUpdate});

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return AppTheme.warning;
      case 'preparing':
        return AppTheme.info;
      case 'ready':
        return AppTheme.success;
      case 'completed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready';
      case 'completed':
        return 'Completed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #${order.id.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color:
                      _statusColor(order.status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _statusLabel(order.status),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(order.status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
              color: isDark ? AppTheme.darkDivider : Colors.grey.shade100,
              height: 1),
          const SizedBox(height: 10),
          ...order.items.entries.map((e) {
            final item = e.value as Map<String, dynamic>;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['name']} × ${item['qty']}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '\$${((item['price'] as num) * (item['qty'] as num)).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }),
          Divider(
              color: isDark ? AppTheme.darkDivider : Colors.grey.shade100,
              height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: \$${order.total.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: AppTheme.primary),
              ),
              Text(
                order.createdAt.toString().substring(0, 16),
                style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (order.status == 'pending')
            _actionButton(
              label: 'Accept Order',
              icon: Icons.check_rounded,
              color: AppTheme.primary,
              onTap: () => onUpdate('preparing'),
            )
          else if (order.status == 'preparing')
            _actionButton(
              label: 'Mark as Ready',
              icon: Icons.coffee_rounded,
              color: AppTheme.success,
              onTap: () => onUpdate('ready'),
            )
          else if (order.status == 'ready')
            _actionButton(
              label: 'Complete Order',
              icon: Icons.done_all_rounded,
              color: AppTheme.info,
              onTap: () => onUpdate('completed'),
            ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}