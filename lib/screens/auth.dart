import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';
import '../services/habit_backend.dart';
import '../services/notifications.dart';
import '../widgets/common.dart';
import '../widgets/brand.dart';
import '../widgets/firebase_connection_banner.dart';
import '../widgets/loading_indicator.dart';
import '../widgets/motion_switcher.dart';
import '../main.dart';
import 'user_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _lastUid = FirebaseAuth.instance.currentUser?.uid;
  late final _auth = FirebaseAuth.instance.authStateChanges().map((user) {
    if (user?.uid != _lastUid) {
      _lastUid = user?.uid;
      firebaseAvailability.reset();
    }
    return user;
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _auth,
    builder: (context, auth) {
      final user = auth.connectionState == ConnectionState.waiting
          ? FirebaseAuth.instance.currentUser
          : auth.data;
      return MotionSwitcher(
        child: user == null
            ? const LoginScreen()
            : _AccountGate(key: ValueKey(user.uid), user: user),
      );
    },
  );
}

class _AccountGate extends StatefulWidget {
  const _AccountGate({super.key, required this.user});
  final User user;

  @override
  State<_AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<_AccountGate> {
  late final _profile = HabitBackend.instance
      .profile(widget.user.uid)
      .transform(
        StreamTransformer<
          DocumentSnapshot<Map<String, dynamic>>,
          DocumentSnapshot<Map<String, dynamic>>
        >.fromHandlers(
          handleData: (snapshot, sink) {
            if (FirebaseAuth.instance.currentUser?.uid == widget.user.uid) {
              firebaseAvailability.observeSnapshot(
                fromCache: snapshot.metadata.isFromCache,
              );
            }
            sink.add(snapshot);
          },
          handleError: (error, stack, sink) {
            if (FirebaseAuth.instance.currentUser?.uid == widget.user.uid) {
              firebaseAvailability.reportUnavailable();
            }
            sink.addError(error, stack);
          },
        ),
      );
  late Future<IdTokenResult> _token = _verifySession();

  Future<IdTokenResult> _verifySession() async {
    try {
      return await widget.user.getIdTokenResult(true);
    } catch (error) {
      if (mounted &&
          FirebaseAuth.instance.currentUser?.uid == widget.user.uid) {
        firebaseAvailability.observeAuthError(error);
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _profile,
        builder: (context, snapshot) => FutureBuilder<IdTokenResult>(
          future: _token,
          builder: (context, token) =>
              MotionSwitcher(child: _screen(snapshot, token)),
        ),
      );

  Widget _screen(
    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
    AsyncSnapshot<IdTokenResult> token,
  ) {
    if (snapshot.hasError) {
      return Scaffold(
        key: const ValueKey('profile-error'),
        body: Center(child: Text('Profile error: ${snapshot.error}')),
      );
    }
    if (snapshot.hasData) {
      final data = snapshot.data!.data();
      if (data == null) {
        return const Scaffold(
          key: ValueKey('unprovisioned'),
          body: Center(
            child: Text(
              'Account profile not provisioned. Contact the administrator.',
            ),
          ),
        );
      }
      if (data['disabled'] == true) {
        return Scaffold(
          key: const ValueKey('disabled'),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Your account is disabled.'),
                TextButton(
                  onPressed: () async => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        );
      }
      if (data['role'] == 'admin' || token.data?.claims?['admin'] == true) {
        return const _AdminWebOnly();
      }
      if (token.hasData) {
        return SignedInShell(
          key: ValueKey(widget.user.uid),
          uid: widget.user.uid,
          displayName: data['displayName'] as String? ?? 'Friend',
        );
      }
      if (token.hasError) {
        return Scaffold(
          key: const ValueKey('session-error'),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to verify your session.'),
                TextButton(
                  onPressed: () => setState(() {
                    _token = _verifySession();
                  }),
                  child: const Text('Try again'),
                ),
                TextButton(
                  onPressed: () async => FirebaseAuth.instance.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        );
      }
    }
    return const Scaffold(
      key: ValueKey('verifying-session'),
      body: SafeArea(
        child: Stack(
          children: [
            BrandHeader(),
            Center(child: HabitLoadingIndicator(label: 'Verifying session')),
          ],
        ),
      ),
    );
  }
}

class SignedInShell extends StatefulWidget {
  const SignedInShell({
    super.key,
    required this.uid,
    required this.displayName,
  });
  final String uid, displayName;
  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settings;
  @override
  void initState() {
    super.initState();
    unawaited(_startDeviceServices());
    _settings = HabitBackend.instance.preferences(widget.uid).listen((d) {
      final isDark = d.data()?['darkMode'] == true;
      themeMode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  Future<void> _startDeviceServices() async {
    try {
      final zone = await NotificationService.instance.deviceTimezone();
      await HabitBackend.instance.setPreference(widget.uid, {'timezone': zone});
      await NotificationService.instance.attachUser(widget.uid);
    } catch (_) {
      /* App stays functional if notification permission is denied. */
    }
  }

  @override
  void dispose() {
    _settings?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UserShell(uid: widget.uid, displayName: widget.displayName);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final id = TextEditingController();
  final password = TextEditingController();
  bool hidden = true, busy = false;
  @override
  void dispose() {
    id.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() => busy = true);
    try {
      await HabitBackend.instance.login(
        username: id.text,
        password: password.text,
      );
      final token = await FirebaseAuth.instance.currentUser!.getIdTokenResult(
        true,
      );
      if (token.claims?['admin'] == true) {
        await FirebaseAuth.instance.signOut();
        throw StateError('Admin accounts use the separate web dashboard.');
      }
    } catch (e) {
      if (mounted) {
        firebaseAvailability.observeAuthError(e);
        toast(context, friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                MediaQuery.sizeOf(context).height -
                MediaQuery.paddingOf(context).top,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 35),
                Container(
                  alignment: Alignment.center,
                  height: 165,
                  child: const BrandMark(size: 132),
                ),
                const SizedBox(height: 26),
                Text(
                  'Welcome back!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Log in to continue your habit journey.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppPalette.muted),
                ),
                const SizedBox(height: 34),
                Form(
                  key: form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: id,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          hintText: 'User ID',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Enter your user ID'
                            : null,
                      ),
                      const SizedBox(height: 13),
                      TextFormField(
                        controller: password,
                        obscureText: hidden,
                        onFieldSubmitted: (_) => login(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          hintText: 'Password',
                          suffixIcon: IconButton(
                            tooltip: hidden ? 'Show password' : 'Hide password',
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => hidden = !hidden),
                          ),
                        ),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter password' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                PrimaryButton(
                  label: 'Login',
                  onPressed: login,
                  busy: busy,
                  icon: Icons.arrow_forward_rounded,
                  color: AppPalette.green,
                ),
                const SizedBox(height: 26),
                const SizedBox(height: 15),
                const Text(
                  'Your administrator provides your account ID and password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppPalette.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AdminWebOnly extends StatelessWidget {
  const _AdminWebOnly();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.laptop_mac_rounded,
                color: AppPalette.green,
                size: 68,
              ),
              const SizedBox(height: 22),
              const Text(
                'Admin access is on the web',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              const Text(
                'Use the separate HabitLoop admin website to manage users and tasks.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
