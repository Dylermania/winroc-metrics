import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(_projectsProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.can(Capability.members) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(S.projects)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text(S.newProject),
              onPressed: () => showDialog(
                  context: context, builder: (_) => const _ProjectDialog()))
          : null,
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const Center(child: Text(S.emptyList))
            : ListView(children: [
                for (final p in list)
                  ListTile(
                    leading: const Icon(Icons.precision_manufacturing_outlined),
                    title: Text(p.name),
                    subtitle: Text(p.description ?? ''),
                    trailing: StatusChip(p.status.label,
                        p.status == ProjectStatus.active ? Colors.green : Colors.grey),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ProjectDetailScreen(projectId: p.id))),
                  ),
              ]),
      ),
    );
  }
}

final _projectsProvider =
    StreamProvider<List<Project>>((ref) => ref.watch(clubDaoProvider).watchProjects());

class _ProjectDialog extends ConsumerStatefulWidget {
  const _ProjectDialog();
  @override
  ConsumerState<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends ConsumerState<_ProjectDialog> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  ProjectStatus _status = ProjectStatus.planning;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.newProject),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: S.projectName)),
          const SizedBox(height: 12),
          TextField(controller: _desc, maxLines: 3, decoration: const InputDecoration(labelText: S.description)),
          const SizedBox(height: 12),
          DropdownButtonFormField<ProjectStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: S.status),
            items: [for (final s in ProjectStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (v) => setState(() => _status = v ?? ProjectStatus.planning),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            if (_name.text.trim().isEmpty) return;
            final id = newId();
            await ref.read(clubDaoProvider).saveProject(
              ProjectsCompanion.insert(
                id: id,
                name: _name.text.trim(),
                description: Value(_desc.text.trim().isEmpty ? null : _desc.text.trim()),
                status: Value(_status),
                startDate: Value(dateOnly(DateTime.now())),
                createdAt: nowIso(),
                updatedAt: nowIso(),
              ),
              id,
              isNew: true,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class ProjectDetailScreen extends ConsumerWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(_projectProvider(projectId)).value;
    final members = ref.watch(_projectMembersProvider(projectId));
    final hours = ref.watch(_projectHoursProvider(projectId));
    final allMembers = ref.watch(_allActiveProvider).value ?? [];
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.can(Capability.members) ?? false;
    if (project == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(project.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(project.description ?? ''),
        const SizedBox(height: 8),
        StatusChip(project.status.label, Colors.green),
        const SizedBox(height: 16),
        if (canEdit)
          OutlinedButton.icon(
            icon: const Icon(Icons.group_add_outlined),
            label: const Text(S.assignMembers),
            onPressed: () => showDialog(
                context: context,
                builder: (_) => _AssignMembersDialog(
                    all: allMembers,
                    current: (members.value ?? []).map((m) => m.id).toSet(),
                    onSave: (ids) =>
                        ref.read(clubDaoProvider).setProjectMembers(projectId, ids))),
          ),
        SectionHeader(S.members),
        members.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => Column(children: [
            for (final m in list)
              ListTile(
                leading: MemberAvatar(m, radius: 18),
                title: Text(m.fullName),
                trailing: canEdit
                    ? IconButton(
                        tooltip: S.logHours,
                        icon: const Icon(Icons.timer_outlined),
                        onPressed: () => showDialog(
                            context: context,
                            builder: (_) => _LogHoursDialog(
                                projectId: projectId, member: m)),
                      )
                    : null,
              ),
          ]),
        ),
        SectionHeader(S.hours),
        hours.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => Column(children: [
            for (final h in list.take(20))
              ListTile(
                dense: true,
                title: Text('${h.hours.toStringAsFixed(1)} h — ${fmtDateShort(h.workDate)}'),
                subtitle: h.note == null ? null : Text(h.note!),
              ),
            if (list.isEmpty) const Text(S.emptyList),
          ]),
        ),
      ]),
    );
  }
}

final _projectProvider = FutureProvider.family<Project?, String>((ref, id) async {
  final list = await ref.watch(clubDaoProvider).watchProjects().first;
  return list.where((p) => p.id == id).firstOrNull;
});

final _projectMembersProvider = FutureProvider.family<List<Member>, String>(
    (ref, id) => ref.watch(clubDaoProvider).projectMembers(id));

final _projectHoursProvider = FutureProvider.family<List<ProjectHour>, String>(
    (ref, id) => ref.watch(clubDaoProvider).projectHours(id));

final _allActiveProvider =
    FutureProvider<List<Member>>((ref) => ref.watch(memberDaoProvider).activeMembers());

class _AssignMembersDialog extends StatefulWidget {
  final List<Member> all;
  final Set<String> current;
  final ValueChanged<List<String>> onSave;
  const _AssignMembersDialog(
      {required this.all, required this.current, required this.onSave});
  @override
  State<_AssignMembersDialog> createState() => _AssignMembersDialogState();
}

