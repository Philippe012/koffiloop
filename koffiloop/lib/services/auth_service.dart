import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _googleSignIn = GoogleSignIn(); 
  String _role = 'customer';

  String get role => _role;
  bool get isLoggedIn => _auth.currentUser != null;
  String get uid => _auth.currentUser?.uid ?? '';

  Future<void> login(String email, String password, BuildContext context) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      await _syncUserRole(userCredential.user!.uid);
      if (context.mounted) _redirect(context);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Login failed');
    }
  }

  Future<void> signup(
      String email, String password, String role, BuildContext context) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      final uid = userCredential.user!.uid;
      
      // Create user document
      await _db.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'role': role,
        'displayName': '',
        'photoURL': '',
        'createdAt': FieldValue.serverTimestamp(),
        'lastLogin': FieldValue.serverTimestamp(),
      });
      
      _role = role;
      notifyListeners();
      if (context.mounted) _redirect(context);
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Signup failed');
    }
  }

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return; 

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final uid = userCredential.user!.uid;

      final userDoc = await _db.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        await _db.collection('users').doc(uid).set({
          'uid': uid,
          'email': googleUser.email,
          'displayName': googleUser.displayName ?? '',
          'photoURL': googleUser.photoUrl ?? '',
          'role': 'customer', 
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
        _role = 'customer';
      } else {
        _role = userDoc.data()?['role'] ?? 'customer';
        await userDoc.reference.update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
      
      notifyListeners();
      if (context.mounted) _redirect(context);
    } catch (e) {
      throw Exception('Google sign-in failed: ${e.toString()}');
    }
  }

  Future<void> handlePostLogin(BuildContext context) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _syncUserRole(user.uid);
    if (context.mounted) _redirect(context);
  }

  Future<void> _syncUserRole(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    _role = doc.data()?['role'] ?? 'customer';
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _googleSignIn.signOut(); 
    _role = 'customer';
    notifyListeners();
  }

  void _redirect(BuildContext context) {
    if (!context.mounted) return;
    final route = _role == 'seller' ? '/seller' : '/home';
    Navigator.pushReplacementNamed(context, route);
  }
}