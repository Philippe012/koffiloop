import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:koffiloop/core/theme/app_theme.dart';
import 'package:koffiloop/services/auth_service.dart';
import 'package:koffiloop/services/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthService>();
    final themeService = context.watch<ThemeService>();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor:
            isDark ? AppTheme.darkSurface : AppTheme.primary,
        foregroundColor: Colors.white,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontFamily: 'Georgia',
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          _ProfileCard(
            email: auth.isLoggedIn ? (user?.email ?? 'User') : 'Guest',
            role: auth.role,
            isDark: isDark,
            photoUrl: user?.photoURL,
          ),
          const SizedBox(height: 16),

          // Appearance
          _SettingsSection(
            title: 'Appearance',
            isDark: isDark,
            children: [
              _SettingsTile(
                icon: Icons.brightness_6_rounded,
                title: 'Theme',
                subtitle: _themeLabel(themeService.themeMode),
                isDark: isDark,
                trailing: _ThemePicker(
                  current: themeService.themeMode,
                  isDark: isDark,
                  onChanged: (mode) => themeService.setThemeMode(mode),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Notifications
          _SettingsSection(
            title: 'Notifications',
            isDark: isDark,
            children: [
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Order updates',
                subtitle: 'Get notified when your order status changes',
                isDark: isDark,
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
              _SettingsTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Messages',
                subtitle: 'Notify on new messages from shops',
                isDark: isDark,
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // About
          _SettingsSection(
            title: 'About',
            isDark: isDark,
            children: [
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'About KoffiLoop',
                subtitle: 'Version 1.0.0',
                isDark: isDark,
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'KoffiLoop',
                  applicationVersion: '1.0.0',
                  applicationLegalese:
                      'Multi-vendor coffee marketplace built with Flutter & Firebase.',
                ),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy Policy',
                isDark: isDark,
                onTap: () {},
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of Service',
                isDark: isDark,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Account
          _SettingsSection(
            title: 'Account',
            isDark: isDark,
            children: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                subtitle: 'You will be returned to the landing page',
                isDark: isDark,
                destructive: true,
                onTap: () => _confirmLogout(context, auth),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System default';
    }
  }

  Future<void> _confirmLogout(BuildContext context, AuthService auth) async {
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
}

class _ProfileCard extends StatelessWidget {
  final String email;
  final String role;
  final bool isDark;
  final String? photoUrl;

  const _ProfileCard({
    required this.email,
    required this.role,
    required this.isDark,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppTheme.buttonShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            child: photoUrl != null && photoUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(photoUrl!, fit: BoxFit.cover))
                : const Icon(Icons.person_rounded,
                    color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.isDark,
    required this.children,
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
            children: children.map((c) {
              final isLast = c == children.last;
              return Column(
                children: [
                  c,
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDark;
  final bool destructive;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.isDark,
    this.destructive = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppTheme.error
        : (isDark ? AppTheme.darkTextPrimary : AppTheme.textPrimary);

    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: (destructive ? AppTheme.error : AppTheme.primary)
              .withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 18,
            color: destructive ? AppTheme.error : AppTheme.primary),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.textSecondary,
              ),
            )
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right_rounded,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : Colors.grey.shade400)
              : null),
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  final ThemeMode current;
  final bool isDark;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemePicker({
    required this.current,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ThemeMode>(
      initialValue: current,
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: isDark ? AppTheme.darkCard : Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkElevated : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_modeIcon(current), size: 14, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(
              _modeLabel(current),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                size: 14, color: AppTheme.primary),
          ],
        ),
      ),
      itemBuilder: (_) => [
        _menuItem(ThemeMode.light, Icons.wb_sunny_rounded, 'Light', isDark),
        _menuItem(ThemeMode.dark, Icons.nightlight_round, 'Dark', isDark),
        _menuItem(ThemeMode.system, Icons.phone_android_rounded,
            'System', isDark),
      ],
    );
  }

  PopupMenuItem<ThemeMode> _menuItem(
      ThemeMode mode, IconData icon, String label, bool isDark) {
    final selected = current == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: selected ? AppTheme.primary : (isDark ? AppTheme.darkTextSecondary : AppTheme.textSecondary)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? AppTheme.primary
                  : (isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.textPrimary),
            ),
          ),
          if (selected) ...[
            const Spacer(),
            const Icon(Icons.check_rounded,
                size: 16, color: AppTheme.primary),
          ],
        ],
      ),
    );
  }

  IconData _modeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.wb_sunny_rounded;
      case ThemeMode.dark:
        return Icons.nightlight_round;
      case ThemeMode.system:
        return Icons.phone_android_rounded;
    }
  }

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }
}