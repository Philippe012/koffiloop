import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/auth_service.dart';

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  static const _tabs = ['Active', 'Completed', 'All'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'My Orders',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Georgia',
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500, fontSize: 13),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _OrderList(
            uid: auth.uid,
            isDark: isDark,
            filterStatuses: const ['pending', 'preparing', 'ready'],
          ),
          _OrderList(
            uid: auth.uid,
            isDark: isDark,
            filterStatuses: const ['completed'],
          ),
          _OrderList(uid: auth.uid, isDark: isDark),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final String uid;
  final bool isDark;
  final List<String>? filterStatuses;

  const _OrderList({
    required this.uid,
    required this.isDark,
    this.filterStatuses,
  });

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('orders')
        .where('customerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    if (filterStatuses != null && filterStatuses!.length == 1) {
      query = query.where('status', isEqualTo: filterStatuses!.first);
    } else if (filterStatuses != null && filterStatuses!.isNotEmpty) {
      query = query.where('status', whereIn: filterStatuses);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton(isDark);
        }
        if (snapshot.hasError) {
          return _buildError(isDark, snapshot.error.toString());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildEmpty(isDark);
        }
        return RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: () =>
              Future.delayed(const Duration(milliseconds: 500)),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final doc = docs[i];
              final data = doc.data() as Map<String, dynamic>;
              return _OrderCard(
                orderId: doc.id,
                data: data,
                isDark: isDark,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 160,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  Widget _buildError(bool isDark, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 56,
              color:
                  isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Could not load orders',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your connection and try again',
            style: TextStyle(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'No orders here yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              color:
                  isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your order history will appear here\nonce you place your first order.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> data;
  final bool isDark;

  const _OrderCard({
    required this.orderId,
    required this.data,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final items = data['items'] as Map<String, dynamic>? ?? {};
    final status = data['status'] as String? ?? 'pending';
    final total = (data['total'] as num?)?.toDouble() ?? 0.0;
    final createdAt =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final paymentMethod =
        data['paymentMethod'] as String? ?? 'cash';

    return GestureDetector(
      onTap: () => _showOrderDetail(context, items, status, total,
          createdAt, paymentMethod),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppTheme.cardShadow(isDark),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: _statusColor(status).withValues(alpha: 0.07),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_statusIcon(status),
                        color: _statusColor(status), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${orderId.substring(0, 8).toUpperCase()}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: isDark
                                ? AppTheme.darkTextPrimary
                                : AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          _formatDate(createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadge(status: status),
                ],
              ),
            ),

            // Status tracker (active orders only)
            if (status != 'completed' && status != 'cancelled')
              _StatusTracker(status: status, isDark: isDark),

            // Items preview
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...items.entries.take(3).map((e) {
                    final item = e.value as Map<String, dynamic>;
                    final qty = item['qty'] as int? ?? 1;
                    final price = (item['price'] as num?)?.toDouble() ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${item['name']} × $qty',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? AppTheme.darkTextPrimary
                                    : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '\$${(price * qty).toStringAsFixed(2)}',
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
                  if (items.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '+ ${items.length - 3} more item(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  _PaymentBadge(method: paymentMethod, isDark: isDark),
                  const Spacer(),
                  Text(
                    'Total  ',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                      fontFamily: 'Georgia',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOrderDetail(
    BuildContext context,
    Map<String, dynamic> items,
    String status,
    double total,
    DateTime createdAt,
    String paymentMethod,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(
        orderId: orderId,
        items: items,
        status: status,
        total: total,
        createdAt: createdAt,
        paymentMethod: paymentMethod,
        isDark: isDark,
      ),
    );
  }

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
      case 'cancelled':
        return AppTheme.error;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'preparing':
        return Icons.coffee_maker_rounded;
      case 'ready':
        return Icons.check_circle_outline_rounded;
      case 'completed':
        return Icons.done_all_rounded;
      case 'cancelled':
        return Icons.cancel_outlined;
      default:
        return Icons.receipt_rounded;
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final m = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month]} ${dt.day}, ${dt.year}  $h:$m $ampm';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = AppTheme.warning;
        label = 'Pending';
        break;
      case 'preparing':
        color = AppTheme.info;
        label = 'Preparing';
        break;
      case 'ready':
        color = AppTheme.success;
        label = 'Ready';
        break;
      case 'completed':
        color = Colors.grey;
        label = 'Completed';
        break;
      case 'cancelled':
        color = AppTheme.error;
        label = 'Cancelled';
        break;
      default:
        color = Colors.grey;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusTracker extends StatelessWidget {
  final String status;
  final bool isDark;

  const _StatusTracker({required this.status, required this.isDark});

  static const _steps = ['pending', 'preparing', 'ready'];
  static const _labels = ['Ordered', 'Preparing', 'Ready'];
  static const _icons = [
    Icons.receipt_outlined,
    Icons.coffee_maker_rounded,
    Icons.store_rounded,
  ];

  int get _currentStep => _steps.indexOf(status);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIndex = i ~/ 2;
            final filled = stepIndex < _currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: filled
                    ? AppTheme.primary
                    : (isDark ? AppTheme.darkDivider : Colors.grey.shade200),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final done = stepIndex < _currentStep;
          final active = stepIndex == _currentStep;
          return Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done || active
                      ? AppTheme.primary
                      : (isDark
                          ? AppTheme.darkElevated
                          : Colors.grey.shade100),
                  border: Border.all(
                    color: done || active
                        ? AppTheme.primary
                        : (isDark
                            ? AppTheme.darkDivider
                            : Colors.grey.shade300),
                    width: 2,
                  ),
                ),
                child: Icon(
                  _icons[stepIndex],
                  size: 16,
                  color: done || active
                      ? Colors.white
                      : (isDark
                          ? AppTheme.darkTextSecondary
                          : Colors.grey.shade400),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _labels[stepIndex],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight:
                      active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? AppTheme.primary
                      : (isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.textSecondary),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final String method;
  final bool isDark;

  const _PaymentBadge({required this.method, required this.isDark});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String label;
    switch (method) {
      case 'mtn_momo':
        icon = Icons.mobile_friendly_rounded;
        label = 'MTN MoMo';
        break;
      case 'card':
        icon = Icons.credit_card_rounded;
        label = 'Card';
        break;
      default:
        icon = Icons.payments_outlined;
        label = 'Cash';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: 14,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.textSecondary),
        const SizedBox(width: 4),
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
    );
  }
}

class _OrderDetailSheet extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> items;
  final String status;
  final double total;
  final DateTime createdAt;
  final String paymentMethod;
  final bool isDark;

  const _OrderDetailSheet({
    required this.orderId,
    required this.items,
    required this.status,
    required this.total,
    required this.createdAt,
    required this.paymentMethod,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkBackground : AppTheme.background,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Order Details',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Georgia',
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  _StatusBadge(status: status),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '#${orderId.substring(0, 8).toUpperCase()}',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  if (status != 'completed' && status != 'cancelled')
                    _DetailSection(
                      title: 'Tracking',
                      isDark: isDark,
                      child: _StatusTracker(
                          status: status, isDark: isDark),
                    ),
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: 'Items Ordered',
                    isDark: isDark,
                    child: Column(
                      children: items.entries.map((e) {
                        final item = e.value as Map<String, dynamic>;
                        final qty = item['qty'] as int? ?? 1;
                        final price =
                            (item['price'] as num?)?.toDouble() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppTheme.secondary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.coffee_rounded,
                                    color: AppTheme.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['name'] ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppTheme.darkTextPrimary
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                '×$qty',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
                                      : AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '\$${(price * qty).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _DetailSection(
                    title: 'Payment',
                    isDark: isDark,
                    child: _PaymentRow(
                        method: paymentMethod,
                        total: total,
                        isDark: isDark),
                  ),
                  if (status == 'ready') ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              AppTheme.success.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.store_rounded,
                              color: AppTheme.success),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Your order is ready for pickup! Head to the café now.',
                              style: TextStyle(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final bool isDark;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.isDark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String method;
  final double total;
  final bool isDark;

  const _PaymentRow({
    required this.method,
    required this.total,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String label;
    switch (method) {
      case 'mtn_momo':
        icon = Icons.mobile_friendly_rounded;
        label = 'MTN MoMo';
        break;
      case 'card':
        icon = Icons.credit_card_rounded;
        label = 'Credit / Debit Card';
        break;
      default:
        icon = Icons.payments_outlined;
        label = 'Cash at Pickup';
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.textPrimary,
            ),
          ),
        ),
        Text(
          '\$${total.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.primary,
            fontFamily: 'Georgia',
          ),
        ),
      ],
    );
  }
}