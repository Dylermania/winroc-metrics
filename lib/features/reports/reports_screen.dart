import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';
import 'pdf_reports.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _from;
  String? _to;

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(_reportMembersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(S.reports)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(S.dateRange, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickDate(context, initial: _from);
                      if (d != null) setState(() => _from = d);
                    },
                    child: Text('${S.from}: ${_from == null ? 'any' : fmtDateShort(_from)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await pickDate(context, initial: _to);
                      if (d != null) setState(() => _to = d);
                    },
                    child: Text('${S.to}: ${_to == null ? 'any' : fmtDateShort(_to)}'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _ReportTile(
          icon: Icons.fact_check_outlined,
          title: S.attendanceRegister,
          onTap: () => PdfReports.attendanceRegister(context, ref, from: _from, to: _to),
        ),
        _ReportTile(
          icon: Icons.account_balance_wallet_outlined,
          title: S.duesLedger,
          onTap: () => PdfReports.duesLedger(context, ref),
        ),
        _ReportTile(
          icon: Icons.warning_amber_outlined,
          title: S.defaulters,
          onTap: () => PdfReports.defaultersList(context, ref),
        ),
        _ReportTile(
          icon: Icons.account_balance_outlined,
          title: S.financialStatement,
          onTap: () => PdfReports.financialStatement(context, ref),
        ),
        _ReportTile(
          icon: Icons.school_outlined,
          title: S.termReport,
          onTap: () => PdfReports.termReport(context, ref),
        ),
        _ReportTile(
          icon: Icons.badge_outlined,
          title: S.printIdCards,
          onTap: () async {
            final list = await ref.read(memberDaoProvider).activeMembers();
            if (context.mounted) await PdfReports.idCards(context, ref, list);
          },
        ),
        SectionHeader(S.reportCard),
        members.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text('$e'),
          data: (list) => DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: S.members),
            items: [
              for (final m in list)
                DropdownMenuItem(value: m.id, child: Text('${m.fullName} (${m.studentId})')),
            ],
            onChanged: (id) async {
              final m = list.firstWhere((x) => x.id == id);
              await PdfReports.memberReportCard(context, ref, m);
            },
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }
}

final _reportMembersProvider =
    FutureProvider<List<Member>>((ref) => ref.watch(memberDaoProvider).activeMembers());

class _ReportTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _ReportTile({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        trailing: const Icon(Icons.picture_as_pdf_outlined),
        onTap: onTap,
      ),
    );
  }
}