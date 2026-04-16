import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';
// import 'package:firebase_auth/firebase_auth.dart';

import 'services/auth_service.dart';
import 'services/cart_service.dart';
import 'services/theme_service.dart'; 
import 'core/theme/app_theme.dart';

import 'package:koffiloop/features/landing/screens/landing_screen.dart';
import 'package:koffiloop/features/customer_dashboard/screens/customer_dashboard.dart';
import 'package:koffiloop/features/seller_portal/screens/seller_dashboard.dart';
import 'package:koffiloop/features/order_tracking/screens/order_status_screen.dart';
import 'package:koffiloop/features/settings/screens/settings_screen.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const KofiLoopApp());
}

class KofiLoopApp extends StatelessWidget {
  const KofiLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => CartService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) => MaterialApp(
          title: 'KofiLoop',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeService.themeMode,
          home: const RoleBasedHome(),
          routes: {
            '/landing': (_) => const LandingScreen(),
            '/home': (_) => const CustomerDashboard(),
            '/seller': (_) => const SellerDashboard(),
            '/order': (_) => const OrderStatusScreen(),
            '/settings': (_) => const SettingsScreen(),
          },
        ),
      ),
    );
  }
}

class RoleBasedHome extends StatelessWidget {
  const RoleBasedHome({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    
    if (!auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/landing');
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final role = context.read<AuthService>().role;
      if (role == 'seller') {
        Navigator.pushReplacementNamed(context, '/seller');
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    });
    
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your dashboard...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}