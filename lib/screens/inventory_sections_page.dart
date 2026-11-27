import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'school_settings_page.dart';

import 'inventory_page.dart';

/// Seller/manager home: the two products share inventory data and audit
/// collections, but their checkout workflows are intentionally independent.
class InventorySectionsPage extends StatelessWidget {
  const InventorySectionsPage({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Shop'),
        actions: [
          const SchoolSettingsButton(),
          if (role == 'canteen_seller' || role == 'inventory_manager')
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => FirebaseAuth.instance.signOut(),
              icon: const Icon(Icons.logout_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text('Choose sales section',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Canteen checkout is fast for break time. '
                'Stationery keeps named customers and borrowed payments.',
              style: TextStyle(color: color.onSurfaceVariant)),
            const SizedBox(height: 18),
            _sectionCard(
              context,
              key: const Key('inventory_canteen_section_card'),
              title: 'Canteen Sales',
              subtitle: 'Fast cash sales • Student, Teacher or Other',
              icon: Icons.fastfood_outlined,
              department: 'canteen',
            ),
            const SizedBox(height: 12),
            _sectionCard(
              context,
              key: const Key('inventory_stationery_section_card'),
              title: 'Stationery & Books',
              subtitle: 'Detailed checkout • Student accounts and borrowed sales',
              icon: Icons.menu_book_outlined,
              department: 'stationery',
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required String department,
  }) {
    final color = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) =>
              InventoryPage(role: role, department: department)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
          child: Row(children: [
            Icon(icon, size: 32, color: color.primary),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w800,
                    fontSize: 16)),
                const SizedBox(height: 6),
                Text(subtitle,
                  style: TextStyle(color: color.onSurfaceVariant, fontSize: 12)),
              ],
            )),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
