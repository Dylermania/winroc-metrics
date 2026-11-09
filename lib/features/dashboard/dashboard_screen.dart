import 'package:fl_chart/fl_chart.dart';
import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/daos/finance_dao.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';
import '../attendance/attendance_screen.dart';
import '../members/members_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user?.role == ClubRole.member && user?.memberId != null) {
      return _MyRecordView(memberId: user!.memberId!);
    }
    final term = ref.watch(currentTermProvider).value;
    final data = ref.watch(_dashboardProvider(term?.id));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (d) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: [
              StatCard(S.todayAttendance, '${d.todayPresent}/${d.todayTotal}', Icons.fact_check_outlined),
              StatCard(S.collectedThisTerm, formatGhs(d.income), Icons.payments_outlined),
              StatCard(S.netBalance, formatGhs(d.net), Icons.account_balance_outlined, color: d.net < 0 ? Colors.red : null),
              StatCard(S.clubHealth, '${d.health.toStringAsFixed(0)}%', Icons.favorite_outline, color: d.health < 50 ? Colors.red : Colors.green),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.attendanceTrend, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: d.trend.isEmpty
                      ? const Center(child: Text(S.emptyList))
                      : LineChart(LineChartData(
                          minY: 0,
                          maxY: 100,
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < d.trend.length; i++)
                                  FlSpot(i.toDouble(), d.trend[i].pct),
                              ],
                              isCurved: true,
                              color: const Color(0xFF1B7A3D),
                              barWidth: 3,
                              dotData: const FlDotData(show: true),
                              belowBarData: BarAreaData(
                                  show: true, color: const Color(0xFF1B7A3D).withValues(alpha: 0.12)),
                            ),
                          ],
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: 25)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                interval: (d.trend.length / 6).ceilToDouble().clamp(1, 100),
                                getTitlesWidget: (v, meta) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= d.trend.length) return const SizedBox();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(d.trend[i].date.substring(5), style: const TextStyle(fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                        )),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${S.income} vs ${S.expenses}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: BarChart(BarChartData(
                    maxY: (d.income > d.expenses ? d.income : d.expenses) / 100 * 1.2 + 1,
                    barGroups: [
                      BarChartGroupData(x: 0, barRods: [
                        BarChartRodData(toY: d.income / 100, color: const Color(0xFF1B7A3D), width: 32, borderRadius: BorderRadius.circular(6)),
                      ]),
                      BarChartGroupData(x: 1, barRods: [
                        BarChartRodData(toY: d.expenses / 100, color: const Color(0xFFC62828), width: 32, borderRadius: BorderRadius.circular(6)),
                      ]),
                    ],
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(v == 0 ? S.income : S.expenses, style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(S.attendanceByTeam, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: d.byTeam.isEmpty
                      ? const Center(child: Text(S.emptyList))
                      : BarChart(BarChartData(
                          maxY: 100,
                          barGroups: [
                            for (var i = 0; i < d.byTeam.length; i++)
                              BarChartGroupData(x: i, barRods: [
                                BarChartRodData(
                                    toY: d.byTeam[i].pct,
                                    color: const Color(0xFFF2C230),
                                    width: 26,
                                    borderRadius: BorderRadius.circular(6)),
                              ]),
                          ],
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: 25)),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 30,
                                getTitlesWidget: (v, meta) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= d.byTeam.length) return const SizedBox();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(d.byTeam[i].teamName, style: const TextStyle(fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: true, drawVerticalLine: false),
                          borderData: FlBorderData(show: false),
                        )),
                ),
              ]),
            ),
          ),
          SectionHeader(S.upcomingSessions),
          for (final s in d.upcoming.take(4))
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(s.title),
              subtitle: Text('${fmtDateShort(s.date)} · ${fmtTimeOfDay(s.startTime)}'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SessionScreen(sessionId: s.id))),
            ),
          if (d.upcoming.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text(S.emptyList)),
          SectionHeader(S.defaulters, action: Text('${d.defaulters.length}')),
          for (final def in d.defaulters.take(5))
            ListTile(
              leading: MemberAvatar(def.member, radius: 18),
              title: Text(def.member.fullName),
              trailing: Text(formatGhs(def.owing), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MemberDetailScreen(memberId: def.member.id))),
            ),
          SectionHeader('${S.atRisk} (<${d.threshold.toStringAsFixed(0)}%)'),
          for (final a in d.atRisk.take(5))
            ListTile(
              leading: MemberAvatar(a.member, radius: 18),
              title: Text(a.member.fullName),
              trailing: Text('${a.pct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.red)),
            ),
          if (d.atRisk.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text(S.emptyList)),
          SectionHeader('${S.leaderboard} — ${S.perfectAttendance}'),
          for (final l in d.leaderboard.take(5))
            ListTile(
              leading: const Icon(Icons.emoji_events_outlined, color: Color(0xFFB8860B)),
              title: Text(l.member.fullName),
              trailing: Text('${l.sessions} sessions'),
            ),
          if (d.leaderboard.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text(S.emptyList)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DashboardData {
  final int todayPresent;
  final int todayTotal;
  final int income;
  final int expenses;
  final int net;
  final double health;
  final double threshold;
  final List<({String date, double pct})> trend;
  final List<({String teamName, double pct})> byTeam;
  final List<Session> upcoming;
  final List<Defaulter> defaulters;
  final List<({Member member, double pct})> atRisk;
  final List<({Member member, double pct, int sessions})> leaderboard;
  _DashboardData(this.todayPresent, this.todayTotal, this.income, this.expenses, this.net,
      this.health, this.threshold, this.trend, this.byTeam, this.upcoming,
      this.defaulters, this.atRisk, this.leaderboard);
}

final _dashboardProvider =
    FutureProvider.family<_DashboardData, String?>((ref, termId) async {
  final db = ref.watch(databaseProvider);
  final att = ref.watch(attendanceDaoProvider);
  final fin = ref.watch(financeDaoProvider);
  final members = await ref.watch(memberDaoProvider).activeMembers();
  final today = dateOnly(DateTime.now());
  final todaySessions = await (db.select(db.sessions)
        ..where((s) => s.date.equals(today) & s.deletedAt.isNull()))
      .get();
  var todayPresent = 0;
  var todayTotal = 0;
  for (final s in todaySessions) {
    final records = await att.recordsFor(s.id);
    todayPresent += records.where((r) => r.status.countsAsPresent).length;
    todayTotal += members.length;
  }
  final totals = termId == null
      ? (income: 0, expenses: 0, net: 0)
      : await fin.termTotals(termId);
  final rate = termId == null ? 100.0 : await fin.collectionRate(termId);
  final trend = termId == null ? <({String date, double pct})>[] : await att.trend(termId);
  final byTeam = termId == null ? <({String teamName, double pct})>[] : await att.attendanceByTeam(termId);
  final threshold = double.tryParse(await db.setting('attendance_threshold', fallback: '75')) ?? 75;
  final atRisk = termId == null ? <({Member member, double pct})>[] : await att.atRisk(threshold, termId);
  final defaulters = await fin.defaulters();
  final leaderboard = termId == null ? <({Member member, double pct, int sessions})>[] : await att.leaderboard(termId);
  final upcoming = await att.watchSessions(upcomingOnly: true).first;
  var avgPct = 100.0;
  if (trend.isNotEmpty) {
    avgPct = trend.map((t) => t.pct).reduce((a, b) => a + b) / trend.length;
  }
  final defaulterShare = members.isEmpty ? 0 : defaulters.length * 100 / members.length;
  final health = (avgPct * 0.4 + rate * 0.4 + (100 - defaulterShare) * 0.2).clamp(0, 100);
  return _DashboardData(todayPresent, todayTotal, totals.income, totals.expenses,
      totals.net, health.toDouble(), threshold, trend, byTeam, upcoming, defaulters, atRisk, leaderboard);
});

class _MyRecordView extends ConsumerWidget {
  final String memberId;
  const _MyRecordView({required this.memberId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final member = ref.watch(_myMemberProvider(memberId)).value;
    if (member == null) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        child: ListTile(
          leading: MemberAvatar(member, radius: 28),
          title: Text(member.fullName),
          subtitle: Text('${S.form} ${member.form} · ${member.studentId}'),
          trailing: StatusChip(member.status.label, member.status.color),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text(S.reportCard),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MemberDetailScreen(memberId: memberId))),
      ),
    ]);
  }
}

final _myMemberProvider =
    FutureProvider.family<Member?, String>((ref, id) => ref.watch(memberDaoProvider).get(id));