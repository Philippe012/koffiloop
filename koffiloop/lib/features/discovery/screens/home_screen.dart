import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
// import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/services/cart_service.dart';
import 'package:koffiloop/features/cart_checkout/screens/checkout_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nearby Cafés'), actions: [
        IconButton(icon: const Icon(Icons.shopping_cart), onPressed: () {
          if (context.read<CartService>().cart.isEmpty) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
        }),
        IconButton(icon: const Icon(Icons.list_alt), onPressed: () => Navigator.pushNamed(context, '/order')),
      ]),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('shops').where('isOpen', isEqualTo: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final shop = snapshot.data!.docs[index];
              return Card(margin: const EdgeInsets.all(8), child: ListTile(
                title: Text(shop['name']),
                subtitle: Text(shop['city'] ?? 'Unknown Location'),
                trailing: ElevatedButton(child: const Text('Menu'), onPressed: () => _showMenu(context, shop.id, shop['name'])),
              ));
            },
          );
        },
      ),
    );
  }

  void _showMenu(BuildContext context, String shopId, String shopName) {
    context.read<CartService>().setShop(shopId);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('$shopName Menu'),
      content: SizedBox(width: double.maxFinite, child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('shops').doc(shopId).collection('products').where('inStock', isEqualTo: true).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          return ListView(shrinkWrap: true, children: snap.data!.docs.map((doc) {
            final p = doc.data() as Map<String, dynamic>;
            return ListTile(title: Text(p['name']), subtitle: Text('\$${p['price']}'), trailing: IconButton(icon: const Icon(Icons.add_circle), onPressed: () {
              context.read<CartService>().add(doc.id, p['name'], (p['price'] as num).toDouble());
            }));
          }).toList());
        },
      )),
      actions: [TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('Done'))],
    ));
  }
}