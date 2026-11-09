import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../providers.dart';
import '../communication/communication_screen.dart';
import '../reports/reports_screen.dart';
import '../robotics/robotics_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final role = user?.role ?? ClubRole.member;
    final items = <(IconData, String, Widget, bool)>[
      (Icons.picture_as_pdf_outlined, S.reports, const ReportsScreen(), role.can(Capability.viewAll)),
      (Icons.announcement_outlined, S.announcements, const AnnouncementsScreen(), true),
      (Icons.message_outlined, S.messageTemplates, const TemplatesScreen(), role.can(Capability.viewAll)),
      (Icons.precision_manufacturing_outlined, S.projects, const ProjectsScreen(), role.can(Capability.viewAll)),
      (Icons.inventory_2_outlined, S.inventory, const InventoryScreen(), role.can(Capability.viewAll)),
      (Icons.emoji_events_outlined, S.events, const EventsScreen(), role.can(Capability.viewAll)),
      (Icons.sync_outlined, S.sync, const SyncScreen(), role.can(Capability.admin)),
      (Icons.settings_outlined, S.settings, const SettingsScreen(), true),
    ];
    return ListView(children: [
      for (final (icon, label, screen, allowed) in items)
        if (allowed)
          ListTile(
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => screen)),
          ),
    ]);
  }
}