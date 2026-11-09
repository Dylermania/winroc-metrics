import 'dart:async';

import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'data/database.dart';
import 'features/attendance/attendance_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/dues/dues_screen.dart';
import 'features/home/more_screen.dart';
import 'features/members/members_screen.dart';
import 'features/robotics/robotics_screen.dart';
import 'features/communication/reminders.dart';
import 'providers.dart';

class WinrocApp extends ConsumerWidget {
  const WinrocApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? 'system';
    return MaterialApp(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: const RootGate(),
    );
  }
}

class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUsers = ref.watch(hasUsersProvider);
    final user = ref.watch(currentUserProvider);
    final onboarded = ref.watch(onboardedProvider).value ?? '0';
    return hasUsers.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Database error: $e'))),
      data: (exists) {
        if (!exists) return const SetupScreen();
        if (user == null) return const LoginScreen();
        if (onboarded == '0') return const OnboardingScreen();
        return LockWrapper(child: HomeShell(key: ValueKey(user.id)));
      },
    );
  }
}

class LockWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const LockWrapper({super.key, required this.child});
  @override
  ConsumerState<LockWrapper> createState() => _LockWrapperState();
}

class _LockWrapperState extends ConsumerState<LockWrapper> with WidgetsBindingObserver {
  bool _locked = false;
  Timer? _timer;
  int _minutes = Defaults.autoLockMinutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(databaseProvider).setting('auto_lock_minutes',
        fallback: '${Defaults.autoLockMinutes}').then((v) {
      _minutes = int.tryParse(v) ?? Defaults.autoLockMinutes;
      _resetTimer();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _minutes > 0) {
      setState(() => _locked = true);
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    if (_minutes <= 0) return;
    _timer = Timer(Duration(minutes: _minutes), () {
      if (mounted) setState(() => _locked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    return Listener(
      onPointerDown: (_) => _resetTimer(),
      child: Stack(children: [
        widget.child,
        if (_locked && user != null)
          LockScreen(
            user: user,
            onUnlocked: () {
              setState(() => _locked = false);
              _resetTimer();
            },
          ),
      ]),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final GoRouter _router;

  static const _tabs = [
    ('/', S.home, Icons.dashboard_outlined),
    ('/members', S.members, Icons.people_outlined),
    ('/attendance', S.attendance, Icons.fact_check_outlined),
    ('/dues', S.dues, Icons.payments_outlined),
    ('/more', S.more, Icons.grid_view_outlined),
  ];

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    final isMemberOnly = user?.role == ClubRole.member;
    final tabs = isMemberOnly ? [_tabs.first, _tabs.last] : _tabs;
    _router = GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              _ShellScaffold(location: state.uri.path, tabs: tabs, child: child),
          routes: [
            GoRoute(path: '/', builder: (c, s) => const DashboardScreen()),
            if (!isMemberOnly) ...[
              GoRoute(path: '/members', builder: (c, s) => const MembersScreen()),
              GoRoute(path: '/attendance', builder: (c, s) => const SessionsScreen()),
              GoRoute(path: '/dues', builder: (c, s) => const DuesScreen()),
            ],
            GoRoute(path: '/more', builder: (c, s) => const MoreScreen()),
          ],
        ),
      ],
    );
    final db = ref.read(databaseProvider);
    NotificationService.instance.startPeriodicChecks(
        db, ref.read(attendanceDaoProvider), ref.read(financeDaoProvider));
    ref.read(adminDaoProvider).maybeAutoBackup();
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Router.withConfig(config: _router);
  }
}

class _ShellScaffold extends ConsumerWidget {
  final String location;
  final List<(String, String, IconData)> tabs;
  final Widget child;
  const _ShellScaffold(
      {required this.location, required this.tabs, required this.child});

  int get _index {
    final i = tabs.indexWhere((t) => t.$1 == location);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final user = ref.watch(currentUserProvider);
    final title = tabs[_index].$2;
    final nav = NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => GoRouter.of(context).go(tabs[i].$1),
      destinations: [
        for (final t in tabs)
          NavigationDestination(icon: Icon(t.$3), label: t.$2),
      ],
    );
    final rail = NavigationRail(
      extended: MediaQuery.of(context).size.width >= 1100,
      selectedIndex: _index,
      onDestinationSelected: (i) => GoRouter.of(context).go(tabs[i].$1),
      labelType: NavigationRailLabelType.none,
      destinations: [
        for (final t in tabs)
          NavigationRailDestination(icon: Icon(t.$3), label: Text(t.$2)),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(title == S.home ? S.appName : title),
        actions: [
          IconButton(
            tooltip: S.search,
            icon: const Icon(Icons.search),
            onPressed: () => showGlobalSearch(context, ref),
          ),
          PopupMenuButton<String>(
            tooltip: user?.displayName ?? '',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) {
              if (v == 'out') {
                ref.read(currentUserProvider.notifier).state = null;
                ref.read(databaseProvider).currentUserId = '';
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(user?.displayName ?? '')),
              const PopupMenuItem(value: 'out', child: Text(S.signOut)),
            ],
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              rail,
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ])
          : child,
      bottomNavigationBar: wide ? null : nav,
    );
  }
}

Future<void> showGlobalSearch(BuildContext context, WidgetRef ref) async {
  await showDialog(
    context: context,
    builder: (ctx) => const _GlobalSearchDialog(),
  );
}

class _GlobalSearchDialog extends ConsumerStatefulWidget {
  const _GlobalSearchDialog();
  @override
  ConsumerState<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends ConsumerState<_GlobalSearchDialog> {
  List<Member> _members = [];
  List<Session> _sessions = [];
  List<Project> _projects = [];

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _members = [];
        _sessions = [];
        _projects = [];
      });
      return;
    }
    final db = ref.read(databaseProvider);
    final like = '%${q.trim()}%';
    final members = await (db.select(db.members)
          ..where((m) => m.deletedAt.isNull() & m.fullName.like(like))
          ..limit(8))
        .get();
    final sessions = await (db.select(db.sessions)
          ..where((s) => s.deletedAt.isNull() & s.title.like(like))
          ..limit(5))
        .get();
    final projects = await (db.select(db.projects)
          ..where((p) => p.deletedAt.isNull() & p.name.like(like))
          ..limit(5))
        .get();
    if (mounted) {
      setState(() {
        _members = members;
        _sessions = sessions;
        _projects = projects;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final empty = _members.isEmpty && _sessions.isEmpty && _projects.isEmpty;
    return AlertDialog(
      title: TextField(
        autofocus: true,
        decoration: const InputDecoration(hintText: S.search, prefixIcon: Icon(Icons.search)),
        onChanged: _search,
      ),
      content: SizedBox(
        width: 440,
        height: 360,
        child: empty
            ? const Center(child: Text(S.noResults))
            : ListView(children: [
                for (final m in _members)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(m.fullName),
                    subtitle: Text('${S.form} ${m.form} · ${m.studentId}'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                          builder: (_) => MemberDetailScreen(memberId: m.id)));
                    },
                  ),
                for (final s in _sessions)
                  ListTile(
                    leading: const Icon(Icons.event_outlined),
                    title: Text(s.title),
                    subtitle: Text(s.date),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                          builder: (_) => SessionScreen(sessionId: s.id)));
                    },
                  ),
                for (final p in _projects)
                  ListTile(
                    leading: const Icon(Icons.precision_manufacturing_outlined),
                    title: Text(p.name),
                    subtitle: Text(p.status.label),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                          builder: (_) => ProjectDetailScreen(projectId: p.id)));
                    },
                  ),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text(S.close)),
      ],
    );
  }
}