class _AssignMembersDialogState extends State<_AssignMembersDialog> {
  late Set<String> _selected = {...widget.current};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.assignMembers),
      content: SizedBox(
        width: 400,
        height: 400,
        child: ListView(children: [
          for (final m in widget.all)
            CheckboxListTile(
              title: Text(m.fullName),
              value: _selected.contains(m.id),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(m.id);
                } else {
                  _selected.remove(m.id);
                }
              }),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () {
            widget.onSave(_selected.toList());
            Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class _LogHoursDialog extends ConsumerStatefulWidget {
  final String projectId;
  final Member member;
  const _LogHoursDialog({required this.projectId, required this.member});
  @override
  ConsumerState<_LogHoursDialog> createState() => _LogHoursDialogState();
}

class _LogHoursDialogState extends ConsumerState<_LogHoursDialog> {
  final _hours = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${S.logHours} — ${widget.member.fullName}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _hours,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: S.hours)),
        const SizedBox(height: 12),
        TextField(controller: _note, decoration: const InputDecoration(labelText: '${S.notes} (${S.optional})')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            final h = double.tryParse(_hours.text);
            if (h == null || h <= 0) return;
            await ref.read(clubDaoProvider).logHours(widget.projectId, widget.member.id, h, _note.text.trim());
            if (context.mounted) {
              Navigator.pop(context);
              ref.invalidate(_projectHoursProvider(widget.projectId));
            }
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_inventoryProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.can(Capability.members) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(S.inventory)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text(S.newItem),
              onPressed: () => showDialog(
                  context: context, builder: (_) => const _ItemDialog()))
          : null,
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(children: [
          for (final item in list)
            _InventoryTile(item: item, canEdit: canEdit),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text(S.emptyList))),
        ]),
      ),
    );
  }
}

final _inventoryProvider = StreamProvider<List<InventoryItem>>(
    (ref) => ref.watch(clubDaoProvider).watchInventory());

class _InventoryTile extends ConsumerWidget {
  final InventoryItem item;
  final bool canEdit;
  const _InventoryTile({required this.item, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(_availableProvider(item.id)).value ?? item.totalQty;
    final low = available <= item.lowStockThreshold;
    final members = ref.watch(_allActiveProvider).value ?? [];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Icon(Icons.inventory_2_outlined, color: low ? Colors.red : null),
        title: Text(item.name),
        subtitle: Text('${S.quantity}: $available/${item.totalQty}${item.location != null ? ' · ${item.location}' : ''}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (low) const StatusChip(S.lowStock, Colors.red),
          if (canEdit)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'out') {
                  showDialog(
                      context: context,
                      builder: (_) => _CheckoutDialog(item: item, members: members));
                } else {
                  final loans = await ref.read(clubDaoProvider).openLoans(itemId: item.id);
                  if (!context.mounted) return;
                  showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: Text(S.checkInItem),
                        content: SizedBox(
                          width: 380,
                          child: loans.isEmpty
                              ? const Text(S.emptyList)
                              : ListView(shrinkWrap: true, children: [
                                  for (final l in loans)
                                    ListTile(
                                      title: Text('${l.qty} × ${item.name}'),
                                      subtitle: Text(fmtDateTime(l.checkedOutAt)),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.check_circle_outline),
                                        onPressed: () async {
                                          await ref.read(clubDaoProvider).checkIn(l.id, 'Good');
                                          if (context.mounted) {
                                            Navigator.pop(context);
                                            ref.invalidate(_availableProvider(item.id));
                                          }
                                        },
                                      ),
                                    ),
                                ]),
                        ),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.close))],
                      ));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'out', child: Text(S.checkOut)),
                PopupMenuItem(value: 'in', child: Text(S.checkInItem)),
              ],
            ),
        ]),
      ),
    );
  }
}

final _availableProvider =
    FutureProvider.family<int, String>((ref, id) => ref.watch(clubDaoProvider).availableQty(id));

