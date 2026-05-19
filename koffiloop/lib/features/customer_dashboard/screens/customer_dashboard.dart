import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/features/discovery/screens/home_screen.dart';
import 'package:koffiloop/features/order_tracking/screens/order_status_screen.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/services/theme_service.dart';

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key});

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  int _currentIndex = 0;

  static const _navItems = [
    _NavItem(
      icon: Icons.storefront_outlined,
      activeIcon: Icons.storefront_rounded,
      label: 'Explore',
    ),
    _NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long_rounded,
      label: 'Orders',
    ),
    _NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  final _screens = const [
    HomeScreen(),
    OrderStatusScreen(),
    _ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        isDark: isDark,
        items: _navItems,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Nav
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.isDark,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = currentIndex == i;
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppTheme.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          color: selected
                              ? AppTheme.primary
                              : (isDark
                                  ? AppTheme.darkTextSecondary
                                  : Colors.grey.shade400),
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        textAlign: TextAlign.center,  
                        style: TextStyle(
                          fontSize: 12,  
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w600, 
                          color: selected
                              ? AppTheme.primary
                              : (isDark
                                  ? AppTheme.darkTextSecondary.withValues(alpha: 0.9) 
                                  : Colors.grey.shade700), 
                          letterSpacing: 0.2,
                          height: 1.2, 
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Tab — Stateful so it can reload after edits
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  // ── Notifications preference ──────────────────────────────────────────────
  // Persisted in Firestore users/{uid}.notificationsEnabled
  bool _notificationsEnabled = true;
  bool _notifLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (doc.exists) {
      final enabled = doc.data()?['notificationsEnabled'];
      if (mounted && enabled != null) {
        setState(() => _notificationsEnabled = enabled as bool);
      }
    }
  }

  Future<void> _setNotifications(bool value) async {
    setState(() {
      _notificationsEnabled = value;
      _notifLoading = true;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'notificationsEnabled': value},
        SetOptions(merge: true),
      );
    }
    if (mounted) setState(() => _notifLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthService>();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              _ProfileHeader(
                user: user,
                isDark: isDark,
                onEditPhoto: () => _pickAndUploadPhoto(context, user),
              ),
              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Quick Stats ──────────────────────────────────────
                    _QuickStats(uid: auth.uid, isDark: isDark),
                    const SizedBox(height: 24),

                    // ── Account ──────────────────────────────────────────
                    _MenuSection(
                      title: 'Account',
                      isDark: isDark,
                      tiles: [
                        _MenuTile(
                          icon: Icons.person_outline_rounded,
                          label: 'Edit Profile',
                          isDark: isDark,
                          onTap: () =>
                              _showEditProfile(context, user, isDark),
                        ),
                        _MenuTile(
                          icon: Icons.lock_outline_rounded,
                          label: 'Change Password',
                          isDark: isDark,
                          onTap: () => _changePassword(context, user),
                        ),
                        _MenuTile(
                          icon: Icons.notifications_outlined,
                          label: 'Notifications',
                          isDark: isDark,
                          onTap: null, // toggled only via the switch
                          trailing: _notifLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : _Toggle(
                                  value: _notificationsEnabled,
                                  onChanged: _setNotifications,
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Appearance ───────────────────────────────────────
                    _MenuSection(
                      title: 'Appearance',
                      isDark: isDark,
                      tiles: [
                        _ThemeModeTile(isDark: isDark),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Support ──────────────────────────────────────────
                    _MenuSection(
                      title: 'Support',
                      isDark: isDark,
                      tiles: [
                        _MenuTile(
                          icon: Icons.help_outline_rounded,
                          label: 'Help & FAQ',
                          isDark: isDark,
                          onTap: () => _showHelpFaq(context, isDark),
                        ),
                        _MenuTile(
                          icon: Icons.mail_outline_rounded,
                          label: 'Contact Support',
                          isDark: isDark,
                          onTap: () => _contactSupport(context),
                        ),
                        _MenuTile(
                          icon: Icons.info_outline_rounded,
                          label: 'About KoffiLoop',
                          isDark: isDark,
                          onTap: () => showAboutDialog(
                            context: context,
                            applicationName: 'KoffiLoop',
                            applicationVersion: '1.0.0',
                            applicationLegalese:
                                'Multi-vendor coffee marketplace.\nBuilt with Flutter & Firebase.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Account Actions ───────────────────────────────────
                    _MenuSection(
                      title: 'Account Actions',
                      isDark: isDark,
                      tiles: [
                        _MenuTile(
                          icon: Icons.logout_rounded,
                          label: 'Sign Out',
                          isDark: isDark,
                          destructive: true,
                          onTap: () => _logout(context, auth),
                        ),
                        _MenuTile(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete Account',
                          isDark: isDark,
                          destructive: true,
                          onTap: () => _deleteAccount(auth, user),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Edit Profile ────────────────────────────────────────────────────────────

  void _showEditProfile(BuildContext context, User? user, bool isDark) {
    final nameCtrl = TextEditingController(text: user?.displayName ?? '');
    late BuildContext sheetContext;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        sheetContext = ctx;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkDivider
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Georgia',
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display Name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;

                  await user?.updateDisplayName(name);
                  // Also mirror to Firestore
                  final uid = user?.uid;
                  if (uid != null) {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .set({'displayName': name}, SetOptions(merge: true));
                  }
                  if (context.mounted) {
                    Navigator.pop(sheetContext);
                      setState(() {});
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(
                          content: Text('Profile updated ✓'),
                          backgroundColor: AppTheme.success,
                        ),
                      );
                  }
                },
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.buttonShadow,
                  ),
                  child: const Center(
                    child: Text(
                      'Save Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
       );
      },
    );
  }

  // ── Photo picker + upload ────────────────────────────────────────────────

  Future<void> _pickAndUploadPhoto(
      BuildContext context, User? user) async {
    if (user == null) return;
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkDivider
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Change Profile Photo',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded,
                    color: AppTheme.primary),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded,
                    color: AppTheme.primary),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    // Show uploading indicator
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Uploading photo…'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final url = await _uploadImageToCloudinary(File(picked.path));
      await user.updatePhotoURL(url);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'photoURL': url}, SetOptions(merge: true));


      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Photo updated ✓'),
              backgroundColor: AppTheme.success),
        );
        setState(() {}); // rebuild header
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Upload failed: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  Future<String> _uploadImageToCloudinary(File file) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/dyyzgowpd/upload',
    );

    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = 'koffiloop_upload';
    request.fields['folder'] = 'koffiloop';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String;
    }

    throw Exception(
      'Cloudinary upload failed (${response.statusCode}): ${response.body}',
    );
  }

  // ── Change Password ─────────────────────────────────────────────────────

  Future<void> _changePassword(BuildContext context, User? user) async {
    if (user?.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No email address on this account'),
            backgroundColor: AppTheme.error),
      );
      return;
    }
    // Confirm before sending
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text(
            'Send a password reset email to ${user!.email}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send Email')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: user!.email!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reset email sent to ${user.email} ✓'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppTheme.error),
        );
      }
    }
  }

  // ── Help & FAQ ──────────────────────────────────────────────────────────

  void _showHelpFaq(BuildContext context, bool isDark) {
    final faqs = [
      (
        q: 'How do I place an order?',
        a: 'Browse shops on the Explore tab, tap a product, customize it and press Add to Cart. Review your cart then tap Checkout.'
      ),
      (
        q: 'Can I cancel my order?',
        a: 'Orders can be cancelled within 2 minutes of placing them while still in "Pending" status. Go to Orders → tap the order → Cancel.'
      ),
      (
        q: 'How do I track my order?',
        a: 'Open the Orders tab to see real-time status updates: Pending → Preparing → Ready → Completed.'
      ),
      (
        q: 'What payment methods are accepted?',
        a: 'We currently support mobile money (MTN, Airtel) and cash on collection.'
      ),
      (
        q: 'How do I contact a shop?',
        a: 'Open a shop page and tap the Chat icon to start a conversation directly with the barista.'
      ),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, ctrl) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkDivider
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Help & FAQ',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Georgia',
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  controller: ctrl,
                  itemCount: faqs.length,
                  separatorBuilder: (_, __) => Divider(
                      color: isDark
                          ? AppTheme.darkDivider
                          : Colors.grey.shade100),
                  itemBuilder: (_, i) {
                    final faq = faqs[i];
                    return ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        faq.q,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.textPrimary,
                        ),
                      ),
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 12),
                          child: Text(
                            faq.a,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Contact Support ─────────────────────────────────────────────────────

  Future<void> _contactSupport(BuildContext context) async {
    const email = 'support@koffiloop.app';
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=KoffiLoop Support Request',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email us at $email'),
            backgroundColor: AppTheme.primary,
          ),
        );
      }
    }
  }

  // ── Sign Out ────────────────────────────────────────────────────────────

  Future<void> _logout(BuildContext context, AuthService auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await auth.logout();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/landing', (r) => false);
      }
    }
  }

  // ── Delete Account ──────────────────────────────────────────────────────

  Future<void> _deleteAccount(AuthService auth, User? user) async {
  if (user == null) return;
  if (!mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Account'),
      content: const Text(
        'This will permanently delete your account and all order history. '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final pwdCtrl = TextEditingController();
  if (!mounted) return;

  final reauthed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm Password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'Enter your password to confirm account deletion.'),
          const SizedBox(height: 12),
          TextField(
            controller: pwdCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (reauthed != true) return;

  try {
    if (user.email != null) {
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: pwdCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .delete();
    await user.delete();
    await auth.logout();

    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/landing', (r) => false);
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed: ${_friendlyError(e)}'),
        backgroundColor: AppTheme.error,
      ),
    );
  }
}
  
  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('wrong-password') ||
        msg.contains('invalid-credential')) {
      return 'Incorrect password';
    }
    if (msg.contains('requires-recent-login')) {
      return 'Please sign out and sign in again first';
    }
    return msg;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Header — shows photo with edit camera badge
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final User? user;
  final bool isDark;
  final VoidCallback onEditPhoto;

  const _ProfileHeader({
    required this.user,
    required this.isDark,
    required this.onEditPhoto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          // Avatar + camera badge
          GestureDetector(
            onTap: onEditPhoto,
            child: Stack(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4), width: 3),
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  child: user?.photoURL != null
                      ? ClipOval(
                          child: Image.network(
                            user!.photoURL!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 44),
                          ),
                        )
                      : const Icon(Icons.person_rounded,
                          color: Colors.white, size: 44),
                ),
                // Camera badge
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: AppTheme.primary, size: 15),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            user?.displayName?.isNotEmpty == true
                ? user!.displayName!
                : 'Coffee Lover',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user?.email ?? '',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'CUSTOMER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Stats — uses a simple query without composite index (no orderBy)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStats extends StatelessWidget {
  final String uid;
  final bool isDark;

  const _QuickStats({required this.uid, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // Single query on customerId only — avoids composite-index errors.
    // All filtering/sorting is done client-side.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .where('customerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const SizedBox.shrink();
        }
        final docs = snap.data?.docs ?? [];
        final total = docs.fold(0.0, (acc, d) {
          final data = d.data() as Map<String, dynamic>;
          return acc + ((data['total'] as num?)?.toDouble() ?? 0);
        });
        final active = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return ['pending', 'preparing', 'ready']
              .contains(data['status']);
        }).length;

        return Row(
          children: [
            _StatTile(
              label: 'Total Orders',
              value: '${docs.length}',
              icon: Icons.receipt_rounded,
              isDark: isDark,
            ),
            const SizedBox(width: 12),
            _StatTile(
              label: 'Active',
              value: '$active',
              icon: Icons.coffee_rounded,
              isDark: isDark,
              color: AppTheme.warning,
            ),
            const SizedBox(width: 12),
            _StatTile(
              label: 'Spent',
              value: '\$${total.toStringAsFixed(0)}',
              icon: Icons.payments_outlined,
              isDark: isDark,
              color: AppTheme.success,
            ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDark;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppTheme.cardShadow(isDark),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Georgia',
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Menu building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _MenuSection extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<Widget> tiles;

  const _MenuSection({
    required this.title,
    required this.isDark,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppTheme.cardShadow(isDark),
          ),
          child: Column(
            children: tiles.asMap().entries.map((e) {
              final isLast = e.key == tiles.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: 56,
                      color: isDark
                          ? AppTheme.darkDivider
                          : Colors.grey.shade100,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final bool destructive;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.isDark,
    this.destructive = false,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppTheme.error : AppTheme.primary;
    final textColor = destructive
        ? AppTheme.error
        : (isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary);

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : Colors.grey.shade300),
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme Mode tile (Appearance)
// ─────────────────────────────────────────────────────────────────────────────

class _ThemeModeTile extends StatelessWidget {
  final bool isDark;

  const _ThemeModeTile({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final current = themeService.themeMode;

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            Icon(_modeIcon(current), size: 18, color: AppTheme.primary),
      ),
      title: Text(
        'Theme',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color:
              isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary,
        ),
      ),
      trailing: PopupMenuButton<ThemeMode>(
        initialValue: current,
        onSelected: (mode) => themeService.setThemeMode(mode),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        color: isDark ? AppTheme.darkCard : Colors.white,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.darkElevated
                : AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_modeIcon(current),
                  size: 13, color: AppTheme.primary),
              const SizedBox(width: 5),
              Text(
                _modeLabel(current),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
              const Icon(Icons.expand_more_rounded,
                  size: 13, color: AppTheme.primary),
            ],
          ),
        ),
        itemBuilder: (_) => [
          _popupItem(ThemeMode.light, Icons.wb_sunny_rounded, 'Light',
              current, isDark),
          _popupItem(ThemeMode.dark, Icons.nightlight_round, 'Dark',
              current, isDark),
          _popupItem(ThemeMode.system, Icons.phone_android_rounded,
              'System', current, isDark),
        ],
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }

  PopupMenuItem<ThemeMode> _popupItem(ThemeMode mode, IconData icon,
      String label, ThemeMode current, bool isDark) {
    final sel = current == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: sel
                  ? AppTheme.primary
                  : (isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.textSecondary)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontWeight:
                      sel ? FontWeight.w700 : FontWeight.w500,
                  color: sel
                      ? AppTheme.primary
                      : (isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.textPrimary))),
          if (sel) ...[
            const Spacer(),
            const Icon(Icons.check_rounded,
                size: 14, color: AppTheme.primary),
          ],
        ],
      ),
    );
  }

  IconData _modeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Icons.wb_sunny_rounded,
        ThemeMode.dark => Icons.nightlight_round,
        ThemeMode.system => Icons.phone_android_rounded,
      };

  String _modeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Toggle widget
// ─────────────────────────────────────────────────────────────────────────────

class _Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.8,
      child: Switch(value: value, onChanged: onChanged),
    );
  }
}