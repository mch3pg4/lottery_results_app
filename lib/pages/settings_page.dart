import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'edit_profile_page.dart';
import 'dark_mode_page.dart';
import 'about_app_page.dart';
import 'feedback_page.dart';
import 'notifications_page.dart';
import 'favourite_numbers_page.dart';
import 'sign_out_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name =
        (user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'])
            ?.toString()
            .trim();
    final email = user?.email?.trim();
    final avatarUrl =
        (user?.userMetadata?['avatar_url'] ?? user?.userMetadata?['picture'])
            ?.toString()
            .trim();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.12),
                      foregroundImage:
                          (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: Icon(
                        Icons.person_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (name != null && name.isNotEmpty)
                                ? name
                                : 'Settings',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (email != null && email.isNotEmpty)
                                ? email
                                : 'Signed in',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Account'),
              const SizedBox(height: 8),
              _buildSettingsTile(
                context,
                icon: Icons.person_outline_rounded,
                title: 'Edit Profile',
                subtitle: 'Manage your account information',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EditProfilePage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsTile(
                context,
                icon: Icons.logout_rounded,
                title: 'Sign out',
                subtitle: 'Sign out of your account',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SignOutPage()),
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsTile(
                context,
                icon: Icons.favorite_border_rounded,
                title: 'Favourite Numbers',
                subtitle: 'Manage your lucky numbers',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FavouriteNumbersPage(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Preferences'),
              const SizedBox(height: 8),
              _buildSettingsTile(
                context,
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Manage notification settings',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationsPage(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsTile(
                context,
                icon: Icons.dark_mode_outlined,
                title: 'Dark Mode',
                subtitle: 'Change app appearance',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const DarkModePage()),
                ),
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Support'),
              const SizedBox(height: 8),
              _buildSettingsTile(
                context,
                icon: Icons.feedback_outlined,
                title: 'Submit Feedback',
                subtitle: 'Share your thoughts and suggestions',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FeedbackPage()),
                ),
              ),
              const SizedBox(height: 12),
              _buildSettingsTile(
                context,
                icon: Icons.info_outline_rounded,
                title: 'About App',
                subtitle: 'App version and information',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutAppPage()),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