class _ItemDialog extends ConsumerStatefulWidget {
  const _ItemDialog();
  @override
  ConsumerState<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends ConsumerState<_ItemDialog> {
  final _name = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _threshold = TextEditingController(text: '2');
  final _location = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _threshold.dispose();
    _location.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.newItem),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: S.itemName)),
          const SizedBox(height: 12),
          TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: S.quantity)),
          const SizedBox(height: 12),
          TextField(controller: _threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: S.lowStockThreshold)),
          const SizedBox(height: 12),
          TextField(controller: _location, decoration: const InputDecoration(labelText: '${S.location} (${S.optional})')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            if (_name.text.trim().isEmpty) return;
            final id = newId();
            await ref.read(clubDaoProvider).saveItem(
              InventoryItemsCompanion.insert(
                id: id,
                name: _name.text.trim(),
                totalQty: int.tryParse(_qty.text) ?? 1,
                lowStockThreshold: Value(int.tryParse(_threshold.text) ?? 2),
                location: Value(_location.text.trim().isEmpty ? null : _location.text.trim()),
                createdAt: nowIso(),
                updatedAt: nowIso(),
              ),
              id,
              isNew: true,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class _CheckoutDialog extends ConsumerStatefulWidget {
  final InventoryItem item;
  final List<Member> members;
  const _CheckoutDialog({required this.item, required this.members});
  @override
  ConsumerState<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<_CheckoutDialog> {
  Member? _member;
  final _qty = TextEditingController(text: '1');

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${S.checkOut} — ${widget.item.name}'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<Member>(
            decoration: const InputDecoration(labelText: S.members),
            items: [for (final m in widget.members) DropdownMenuItem(value: m, child: Text(m.fullName))],
            onChanged: (v) => setState(() => _member = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: S.quantity)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            final qty = int.tryParse(_qty.text) ?? 1;
            if (_member == null) return;
            final available = await ref.read(clubDaoProvider).availableQty(widget.item.id);
            if (qty > available) {
              if (context.mounted) showSnack(context, 'Not enough stock available.');
              return;
            }
            await ref.read(clubDaoProvider).checkOut(widget.item.id, _member!.id, qty, null);
            if (context.mounted) {
              Navigator.pop(context);
              ref.invalidate(_availableProvider(widget.item.id));
            }
          },
          child: const Text(S.checkOut),
        ),
      ],
    );
  }
}

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(_eventsProvider);
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.role.can(Capability.members) ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(S.events)),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text(S.newEvent),
              onPressed: () => showDialog(
                  context: context, builder: (_) => const _EventDialog()))
          : null,
      body: events.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => ListView(children: [
          for (final e in list)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                leading: const Icon(Icons.emoji_events_outlined),
                title: Text(e.name),
                subtitle: Text('${fmtDateShort(e.date)}${e.location != null ? ' · ${e.location}' : ''}${e.feePesewas > 0 ? ' · ${formatGhs(e.feePesewas)}' : ''}'),
                trailing: e.result != null ? StatusChip(e.result!, const Color(0xFFB8860B)) : null,
                onTap: canEdit
                    ? () => showDialog(
                        context: context, builder: (_) => _EventDetailDialog(event: e))
                    : null,
              ),
            ),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text(S.emptyList))),
        ]),
      ),
    );
  }
}

final _eventsProvider =
    StreamProvider<List<Event>>((ref) => ref.watch(clubDaoProvider).watchEvents());

class _EventDialog extends ConsumerStatefulWidget {
  const _EventDialog();
  @override
  ConsumerState<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends ConsumerState<_EventDialog> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _fee = TextEditingController();
  String? _date;

  @override
  void initState() {
    super.initState();
    _date = dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _fee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.newEvent),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: S.eventName)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${S.date}: ${fmtDateShort(_date)}'),
            onTap: () async {
              final d = await pickDate(context, initial: _date);
              if (d != null) setState(() => _date = d);
            },
          ),
          TextField(controller: _location, decoration: const InputDecoration(labelText: S.location)),
          const SizedBox(height: 12),
          MoneyField(_fee, label: S.fee),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            if (_name.text.trim().isEmpty) return;
            final id = newId();
            await ref.read(clubDaoProvider).saveEvent(
              EventsCompanion.insert(
                id: id,
                name: _name.text.trim(),
                date: '${_date}T00:00:00',
                location: Value(_location.text.trim().isEmpty ? null : _location.text.trim()),
                feePesewas: Value(parseGhs(_fee.text)),
                createdAt: nowIso(),
                updatedAt: nowIso(),
              ),
              id,
              isNew: true,
            );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}

class _EventDetailDialog extends ConsumerStatefulWidget {
  final Event event;
  const _EventDetailDialog({required this.event});
  @override
  ConsumerState<_EventDetailDialog> createState() => _EventDetailDialogState();
}

class _EventDetailDialogState extends ConsumerState<_EventDetailDialog> {
  final _result = TextEditingController();
  Set<String> _attendees = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _result.text = widget.event.result ?? '';
    ref.read(clubDaoProvider).eventAttendees(widget.event.id).then((list) {
      if (mounted) {
        setState(() {
          _attendees = list.map((m) => m.id).toSet();
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _result.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_allActiveProvider).value ?? [];
    return AlertDialog(
      title: Text(widget.event.name),
      content: SizedBox(
        width: 420,
        height: 440,
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                TextField(controller: _result, decoration: const InputDecoration(labelText: '${S.result} (e.g. 1st place)')),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(children: [
                    for (final m in members)
                      CheckboxListTile(
                        dense: true,
                        title: Text(m.fullName),
                        value: _attendees.contains(m.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _attendees.add(m.id);
                          } else {
                            _attendees.remove(m.id);
                          }
                        }),
                      ),
                  ]),
                ),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.cancel)),
        FilledButton(
          onPressed: () async {
            final dao = ref.read(clubDaoProvider);
            await dao.setEventAttendees(widget.event.id, _attendees.toList());
            final won = _result.text.toLowerCase().contains(RegExp(r'1st|winner|gold|champion'));
            await dao.saveEvent(
              EventsCompanion(
                id: Value(widget.event.id),
                result: Value(_result.text.trim().isEmpty ? null : _result.text.trim()),
                updatedAt: Value(nowIso()),
              ),
              widget.event.id,
              isNew: false,
            );
            if (won) {
              for (final id in _attendees) {
                await dao.checkAutoBadges(id, competitionWin: true);
              }
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text(S.save),
        ),
      ],
    );
  }
}