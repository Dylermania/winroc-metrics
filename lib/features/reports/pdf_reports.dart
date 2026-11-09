import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../core/utils.dart';
import '../../data/database.dart';
import '../../providers.dart';
import '../../shared/widgets.dart';

class PdfReports {
  static Future<pw.MemoryImage> _logo() async {
    final bytes = await rootBundle.load('assets/branding/logo.jpg');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static pw.Widget _header(pw.MemoryImage logo, String title, String school) {
    return pw.Row(children: [
      pw.Image(logo, width: 56, height: 56),
      pw.SizedBox(width: 12),
      pw.Expanded(
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(school, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(S.clubName, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1B7A3D'))),
        ]),
      ),
    ]);
  }

  static pw.Widget _footer(String officer) {
    return pw.Column(children: [
      pw.Divider(),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('${S.generatedBy}: $officer', style: const pw.TextStyle(fontSize: 9)),
        pw.Text(fmtDateTime(nowIso()), style: const pw.TextStyle(fontSize: 9)),
      ]),
      pw.Text(S.motto, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
    ]);
  }

  static Future<void> _deliver(BuildContext context, Uint8List bytes, String filename) async {
    if (Platform.isWindows) {
      await saveBytesFile(context, bytes, filename);
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  static Future<String> _school(WidgetRef ref) =>
      ref.read(databaseProvider).setting('school_name', fallback: Defaults.schoolName);

  static Future<String> _officer(WidgetRef ref) async {
    final user = ref.read(currentUserProvider);
    return user?.displayName ?? 'Officer';
  }

  static Future<void> receipt(BuildContext context, WidgetRef ref, Payment payment, Member member) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        _header(logo, S.receipt, school),
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#1B7A3D'))),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('${S.receiptNo}: ${payment.receiptNo}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Text('${S.fullName}: ${member.fullName} (${member.studentId})'),
            pw.Text('${S.form} ${member.form}'),
            pw.SizedBox(height: 8),
            pw.Text('${S.amount}: ${formatGhs(payment.amountPesewas)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('${S.paymentMethod}: ${payment.method.label}'),
            if (payment.transactionRef != null) pw.Text('${S.transactionRef}: ${payment.transactionRef}'),
            pw.Text('${S.date}: ${fmtDateTime(payment.paidAt)}'),
            pw.Text('Received by: $officer'),
          ]),
        ),
        pw.SizedBox(height: 16),
        pw.Center(
          child: pw.Column(children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: receiptQrData(payment.receiptNo, payment.amountPesewas),
              width: 90,
              height: 90,
            ),
            pw.SizedBox(height: 4),
            pw.Text('Scan in Winroc Metrics to verify', style: const pw.TextStyle(fontSize: 8)),
          ]),
        ),
        pw.Spacer(),
        _footer(officer),
      ]),
    ));
    if (context.mounted) {
      await _deliver(context, await doc.save(), 'receipt-${payment.receiptNo}.pdf');
    }
  }

  static Future<void> idCards(BuildContext context, WidgetRef ref, List<Member> members) async {
    final logo = await _logo();
    final school = await _school(ref);
    final doc = pw.Document();
    const perPage = 8;
    for (var i = 0; i < members.length; i += perPage) {
      final chunk = members.skip(i).take(perPage).toList();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final m in chunk)
              pw.Container(
                width: 240,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromHex('#1B7A3D'), width: 1.5),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Row(children: [
                    pw.Image(logo, width: 28, height: 28),
                    pw.SizedBox(width: 6),
                    pw.Expanded(child: pw.Text(school, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  ]),
                  pw.SizedBox(height: 6),
                  pw.Text(m.fullName, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${S.form} ${m.form} · ${m.studentId}', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text(S.clubName, style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#1B7A3D'))),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: memberQrData(m.id, m.qrToken),
                      width: 80,
                      height: 80,
                    ),
                  ),
                ]),
              ),
          ],
        ),
      ));
    }
    if (context.mounted) await _deliver(context, await doc.save(), 'winroc-id-cards.pdf');
  }

  static Future<void> memberReportCard(BuildContext context, WidgetRef ref, Member m) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final term = ref.read(currentTermProvider).value;
    final att = ref.read(attendanceDaoProvider);
    final fin = ref.read(financeDaoProvider);
    final club = ref.read(clubDaoProvider);
    final pct = await att.attendancePct(m.id, termId: term?.id);
    final streak = await att.streak(m.id);
    final balance = await fin.balance(m.id);
    final dues = await fin.duesWithBalances(m.id);
    final hours = await club.hoursForMember(m.id);
    final badges = await club.badgesFor(m.id);
    final allBadges = await club.allBadges();
    final skills = await ref.read(memberDaoProvider).skillsFor(m.id);
    final allSkills = await ref.read(memberDaoProvider).allSkills();
    final teams = await ref.read(memberDaoProvider).teamsFor(m.id);
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header(logo, '${S.reportCard}: ${m.fullName}', school),
        pw.SizedBox(height: 12),
        pw.Text('${S.studentId}: ${m.studentId}   ${S.form}: ${m.form}   ${S.status}: ${m.status.label}'),
        pw.Text('${S.teams}: ${teams.map((t) => t.name).join(', ')}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [S.attendancePct, S.streak, S.balance, S.hours],
          data: [
            ['${pct.toStringAsFixed(1)}%', '$streak sessions', formatGhs(balance.owing), hours.toStringAsFixed(1)],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(S.duesLedger, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Item', S.amount, S.waiver, S.paid, S.owing],
          data: [
            for (final d in dues)
              [d.label, formatGhs(d.due.amountPesewas), formatGhs(d.due.waiverPesewas), formatGhs(d.allocated), formatGhs(d.remaining)],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(S.skills, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: ['Skill', 'Level (0-5)'],
          data: [
            for (final s in allSkills) [s.name, '${skills[s.id] ?? 0}'],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('${S.badges}: ${badges.isEmpty ? '-' : badges.map((b) => allBadges.where((x) => x.id == b.badgeId).firstOrNull?.name ?? '').join(', ')}'),
        pw.SizedBox(height: 16),
        _footer(officer),
      ],
    ));
    if (context.mounted) await _deliver(context, await doc.save(), 'report-card-${m.studentId}.pdf');
  }

  static Future<void> attendanceRegister(BuildContext context, WidgetRef ref,
      {String? from, String? to}) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final db = ref.read(databaseProvider);
    var q = db.select(db.sessions)..where((s) => s.deletedAt.isNull());
    if (from != null) q = q..where((s) => s.date.isBiggerOrEqualValue(from));
    if (to != null) q = q..where((s) => s.date.isSmallerOrEqualValue(to));
    q = q..orderBy([(s) => OrderingTerm(expression: s.date)]);
    final sessions = await q.get();
    final members = await ref.read(memberDaoProvider).activeMembers();
    final att = ref.read(attendanceDaoProvider);
    final doc = pw.Document();
    for (final s in sessions) {
      final records = await att.recordsFor(s.id);
      final byMember = {for (final r in records) r.memberId: r};
      doc.addPage(pw.MultiPage(
        build: (ctx) => [
          _header(logo, '${S.attendanceRegister}: ${s.title}', school),
          pw.SizedBox(height: 8),
          pw.Text('${fmtDate(s.date)} · ${s.startTime} · ${s.type.label}'),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: [S.fullName, S.studentId, S.form, S.status, S.checkIn],
            data: [
              for (final m in members)
                [
                  m.fullName,
                  m.studentId,
                  '${m.form}',
                  byMember[m.id]?.status.label ?? '-',
                  byMember[m.id]?.checkInAt != null ? fmtTime(byMember[m.id]!.checkInAt) : '-',
                ],
            ],
          ),
          pw.SizedBox(height: 12),
          _footer(officer),
        ],
      ));
    }
    if (sessions.isEmpty) {
      doc.addPage(pw.Page(build: (ctx) => pw.Text(S.emptyList)));
    }
    if (context.mounted) await _deliver(context, await doc.save(), 'attendance-register.pdf');
  }

  static Future<void> duesLedger(BuildContext context, WidgetRef ref) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final members = await ref.read(memberDaoProvider).activeMembers();
    final fin = ref.read(financeDaoProvider);
    final rows = <List<String>>[];
    for (final m in members) {
      final b = await fin.balance(m.id);
      rows.add([m.fullName, m.studentId, formatGhs(b.netCharged), formatGhs(b.paid), formatGhs(b.owing), formatGhs(b.credit)]);
    }
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header(logo, S.duesLedger, school),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [S.fullName, S.studentId, 'Charged', S.paid, S.owing, S.credit],
          data: rows,
        ),
        pw.SizedBox(height: 12),
        _footer(officer),
      ],
    ));
    if (context.mounted) await _deliver(context, await doc.save(), 'dues-ledger.pdf');
  }

  static Future<void> defaultersList(BuildContext context, WidgetRef ref) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final defaulters = await ref.read(financeDaoProvider).defaulters();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header(logo, S.defaulters, school),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [S.fullName, S.studentId, S.form, S.owing, S.guardianContact],
          data: [
            for (final d in defaulters)
              [d.member.fullName, d.member.studentId, '${d.member.form}', formatGhs(d.owing), d.member.guardianContact ?? '-'],
          ],
        ),
        pw.SizedBox(height: 12),
        _footer(officer),
      ],
    ));
    if (context.mounted) await _deliver(context, await doc.save(), 'defaulters.pdf');
  }

  static Future<void> financialStatement(BuildContext context, WidgetRef ref, {String? termId}) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final fin = ref.read(financeDaoProvider);
    final db = ref.read(databaseProvider);
    final term = termId != null
        ? await (db.select(db.terms)..where((t) => t.id.equals(termId))).getSingleOrNull()
        : ref.read(currentTermProvider).value;
    final totals = term == null ? (income: 0, expenses: 0, net: 0) : await fin.termTotals(term.id);
    final payments = await fin.watchPayments(termId: term?.id).first;
    final expenses = await fin.watchExpenses().first;
    final categories = await fin.categories(CategoryKind.expense);
    final memberDao = ref.read(memberDaoProvider);
    final names = <String, String>{};
    for (final pmt in payments) {
      names[pmt.memberId] = (await memberDao.get(pmt.memberId))?.fullName ?? '-';
    }
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header(logo, '${S.financialStatement}${term != null ? ' — Term ${term.number}' : ''}', school),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: [S.income, S.expenses, S.netBalance],
          data: [
            [formatGhs(totals.income), formatGhs(totals.expenses), formatGhs(totals.net)],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(S.income, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: [S.date, S.receiptNo, S.fullName, S.amount, S.paymentMethod],
          data: [
            for (final pmt in payments)
              [
                fmtDateShort(pmt.paidAt),
                pmt.receiptNo,
                names[pmt.memberId] ?? '-',
                formatGhs(pmt.amountPesewas),
                pmt.method.label,
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(S.expenses, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: [S.date, S.description, S.expenseCategory, S.amount],
          data: [
            for (final e in expenses)
              [
                fmtDateShort(e.spentAt),
                e.description,
                categories.where((c) => c.id == e.categoryId).firstOrNull?.name ?? '-',
                formatGhs(e.amountPesewas),
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        _footer(officer),
      ],
    ));
    if (context.mounted) await _deliver(context, await doc.save(), 'financial-statement.pdf');
  }

  static Future<void> termReport(BuildContext context, WidgetRef ref) async {
    final logo = await _logo();
    final school = await _school(ref);
    final officer = await _officer(ref);
    final term = ref.read(currentTermProvider).value;
    final att = ref.read(attendanceDaoProvider);
    final fin = ref.read(financeDaoProvider);
    final members = await ref.read(memberDaoProvider).activeMembers();
    final threshold = double.tryParse(await ref.read(databaseProvider).setting('attendance_threshold', fallback: '75')) ?? 75;
    final atRisk = term == null ? <({Member member, double pct})>[] : await att.atRisk(threshold, term.id);
    final byTeam = term == null ? <({String teamName, double pct})>[] : await att.attendanceByTeam(term.id);
    final totals = term == null ? (income: 0, expenses: 0, net: 0) : await fin.termTotals(term.id);
    final rate = term == null ? 0.0 : await fin.collectionRate(term.id);
    final defaulters = await fin.defaulters();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      build: (ctx) => [
        _header(logo, '${S.termReport}${term != null ? ' — Term ${term.number}, ${term.startDate} to ${term.endDate}' : ''}', school),
        pw.SizedBox(height: 12),
        pw.Text('Prepared for the Headmaster and Patron.', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Metric', 'Value'],
          data: [
            ['Active members', '${members.length}'],
            [S.collectionRate, '${rate.toStringAsFixed(1)}%'],
            [S.income, formatGhs(totals.income)],
            [S.expenses, formatGhs(totals.expenses)],
            [S.netBalance, formatGhs(totals.net)],
            ['Defaulters', '${defaulters.length}'],
            ['At-risk members (<$threshold%)', '${atRisk.length}'],
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text('Attendance by team', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: [S.teams, S.attendancePct],
          data: [for (final t in byTeam) [t.teamName, '${t.pct.toStringAsFixed(1)}%']],
        ),
        pw.SizedBox(height: 12),
        pw.Text(S.atRisk, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.TableHelper.fromTextArray(
          headers: [S.fullName, S.form, S.attendancePct],
          data: [for (final a in atRisk) [a.member.fullName, '${a.member.form}', '${a.pct.toStringAsFixed(1)}%']],
        ),
        pw.SizedBox(height: 16),
        _footer(officer),
      ],
    ));
    if (context.mounted) await _deliver(context, await doc.save(), 'term-report.pdf');
  }
}