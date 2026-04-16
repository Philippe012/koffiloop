import 'package:flutter/material.dart';

class CartService extends ChangeNotifier {
  String _selectedShopId = '';
  final Map<String, Map<String, dynamic>> _cart = {};

  String get selectedShopId => _selectedShopId;
  Map<String, Map<String, dynamic>> get cart => Map.unmodifiable(_cart);
  double get total => _cart.values.fold(0, (sum, item) => sum + ((item['price'] as num) * (item['qty'] as int)).toDouble());
  int get itemCount => _cart.values.fold(0, (sum, item) => sum + (item['qty'] as int));

  void setShop(String shopId) { 
    if (_selectedShopId != shopId) clear(); 
    _selectedShopId = shopId; 
    notifyListeners(); 
  }
  
  void add(String id, String name, double price) {
    if (_cart.containsKey(id)) {
      _cart[id]!['qty'] = (_cart[id]!['qty'] as int) + 1;
    } else {
      _cart[id] = {'name': name, 'price': price, 'qty': 1};
    }
    notifyListeners();
  }

  void remove(String id) { 
    _cart.remove(id); 
    notifyListeners(); 
  }
  
  void updateQty(String id, int qty) {
    if (qty <= 0) {
      remove(id);
    } else {
      _cart[id]!['qty'] = qty;
      notifyListeners();
    }
  }

  void decrementQty(String id) {
    if (_cart.containsKey(id)) {
      int currentQty = _cart[id]!['qty'] as int;
      if (currentQty > 1) {
        _cart[id]!['qty'] = currentQty - 1;
      } else {
        remove(id);
      }
      notifyListeners();
    }
  }
  
  void clear() { 
    _cart.clear(); 
    _selectedShopId = ''; 
    notifyListeners(); 
  }  
}