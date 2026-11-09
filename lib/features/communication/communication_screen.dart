import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';

final _announcementsProvider =
    StreamProvider<List<Announcement>>((ref) => ref.watch(clubDaoProvider).watchAnnouncements());
final _templatesProvider =
    StreamProvider<List<MessageTemplate>>((ref) => ref.watch(clubDaoProvider).watchTemplates());

String _kindLabel(TemplateKind k) => switch (k) {
      TemplateKind.duesReminder => 'Dues reminder',
      TemplateKind.guardianSummary => 'Guardian summary',
      TemplateKind.sessionReminder => 'Session reminder',
      TemplateKind.custom => 'Custom',
    };

const _placeholders = {
  'name': 'Ama Mensah',
  'balance': 'GHS 25.00',
  'date': 'Friday, 14 Nov 2026',
  'time': '3:30 PM',
  'session': 'Regular Meeting',
  'term': 'Term 1',
  'attendance': '92%',
  'club': S.clubName,
};

class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canEdit = (user?.role ?? ClubRole.member).can(Capability.viewAll);
    final items = ref.watch(_announcementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.announcements)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const _AnnouncementEditScreen())),
              icon: const Icon(Icons.add),
              label: const Text(S.newAnnouncement),
            )
          : null,
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text(S.emptyList))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final a = list[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: a.pinned
                          ? const Icon(Icons.push_pin, color: Color(0xFFF2C230))
                          : const Icon(Icons.announcement_outlined),
                      title: Text(a.title,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(a.body),
                          const SizedBox(height: 4),
                          Text(fmtDateTime(a.createdAt),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(a.title),
                          content: SingleChildScrollView(child: Text(a.body)),
                          actions: [
                            TextButton.icon(
                              onPressed: () => Share.share('${a.title}\n\n${a.body}'),
                              icon: const Icon(Icons.share),
                              label: const Text(S.share),
                            ),
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text(S.close)),
                          ],
                        ),
                      ),
                      trailing: canEdit
                          ? PopupMenuButton<String>(
                              onSelected: (v) async {
                                final dao = ref.read(clubDaoProvider);
                                if (v == 'edit') {
                                  Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => _AnnouncementEditScreen(existing: a)));
                                } else if (v == 'pin') {
                                  await dao.saveAnnouncement(
                                      AnnouncementsCompanion(
                                          id: Value(a.id),
                                          pinned: Value(!a.pinned),
                                          updatedAt: Value(nowIso())),
                                      a.id,
                                      isNew: false);
                                } else if (v == 'delete') {
                                  final ok = await confirmDialog(context, S.delete, a.title);
                                  if (ok) {
                                    await dao.deleteAnnouncement(a.id);
                                    if (context.mounted) showSnack(context, S.deleted);
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'edit', child: Text(S.edit)),
                                PopupMenuItem(
                                    value: 'pin',
                                    child: Text(a.pinned ? 'Unpin' : 'Pin to top')),
                                const PopupMenuItem(value: 'delete', child: Text(S.delete)),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _AnnouncementEditScreen extends ConsumerStatefulWidget {
  final Announcement? existing;
  const _AnnouncementEditScreen({this.existing});

  @override
  ConsumerState<_AnnouncementEditScreen> createState() => _AnnouncementEditScreenState();
}

class _AnnouncementEditScreenState extends ConsumerState<_AnnouncementEditScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    if (a != null) {
      _title.text = a.title;
      _body.text = a.body;
      _pinned = a.pinned;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      showSnack(context, S.required);
      return;
    }
    final id = widget.existing?.id ?? newId();
    final user = ref.read(currentUserProvider);
    await ref.read(clubDaoProvider).saveAnnouncement(
          AnnouncementsCompanion(
            id: Value(id),
            title: Value(_title.text.trim()),
            body: Value(_body.text.trim()),
            pinned: Value(_pinned),
            createdBy: Value(user?.id ?? ''),
            createdAt: Value(widget.existing?.createdAt ?? nowIso()),
            updatedAt: Value(nowIso()),
          ),
          id,
          isNew: widget.existing == null,
        );
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, S.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? S.newAnnouncement : S.edit)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: S.title)),
          const SizedBox(height: 16),
          TextField(
              controller: _body,
              maxLines: 8,
              decoration: const InputDecoration(labelText: S.body, alignLabelWithHint: true)),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
            title: const Text(S.pinned),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _save, icon: const Icon(Icons.save), label: const Text(S.save)),
        ],
      ),
    );
  }
}

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_templatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.messageTemplates)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const _TemplateEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text(S.add),
      ),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text(S.emptyList))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final t = list[i];
                  final preview = fillTemplate(t.body, _placeholders);
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.message_outlined),
                      title: Text(_kindLabel(t.kind),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(preview, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: Text(_kindLabel(t.kind)),
                          content: SingleChildScrollView(child: Text(preview)),
                          actions: [
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: preview));
                                showSnack(context, S.copyMessage);
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text(S.copyMessage),
                            ),
                            TextButton.icon(
                              onPressed: () => Share.share(preview),
                              icon: const Icon(Icons.share),
                              label: const Text(S.shareMessage),
                            ),
                          ],
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => _TemplateEditScreen(existing: t)));
                          } else if (v == 'copy') {
                            await Clipboard.setData(ClipboardData(text: preview));
                            if (context.mounted) showSnack(context, S.copyMessage);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text(S.edit)),
                          PopupMenuItem(value: 'copy', child: Text(S.copyMessage)),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _TemplateEditScreen extends ConsumerStatefulWidget {
  final MessageTemplate? existing;
  const _TemplateEditScreen({this.existing});

  @override
  ConsumerState<_TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TemplateEditScreenState extends ConsumerState<_TemplateEditScreen> {
  final _body = TextEditingController();
  TemplateKind _kind = TemplateKind.custom;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    if (t != null) {
      _body.text = t.body;
      _kind = t.kind;
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_body.text.trim().isEmpty) {
      showSnack(context, S.required);
      return;
    }
    final id = widget.existing?.id ?? newId();
    await ref.read(clubDaoProvider).saveTemplate(
          MessageTemplatesCompanion(
            id: Value(id),
            kind: Value(_kind),
            body: Value(_body.text.trim()),
            createdAt: Value(widget.existing?.createdAt ?? nowIso()),
            updatedAt: Value(nowIso()),
          ),
          id,
          isNew: widget.existing == null,
        );
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, S.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'New template' : S.edit)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<TemplateKind>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final k in TemplateKind.values)
                DropdownMenuItem(value: k, child: Text(_kindLabel(k))),
            ],
            onChanged: (v) => setState(() => _kind = v ?? TemplateKind.custom),
          ),
          const SizedBox(height: 16),
          TextField(
              controller: _body,
              maxLines: 8,
              decoration: const InputDecoration(
                  labelText: S.body,
                  alignLabelWithHint: true,
                  helperText: 'Placeholders: {name} {balance} {date} {time} {session} {term} {attendance} {club}',
                  helperMaxLines: 3)),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _save, icon: const Icon(Icons.save), label: const Text(S.save)),
        ],
      ),
    );
  }
}