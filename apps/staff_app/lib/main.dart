import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'data/role_store.dart';
import 'theme/clone_pos_theme.dart';
import 'screens/master_dashboard_screen.dart';
import 'screens/role_chooser_screen.dart';
import 'screens/satellite_view_screen.dart';

Future<void> main() async {
  // Kiosk-grade resilience: a single widget error must never take the whole
  // POS down or flash a red error screen in front of staff/customers. Any
  // build error renders a neutral dark surface (self-contained, so it can't
  // itself throw), and uncaught async errors are logged, not fatal. Errors are
  // still printed to logcat for diagnosis.
  ErrorWidget.builder = (_) => const ColoredBox(color: Color(0xFF1A1A1A));
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) => FlutterError.presentError(details);
    // Master runs landscape-only, per spec Section 5.1. The Master canvas is
    // 1280x800 kiosk-mode; portrait is never a valid orientation for it.
    // Satellite/Clone-POS client apps will override this once split off.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Kiosk/dedicated-device mode — no system chrome (spec Section 5.1).
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    runApp(const CloneposStaffApp());
  }, (error, stack) {
    debugPrint('Uncaught (guarded): $error\n$stack');
  });
}

class CloneposStaffApp extends StatelessWidget {
  const CloneposStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clone-POS Staff',
      debugShowCheckedModeBanner: false,
      theme: ClonePosTheme.staffAppTheme,
      home: const _RoleGate(),
    );
  }
}

/// Routes the app by this device's persisted role: the role chooser on first
/// launch, then the Master dashboard or the Satellite (Clone) view. Sign-out
/// clears the role and returns to the chooser.
class _RoleGate extends StatefulWidget {
  const _RoleGate();

  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  final RoleStore _store = RoleStore();
  RoleConfig? _config; // null while loading

  @override
  void initState() {
    super.initState();
    _store.load().then((c) {
      if (mounted) setState(() => _config = c);
    });
  }

  Future<void> _becomeMaster() async {
    await _store.saveMaster();
    if (mounted) setState(() => _config = const RoleConfig(DeviceRole.master));
  }

  Future<void> _becomeClone(String biz, String clone) async {
    await _store.saveClone(biz, clone);
    if (mounted) {
      setState(() => _config =
          RoleConfig(DeviceRole.clone, businessId: biz, cloneId: clone));
    }
  }

  Future<void> _signOut() async {
    await _store.clear();
    if (mounted) setState(() => _config = RoleConfig.unset);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    if (config == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A1A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE87722)),
        ),
      );
    }
    switch (config.role) {
      case DeviceRole.master:
        return MasterDashboardScreen(onSignOut: _signOut);
      case DeviceRole.clone:
        return SatelliteViewScreen(
          businessId: config.businessId,
          cloneId: config.cloneId,
          onSignOut: _signOut,
        );
      case DeviceRole.unset:
        return RoleChooserScreen(
          onMaster: _becomeMaster,
          onClone: _becomeClone,
        );
    }
  }
}
