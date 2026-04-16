import 'package:cloud_firestore/cloud_firestore.dart';

class OrderModel {
  final String id;
  final String customerId;
  final String sellerId;
  final Map<String, dynamic> items;
  final double total;
  final String paymentMethod;
  final String status;
  final DateTime createdAt;

  OrderModel({
    required this.id, required this.customerId, required this.sellerId,
    required this.items, required this.total, required this.paymentMethod,
    required this.status, required this.createdAt,
  });

  factory OrderModel.fromFirestore(Map<String, dynamic> data, String id) {
    return OrderModel(
      id: id,
      customerId: data['customerId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      items: data['items'] ?? {},
      total: (data['total'] ?? 0).toDouble(),
      paymentMethod: data['paymentMethod'] ?? 'cash',
      status: data['status'] ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }
}