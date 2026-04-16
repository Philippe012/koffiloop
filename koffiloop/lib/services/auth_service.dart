import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  String _role = 'customer';

  String get role => _role;
  bool get isLoggedIn => _auth.currentUser != null;
  String get uid => _auth.currentUser?.uid ?? '';

  Future<void> login(String email, String password, BuildContext context) async {
    try {
      final user = await _auth.signInWithEmailAndPassword(email: email, password: password);
      final doc = await _db.collection('users').doc(user.user!.uid).get();
      _role = doc.data()?['role'] ?? 'customer';
      notifyListeners();
      if (context.mounted) _redirect(context);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Login failed');
    }
  }

  Future<void> signup(String email, String password, String role, BuildContext context) async {
    try {
      final user = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await _db.collection('users').doc(user.user!.uid).set({
        'email': email, 'role': role, 'createdAt': FieldValue.serverTimestamp()
      });
      _role = role;
      notifyListeners();
      if (context.mounted) _redirect(context);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Signup failed');
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    _role = 'customer';
    notifyListeners();
  }

  void _redirect(BuildContext context) {
    if (!context.mounted) return;
    Navigator.pushReplacementNamed(context, _role == 'seller' ? '/seller' : '/home');
  }
}