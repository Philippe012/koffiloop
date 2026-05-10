import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/cart_service.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/services/notification_service.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _paymentMethod = 'cash';
  bool _placing = false;

  static const _paymentOptions = [
    _PaymentOption(
      id: 'cash',
      label: 'Cash at Pickup',
      subtitle: 'Pay when you collect your order',
      icon: Icons.payments_outlined,
      color: AppTheme.success,
    ),
    _PaymentOption(
      id: 'mtn_momo',
      label: 'MTN MoMo',
      subtitle: 'Pay with MTN Mobile Money',
      icon: Icons.mobile_friendly_rounded,
      color: Color(0xFFFFCC00),
    ),
    _PaymentOption(
      id: 'card',
      label: 'Credit / Debit Card',
      subtitle: 'Visa, Mastercard accepted',
      icon: Icons.credit_card_rounded,
      color: AppTheme.info,
    ),
  ];

  Future<void> _placeOrder(BuildContext context) async {
    final cart = context.read<CartService>();
    final auth = context.read<AuthService>();

    if (cart.cart.isEmpty) return;

    setState(() => _placing = true);
    try {
      final orderRef = await FirebaseFirestore.instance
          .collection('orders')
          .add({
        'customerId': auth.uid,
        'sellerId': cart.selectedShopId,
        'items': cart.cart,
        'total': cart.total,
        'paymentMethod': _paymentMethod,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Notify seller of new order
      await NotificationService().notifyNewOrder(
        orderId: orderRef.id,
        sellerId: cart.selectedShopId,
      );

      cart.clear();

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle_outline_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Text('Order placed! The shop will confirm shortly.'),
            ]),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to place order: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cart = context.watch<CartService>();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Checkout',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Georgia',
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (cart.cart.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, cart),
              child: const Text(
                'Clear',
                style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: cart.cart.isEmpty
          ? _buildEmptyCart(isDark)
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Shop header
                        _ShopHeader(
                            shopId: cart.selectedShopId,
                            isDark: isDark),
                        const SizedBox(height: 16),

                        // Cart items section
                        _SectionLabel(
                            label: 'Your Items', isDark: isDark),
                        const SizedBox(height: 10),
                        ...cart.cart.entries.map((entry) =>
                            _CartItemRow(
                              itemId: entry.key,
                              item: entry.value,
                              isDark: isDark,
                              onRemove: () =>
                                  cart.remove(entry.key),
                              onAdd: () => cart.add(
                                entry.key,
                                entry.value['name'],
                                (entry.value['price'] as num)
                                    .toDouble(),
                              ),
                            )),
                        const SizedBox(height: 20),

                        // Order summary
                        _SectionLabel(
                            label: 'Order Summary', isDark: isDark),
                        const SizedBox(height: 10),
                        _SummaryCard(cart: cart, isDark: isDark),
                        const SizedBox(height: 20),

                        // Payment method
                        _SectionLabel(
                            label: 'Payment Method', isDark: isDark),
                        const SizedBox(height: 10),
                        Column(
                          children: _paymentOptions.map((opt) =>
                              _PaymentOptionTile(
                                option: opt,
                                selected:
                                    _paymentMethod == opt.id,
                                isDark: isDark,
                                onTap: () => setState(
                                    () => _paymentMethod = opt.id),
                              )).toList(),
                        ),
                        const SizedBox(height: 8),
                        if (_paymentMethod == 'mtn_momo')
                          _MomoNotice(isDark: isDark),
                        if (_paymentMethod == 'card')
                          _CardNotice(isDark: isDark),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
                ),

                // Bottom bar
                _BottomBar(
                  total: cart.total,
                  placing: _placing,
                  isDark: isDark,
                  onConfirm: () => _placeOrder(context),
                ),
              ],
            ),
    );
  }

  Widget _buildEmptyCart(bool isDark) {
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
            child: const Icon(Icons.shopping_bag_outlined,
                size: 48, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          Text(
            'Your cart is empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFamily: 'Georgia',
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add items from a café to get started',
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

  Future<void> _confirmClear(
      BuildContext context, CartService cart) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Cart'),
        content: const Text('Remove all items from your cart?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      cart.clear();
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _ShopHeader extends StatelessWidget {
  final String shopId;
  final bool isDark;

  const _ShopHeader({required this.shopId, required this.isDark});

  @override
  Widget build(BuildContext context) {
    if (shopId.isEmpty) return const SizedBox();
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final data = snap.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox();
        final imageUrl = data['shopImageUrl'] as String? ?? '';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.cardShadow(isDark),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: imageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(imageUrl, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.storefront_rounded,
                                color: AppTheme.primary)),
                      )
                    : const Icon(Icons.storefront_rounded,
                        color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name'] ?? 'Café',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      data['city'] ?? '',
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Open',
                  style: TextStyle(
                    color: AppTheme.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final String itemId;
  final Map<String, dynamic> item;
  final bool isDark;
  final VoidCallback onRemove;
  final VoidCallback onAdd;

  const _CartItemRow({
    required this.itemId,
    required this.item,
    required this.isDark,
    required this.onRemove,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final qty = item['qty'] as int? ?? 1;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final name = item['name'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.coffee_rounded,
                color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '\$${price.toStringAsFixed(2)} each',
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
          // Qty controls
          Row(
            children: [
              _QtyButton(
                icon: Icons.remove_rounded,
                onTap: onRemove,
                isDark: isDark,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$qty',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
              _QtyButton(
                icon: Icons.add_rounded,
                onTap: onAdd,
                isDark: isDark,
                primary: true,
              ),
            ],
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
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final bool primary;

  const _QtyButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: primary
              ? AppTheme.primary
              : (isDark ? AppTheme.darkElevated : AppTheme.surfaceVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: primary
              ? Colors.white
              : (isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final CartService cart;
  final bool isDark;

  const _SummaryCard({required this.cart, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final subtotal = cart.total;
    const serviceFee = 0.0;
    final total = subtotal + serviceFee;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow(isDark),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'Subtotal',
            value: '\$${subtotal.toStringAsFixed(2)}',
            isDark: isDark,
          ),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Service fee',
            value: 'Free',
            isDark: isDark,
            valueColor: AppTheme.success,
          ),
          Divider(
            height: 20,
            color: isDark ? AppTheme.darkDivider : Colors.grey.shade100,
          ),
          _SummaryRow(
            label: 'Total',
            value: '\$${total.toStringAsFixed(2)}',
            isDark: isDark,
            bold: true,
            valueColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool bold;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: bold ? 16 : 14,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: bold ? 18 : 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            fontFamily: bold ? 'Georgia' : null,
            color: valueColor ??
                (isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _PaymentOptionTile extends StatelessWidget {
  final _PaymentOption option;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _PaymentOptionTile({
    required this.option,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.07)
              : (isDark ? AppTheme.darkCard : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : (isDark ? AppTheme.darkDivider : AppTheme.divider),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected ? [] : AppTheme.cardShadow(isDark),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: option.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(option.icon, color: option.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    option.subtitle,
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppTheme.primary : Colors.grey.shade400,
                  width: 2,
                ),
                color: selected ? AppTheme.primary : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      size: 12, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _MomoNotice extends StatelessWidget {
  final bool isDark;
  const _MomoNotice({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFCC00).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFFFCC00).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFD4A400), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You will receive a push code on your MTN number to confirm payment.',
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
    );
  }
}

class _CardNotice extends StatelessWidget {
  final bool isDark;
  const _CardNotice({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppTheme.info, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Card payments are processed securely. You will be redirected to the payment gateway.',
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
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double total;
  final bool placing;
  final bool isDark;
  final VoidCallback onConfirm;

  const _BottomBar({
    required this.total,
    required this.placing,
    required this.isDark,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppTheme.darkDivider : Colors.grey.shade100,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary,
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                  fontFamily: 'Georgia',
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: GestureDetector(
              onTap: placing ? null : onConfirm,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: placing
                        ? [Colors.grey.shade400, Colors.grey.shade400]
                        : [AppTheme.primary, AppTheme.primaryDark],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: placing ? [] : AppTheme.buttonShadow,
                ),
                child: Center(
                  child: placing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Place Order',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;

  const _SectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFamily: 'Georgia',
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
      ),
    );
  }
}

class _PaymentOption {
  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _PaymentOption({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}