import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/strings.dart';
import '../core/utils.dart';
import '../data/database.dart';

class MemberAvatar extends StatelessWidget {
  final Member member;
  final double radius;
  const MemberAvatar(this.member, {super.key, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final photo = member.photoPath;
    if (photo != null && File(photo).existsSync()) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(File(photo)));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(initials(member.fullName),
          style: TextStyle(
              fontSize: radius * 0.7,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer)),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const StatCard(this.label, this.value, this.icon, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color ?? scheme.primary, size: 28),
          const SizedBox(height: 10),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold))),
        if (action != null) action!,
      ]),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const StatusChip(this.label, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text(S.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: const Text(S.confirm)),
      ],
    ),
  );
  return result ?? false;
}

void showUndo(BuildContext context, String message, VoidCallback onUndo) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    action: SnackBarAction(label: S.undo, onPressed: onUndo),
    duration: const Duration(seconds: 6),
  ));
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> pickDate(BuildContext context, {String? initial}) async {
  final now = DateTime.now();
  final first = DateTime(now.year - 3);
  final last = DateTime(now.year + 3);
  DateTime init = now;
  if (initial != null) init = DateTime.tryParse(initial) ?? now;
  if (init.isBefore(first)) init = first;
  if (init.isAfter(last)) init = last;
  final picked = await showDatePicker(
      context: context, initialDate: init, firstDate: first, lastDate: last);
  return picked == null ? null : dateOnly(picked);
}

Future<String?> pickTime(BuildContext context, {String? initial}) async {
  TimeOfDay init = TimeOfDay.now();
  if (initial != null && initial.contains(':')) {
    final parts = initial.split(':');
    init = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 12, minute: int.tryParse(parts[1]) ?? 0);
  }
  final picked = await showTimePicker(context: context, initialTime: init);
  if (picked == null) return null;
  return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
}

Future<String?> pickPhoto(BuildContext context) async {
  final picker = ImagePicker();
  final source = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text(S.takePhoto),
            onTap: () => Navigator.pop(ctx, 'camera')),
        ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text(S.pickPhoto),
            onTap: () => Navigator.pop(ctx, 'gallery')),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final shot = await picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 80);
    if (shot == null) return null;
    final dir = await getApplicationSupportDirectory();
    final photos = Directory(p.join(dir.path, 'photos'));
    await photos.create(recursive: true);
    final dest = p.join(photos.path, '${newId()}.jpg');
    await File(shot.path).copy(dest);
    return dest;
  } catch (_) {
    return null;
  }
}

class MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const MoneyField(this.controller, {super.key, this.label = S.amount});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(labelText: label, prefixText: '${Defaults.currency} '),
    );
  }
}

String fmtTimeOfDay(String hhmm) {
  final parts = hhmm.split(':');
  final t = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  final now = DateTime.now();
  return DateFormat('h:mm a').format(DateTime(now.year, now.month, now.day, t.hour, t.minute));
}

bool isDesktop(BuildContext context) =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> saveBytesFile(BuildContext context, List<int> bytes, String filename) async {
  if (Platform.isWindows) {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'WinrocExports'));
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes);
    if (context.mounted) showSnack(context, 'Saved: ${file.path}');
  }
}