import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';

final _peersProvider =
    StreamProvider<List<SyncPeer>>((ref) => ref.watch(syncServiceProvider).watchPeers());
final _conflictsProvider =
    StreamProvider<List<SyncConflict>>((ref) => ref.watch(syncServiceProvider).watchConflicts());

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _address = TextEditingController();
  bool _hosting = false;
  bool _busy = false;
  List<String> _addresses = [];

  @override
  void initState() {
    super.initState();
    _hosting = ref.read(syncServiceProvider).hosting;
    if (_hosting) _loadAddresses();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadAddresses() async {
    final list = await ref.read(syncServiceProvider).localAddresses();
    if (mounted) setState(() => _addresses = list);
  }

  Future<void> _toggleHost() async {
    final svc = ref.read(syncServiceProvider);
    setState(() => _busy = true);
    try {
      if (_hosting) {
        await svc.stopHost();
        setState(() {
          _hosting = false;
          _addresses = [];
        });
      } else {
        await svc.startHost();
        setState(() => _hosting = true);
        await _loadAddresses();
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Could not start sync host: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync(String address) async {
    final ip = address.trim();
    if (ip.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(syncServiceProvider).syncWith(ip);
      if (mounted) {
        showSnack(context,
            '${S.syncDone} ${r.pulled} received, ${r.pushed} sent, ${r.conflicts} conflict(s).');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Sync failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(_peersProvider);
    final conflicts = ref.watch(_conflictsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(S.sync)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.syncHint, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _toggleHost,
                  icon: Icon(_hosting ? Icons.stop : Icons.wifi_tethering),
                  label: Text(_hosting ? 'Stop hosting' : S.hostSync),
                ),
                if (_hosting) ...[
                  const SizedBox(height: 16),
                  const Text('This device address:'),
                  const SizedBox(height: 8),
                  for (final a in _addresses)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.router_outlined),
                      title: Text(a, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      trailing: IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: a));
                          showSnack(context, 'Address copied');
                        },
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text('Enter this address on the other device, then tap "${S.syncNow}".',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.connectSync, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: S.deviceAddress,
                    hintText: '192.168.1.20',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.sync),
                      onPressed: _busy ? null : () => _sync(_address.text),
                    ),
                  ),
                  onSubmitted: _busy ? null : _sync,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _sync(_address.text),
                    icon: _busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync),
                    label: const Text(S.syncNow),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader('Known devices'),
          peers.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8), child: Text(S.emptyList))
                : Column(
                    children: [
                      for (final peer in list)
                        ListTile(
                          leading: const Icon(Icons.devices_other),
                          title: Text(peer.peerName),
                          subtitle: Text(
                              '${peer.address}${peer.lastSyncAt != null ? ' - last sync ${fmtDateTime(peer.lastSyncAt!)}' : ' - never synced'}'),
                          trailing: TextButton(
                            onPressed: _busy ? null : () => _sync(peer.address),
                            child: const Text(S.syncNow),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(S.syncConflicts),
          conflicts.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(8), child: Text('No pending conflicts.'))
                : Column(
                    children: [
                      for (final c in list) _ConflictTile(conflict: c),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConflictTile extends ConsumerWidget {
  final SyncConflict conflict;
  const _ConflictTile({required this.conflict});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Map<String, dynamic> decode(String s) {
      try {
        return jsonDecode(s) as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    }

    final local = decode(conflict.localJson);
    final remote = decode(conflict.remoteJson);
    final keys = {...local.keys, ...remote.keys}
        .where((k) => local[k] != remote[k] && !k.endsWith('_at') && k != 'id')
        .toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        leading: const Icon(Icons.warning_amber, color: Color(0xFFF9A825)),
        title: Text('${conflict.targetTable} - ${conflict.recordId.substring(0, 8)}'),
        subtitle: Text('${keys.length} field(s) differ'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Table(
              columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.2), 2: FlexColumnWidth(1.2)},
              children: [
                const TableRow(children: [
                  Text('Field', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('This device', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('Other device', style: TextStyle(fontWeight: FontWeight.bold)),
                ]),
                for (final k in keys.take(12))
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.all(4), child: Text(k)),
                    Padding(padding: const EdgeInsets.all(4), child: Text('${local[k] ?? '-'}')),
                    Padding(padding: const EdgeInsets.all(4), child: Text('${remote[k] ?? '-'}')),
                  ]),
              ],
            ),
          ),
          OverflowBar(
            children: [
              OutlinedButton(
                onPressed: () async {
                  await ref.read(syncServiceProvider).resolveConflict(conflict.id, false);
                  if (context.mounted) showSnack(context, S.saved);
                },
                child: const Text(S.keepLocal),
              ),
              FilledButton(
                onPressed: () async {
                  await ref.read(syncServiceProvider).resolveConflict(conflict.id, true);
                  if (context.mounted) showSnack(context, S.saved);
                },
                child: const Text(S.useRemote),
              ),
            ],
          ),
        ],
      ),
    );
  }
}