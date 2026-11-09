import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/security.dart';
import '../../core/strings.dart';
import '../../data/database.dart';
import '../../providers.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _name = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = S.required);
      return;
    }
    if (_pin.text.length < 4 || _pin.text.length > 6) {
      setState(() => _error = S.pinTooShort);
      return;
    }
    if (_pin.text != _confirm.text) {
      setState(() => _error = S.pinsDoNotMatch);
      return;
    }
    setState(() => _busy = true);
    final admin = ref.read(adminDaoProvider);
    final user = await admin.createUser(
        displayName: _name.text.trim(), role: ClubRole.admin, pin: _pin.text);
    ref.read(databaseProvider).currentUserId = user.id;
    ref.read(currentUserProvider.notifier).state = user;
    ref.invalidate(hasUsersProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Image.asset('assets/branding/logo.jpg', height: 110),
              const SizedBox(height: 16),
              Text(S.welcome,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(S.setupIntro, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: S.yourName)),
              const SizedBox(height: 16),
              TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: S.createPin)),
              const SizedBox(height: 8),
              TextField(
                  controller: _confirm,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: S.confirmPin)),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _busy ? null : _submit, child: const Text(S.finishSetup)),
            ]),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _pin = TextEditingController();
  User? _selected;
  String? _error;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    Biometrics.available().then((v) {
      if (mounted) setState(() => _biometricAvailable = v);
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final user = _selected;
    if (user == null) return;
    final result = await ref.read(adminDaoProvider).authenticate(user.id, _pin.text);
    if (!mounted) return;
    if (result.user != null) {
      _pin.clear();
      setState(() => _error = null);
      ref.read(currentUserProvider.notifier).state = result.user;
    } else {
      setState(() => _error = result.error == 'locked' ? S.lockedOut : S.wrongPin);
    }
  }

  Future<void> _biometric(User user) async {
    final ok = await Biometrics.authenticate(S.unlock);
    if (!ok || !mounted) return;
    ref.read(databaseProvider).currentUserId = user.id;
    ref.read(currentUserProvider.notifier).state = user;
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminDaoProvider).watchUsers();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: StreamBuilder<List<User>>(
              stream: users,
              builder: (context, snap) {
                final list = snap.data ?? [];
                if (list.isNotEmpty && _selected == null) {
                  _selected = list.first;
                }
                final selected = _selected;
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Image.asset('assets/branding/logo.jpg', height: 110),
                  const SizedBox(height: 12),
                  Text(S.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 24),
                  if (list.isNotEmpty)
                    DropdownButtonFormField<User>(
                      initialValue: selected,
                      decoration: const InputDecoration(labelText: S.login),
                      items: list
                          .map((u) => DropdownMenuItem(
                              value: u,
                              child: Text('${u.displayName} (${u.role.label})')))
                          .toList(),
                      onChanged: (u) => setState(() => _selected = u),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: S.enterPin),
                    onSubmitted: (_) => _login(),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  FilledButton(onPressed: _login, child: const Text(S.login)),
                  if (_biometricAvailable &&
                      selected != null &&
                      selected.biometricEnabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _biometric(selected),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text(S.useBiometrics),
                    ),
                  ],
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  final User user;
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.user, required this.onUnlocked});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final result =
        await ref.read(adminDaoProvider).authenticate(widget.user.id, _pin.text);
    if (!mounted) return;
    if (result.user != null) {
      widget.onUnlocked();
    } else {
      setState(() => _error = result.error == 'locked' ? S.lockedOut : S.wrongPin);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 12),
              Text(S.sessionLocked,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(widget.user.displayName, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: _pin,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: S.enterPin),
                onSubmitted: (_) => _unlock(),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              FilledButton(onPressed: _unlock, child: const Text(S.unlock)),
              if (widget.user.biometricEnabled) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await Biometrics.authenticate(S.unlock);
                    if (ok && mounted) widget.onUnlocked();
                  },
                  icon: const Icon(Icons.fingerprint),
                  label: const Text(S.useBiometrics),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 0;
  final _pages = const [
    (Icons.fact_check_outlined, S.onboarding1),
    (Icons.payments_outlined, S.onboarding2),
    (Icons.lock_outlined, S.onboarding3),
  ];

  @override
  Widget build(BuildContext context) {
    final (icon, text) = _pages[_page];
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(S.onboardingTitle, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 32),
              Icon(icon, size: 88, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 24),
              Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _pages.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ]),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () async {
                  if (_page < _pages.length - 1) {
                    setState(() => _page++);
                  } else {
                    await ref.read(databaseProvider).setSetting('onboarded', '1');
                  }
                },
                child: Text(_page < _pages.length - 1 ? S.next : S.getStarted),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}