import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/features/seller_portal/screens/product_manager_screen.dart';
import 'package:koffiloop/models/order_model.dart';

class SellerDashboard extends StatelessWidget {
  const SellerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('🏪 Seller Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await context.read<AuthService>().logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, '/landing', (route) => false);
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome + Quick Stats
            _buildStatsCard(auth.uid),
            const SizedBox(height: 24),
            
            // Quick Actions
            const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionCard(
                    icon: Icons.add_circle_outline,
                    title: 'Add Product',
                    subtitle: 'List a new item',
                    color: AppTheme.primary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProductManagerScreen(shopId: _getShopId(auth.uid))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'Manage Stock',
                    subtitle: 'Update availability',
                    color: AppTheme.secondary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProductManagerScreen(shopId: _getShopId(auth.uid), manageStock: true)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Active Orders
            const Text('Active Orders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _buildOrdersList(auth.uid),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(String sellerId) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: 'Today\'s Orders',
                  value: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('orders')
                        .where('sellerId', isEqualTo: sellerId)
                        .where('createdAt', isGreaterThanOrEqualTo: DateTime.now().subtract(const Duration(hours: 24)))
                        .snapshots(),
                    builder: (context, snap) => Text(snap.hasData ? '${snap.data!.docs.length}' : '0', 
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                ),
                _StatItem(
                  label: 'Revenue',
                  value: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('orders')
                        .where('sellerId', isEqualTo: sellerId)
                        .where('status', isEqualTo: 'completed')
                        .snapshots(),
                    builder: (context, snap) {
                      if (!snap.hasData) return const Text('\$0.00', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold));
                      final total = snap.data!.docs.fold(0.0, (acc, doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        return acc + ((data['total'] ?? 0) as num).toDouble();
                      });
                      return Text('\$${total.toStringAsFixed(2)}', 
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.success));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersList(String sellerId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('sellerId', isEqualTo: sellerId)
          .where('status', whereIn: ['pending', 'preparing', 'ready'])
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('No active orders', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text('New orders will appear here', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
                ],
              ),
            ),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final order = OrderModel.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
            return _OrderTile(order: order, onUpdate: (status) async {
              await FirebaseFirestore.instance.collection('orders').doc(order.id).update({'status': status});
            });
          },
        );
      },
    );
  }

  String _getShopId(String sellerId) => sellerId; // Simplified: 1 shop per seller
}

// Stats Item Widget
class _StatItem extends StatelessWidget {
  final String label;
  final Widget value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        value,
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      ],
    );
  }
}

// Quick Action Card
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

// Order Tile with Status Actions
class _OrderTile extends StatelessWidget {
  final OrderModel order;
  final Function(String) onUpdate;
  const _OrderTile({required this.order, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Order #${order.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                Chip(
                  label: Text(order.status.toUpperCase(), style: const TextStyle(fontSize: 11, color: Colors.white)),
                  backgroundColor: _statusColor(order.status),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            ...(order.items.entries.map((e) {
              final item = e.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${item['name']} × ${item['qty']} · \$${(item['price'] * item['qty']).toStringAsFixed(2)}'),
              );
            })),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total: \$${order.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(order.createdAt.toString().substring(0, 16), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 12),
            // Status Actions
            if (order.status == 'pending')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Accept Order'),
                  onPressed: () => onUpdate('preparing'),
                ),
              )
            else if (order.status == 'preparing')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.coffee),
                  label: const Text('Mark as Ready'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
                  onPressed: () => onUpdate('ready'),
                ),
              )
            else if (order.status == 'ready')
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: const Text('Complete Order'),
                  onPressed: () => onUpdate('completed'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return AppTheme.warning;
      case 'preparing': return Colors.blue;
      case 'ready': return AppTheme.success;
      case 'completed': return Colors.grey;
      default: return Colors.grey;
    }
  }
}