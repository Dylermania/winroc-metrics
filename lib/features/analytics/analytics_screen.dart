import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/daos/finance_dao.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';

const _green = Color(0xFF1B7A3D);
const _gold = Color(0xFFF2C230);

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  String? _termId;

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(allTermsProvider);
    final current = ref.watch(currentTermProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.analytics),
        actions: [
          IconButton(
            tooltip: S.retry,
            icon: const Icon(Icons.refresh),
            onPressed: () {
              final id = _termId ?? current?.id;
              if (id != null) {
                ref.invalidate(_attAnalyticsProvider(id));
                ref.invalidate(_duesAnalyticsProvider(id));
              }
              ref.invalidate(allTermsProvider);
            },
          ),
        ],
      ),
      body: terms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) return const Center(child: Text(S.noDataForTerm));
          final selected =
              list.any((t) => t.id == _termId) ? _termId! : (current?.id ?? list.first.id);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: S.terms),
                items: [
                  for (final t in list)
                    DropdownMenuItem(
                        value: t.id,
                        child: Text(
                            'Term ${t.number} · ${fmtDateShort(t.startDate)}')),
                ],
                onChanged: (v) => setState(() => _termId = v),
              ),
            ),
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(children: [
                  const TabBar(tabs: [
                    Tab(text: S.attendance),
                    Tab(text: S.dues),
                  ]),
                  Expanded(
                    child: TabBarView(children: [
                      _AttendanceTab(termId: selected),
                      _DuesTab(termId: selected),
                    ]),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _AttendanceAnalytics {
  final double overallPct;
  final int sessionCount;
  final int recordCount;
  final double threshold;
  final Map<AttendanceStatus, int> statusCounts;
  final List<({String date, double pct})> trend;
  final List<({String teamName, double pct})> byTeam;
  final List<({Member member, double pct, int sessions})> leaderboard;
  final List<({Member member, double pct})> atRisk;
  _AttendanceAnalytics(this.overallPct, this.sessionCount, this.recordCount,
      this.threshold, this.statusCounts, this.trend, this.byTeam,
      this.leaderboard, this.atRisk);
}

final _attAnalyticsProvider =
    FutureProvider.family<_AttendanceAnalytics, String>((ref, termId) async {
  final db = ref.watch(databaseProvider);
  final att = ref.watch(attendanceDaoProvider);
  final threshold =
      double.tryParse(await db.setting('attendance_threshold', fallback: '75')) ?? 75;
  final counts = await att.statusCounts(termId);
  return _AttendanceAnalytics(
    await att.overallPct(termId),
    await att.sessionCount(termId),
    counts.values.fold(0, (a, b) => a + b),
    threshold,
    counts,
    await att.trend(termId),
    await att.attendanceByTeam(termId),
    await att.leaderboard(termId),
    await att.atRisk(threshold, termId),
  );
});

class _AttendanceTab extends ConsumerWidget {
  final String termId;
  const _AttendanceTab({required this.termId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_attAnalyticsProvider(termId));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (d) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kpiGrid(context, [
            StatCard(S.overallAttendance, '${d.overallPct.toStringAsFixed(0)}%',
                Icons.fact_check_outlined,
                color: d.overallPct < d.threshold ? Colors.red : _green),
            StatCard(S.sessionsHeld, '${d.sessionCount}', Icons.event_outlined),
            StatCard(S.recordsMarked, '${d.recordCount}', Icons.how_to_reg_outlined),
            StatCard(S.atRisk, '${d.atRisk.length}', Icons.warning_amber_outlined,
                color: d.atRisk.isEmpty ? _green : Colors.red),
          ]),
          const SizedBox(height: 16),
          _chartCard(
            context,
            S.attendanceTrend,
            d.trend.isEmpty
                ? const Text(S.noDataForTerm)
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
                        color: _green,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                            show: true, color: _green.withValues(alpha: 0.12)),
                      ),
                    ],
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true, reservedSize: 34, interval: 25)),
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
                              child: Text(d.trend[i].date.substring(5),
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  )),
          ),
          const SizedBox(height: 16),
          _chartCard(
            context,
            S.statusDistribution,
            d.recordCount == 0
                ? const Text(S.noDataForTerm)
                : _legendPie(
                    context,
                    [
                      for (final s in AttendanceStatus.values)
                        if (d.statusCounts[s]! > 0)
                          (s.label, d.statusCounts[s]!.toDouble(), s.color),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _chartCard(
            context,
            S.attendanceByTeam,
            d.byTeam.isEmpty
                ? const Text(S.noDataForTerm)
                : BarChart(BarChartData(
                    maxY: 100,
                    barGroups: [
                      for (var i = 0; i < d.byTeam.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                              toY: d.byTeam[i].pct,
                              color: _gold,
                              width: 26,
                              borderRadius: BorderRadius.circular(6)),
                        ]),
                    ],
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true, reservedSize: 34, interval: 25)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= d.byTeam.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(d.byTeam[i].teamName,
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  )),
          ),
          SectionHeader(S.leaderboard, action: Text('${d.leaderboard.length}')),
          for (final l in d.leaderboard.take(10))
            ListTile(
              leading: MemberAvatar(l.member, radius: 18),
              title: Text(l.member.fullName),
              trailing: Text('${l.sessions} sessions · ${l.pct.toStringAsFixed(0)}%'),
            ),
          if (d.leaderboard.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text(S.emptyList)),
          SectionHeader('${S.atRisk} (<${d.threshold.toStringAsFixed(0)}%)',
              action: Text('${d.atRisk.length}')),
          for (final a in d.atRisk.take(10))
            ListTile(
              leading: MemberAvatar(a.member, radius: 18),
              title: Text(a.member.fullName),
              trailing: Text('${a.pct.toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.red)),
            ),
          if (d.atRisk.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text(S.emptyList)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DuesAnalytics {
  final int income;
  final int expenses;
  final int net;
  final int charged;
  final double rate;
  final Map<PaymentMethod, int> byMethod;
  final List<({String month, int total})> monthly;
  final List<Defaulter> defaulters;
  _DuesAnalytics(this.income, this.expenses, this.net, this.charged, this.rate,
      this.byMethod, this.monthly, this.defaulters);
  int get outstanding => (charged - income).clamp(0, 1 << 62);
}

final _duesAnalyticsProvider =
    FutureProvider.family<_DuesAnalytics, String>((ref, termId) async {
  final fin = ref.watch(financeDaoProvider);
  final totals = await fin.termTotals(termId);
  return _DuesAnalytics(
    totals.income,
    totals.expenses,
    totals.net,
    await fin.termCharged(termId),
    await fin.collectionRate(termId),
    await fin.paymentsByMethod(termId),
    await fin.monthlyCollections(termId),
    await fin.defaulters(),
  );
});

class _DuesTab extends ConsumerWidget {
  final String termId;
  const _DuesTab({required this.termId});

  static const _methodColors = {
    PaymentMethod.cash: _green,
    PaymentMethod.mtnMomo: _gold,
    PaymentMethod.telecelCash: Color(0xFF1565C0),
    PaymentMethod.airteltigoMoney: Color(0xFFC62828),
    PaymentMethod.bank: Color(0xFF6A3FB5),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_duesAnalyticsProvider(termId));
    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (d) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _kpiGrid(context, [
            StatCard(S.collectedThisTerm, formatGhs(d.income), Icons.payments_outlined,
                color: _green),
            StatCard(S.expected, formatGhs(d.charged), Icons.request_quote_outlined),
            StatCard(S.outstanding, formatGhs(d.outstanding), Icons.pending_actions_outlined,
                color: d.outstanding > 0 ? Colors.red : _green),
            StatCard(S.collectionRate, '${d.rate.toStringAsFixed(0)}%',
                Icons.percent_outlined,
                color: d.rate < 50 ? Colors.red : _green),
          ]),
          const SizedBox(height: 16),
          _chartCard(
            context,
            '${S.income} vs ${S.expenses}',
            BarChart(BarChartData(
              maxY: (d.income > d.expenses ? d.income : d.expenses) / 100 * 1.2 + 1,
              barGroups: [
                BarChartGroupData(x: 0, barRods: [
                  BarChartRodData(
                      toY: d.income / 100,
                      color: _green,
                      width: 32,
                      borderRadius: BorderRadius.circular(6)),
                ]),
                BarChartGroupData(x: 1, barRods: [
                  BarChartRodData(
                      toY: d.expenses / 100,
                      color: const Color(0xFFC62828),
                      width: 32,
                      borderRadius: BorderRadius.circular(6)),
                ]),
              ],
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(v == 0 ? S.income : S.expenses,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              ),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              borderData: FlBorderData(show: false),
            )),
          ),
          const SizedBox(height: 16),
          _chartCard(
            context,
            S.paymentMethods,
            d.income == 0
                ? const Text(S.noDataForTerm)
                : _legendPie(
                    context,
                    [
                      for (final m in PaymentMethod.values)
                        if (d.byMethod[m]! > 0)
                          (m.label, d.byMethod[m]!.toDouble(), _methodColors[m]!),
                    ],
                    money: true,
                  ),
          ),
          const SizedBox(height: 16),
          _chartCard(
            context,
            S.monthlyCollections,
            d.monthly.isEmpty
                ? const Text(S.noDataForTerm)
                : BarChart(BarChartData(
                    maxY: d.monthly.map((m) => m.total).reduce((a, b) => a > b ? a : b) /
                            100 *
                            1.2 +
                        1,
                    barGroups: [
                      for (var i = 0; i < d.monthly.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                              toY: d.monthly[i].total / 100,
                              color: _green,
                              width: 26,
                              borderRadius: BorderRadius.circular(6)),
                        ]),
                    ],
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= d.monthly.length) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(d.monthly[i].month.substring(5),
                                  style: const TextStyle(fontSize: 10)),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: true, drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                  )),
          ),
          SectionHeader(S.defaulters, action: Text('${d.defaulters.length}')),
          for (final def in d.defaulters.take(10))
            ListTile(
              leading: MemberAvatar(def.member, radius: 18),
              title: Text(def.member.fullName),
              trailing: Text(formatGhs(def.owing),
                  style: const TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          if (d.defaulters.isEmpty)
            const Padding(padding: EdgeInsets.all(8), child: Text(S.emptyList)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

Widget _kpiGrid(BuildContext context, List<Widget> cards) => GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.5,
      children: cards,
    );

Widget _chartCard(BuildContext context, String title, Widget chart) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SizedBox(height: 200, child: chart),
        ]),
      ),
    );

Widget _legendPie(BuildContext context, List<(String, double, Color)> entries,
    {bool money = false}) {
  final total = entries.fold<double>(0, (s, e) => s + e.$2);
  return Row(children: [
    Expanded(
      child: PieChart(PieChartData(
        sections: [
          for (final e in entries)
            PieChartSectionData(
              value: e.$2,
              color: e.$3,
              radius: 52,
              title: total == 0 ? '' : '${(e.$2 * 100 / total).toStringAsFixed(0)}%',
              titleStyle: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
        ],
        centerSpaceRadius: 34,
        sectionsSpace: 2,
      )),
    ),
    const SizedBox(width: 12),
    Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 12, height: 12, color: e.$3),
                const SizedBox(width: 6),
                Text(
                    money
                        ? '${e.$1}: ${formatGhs(e.$2.round())}'
                        : '${e.$1}: ${e.$2.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12)),
              ]),
            ),
        ]),
  ]);
}