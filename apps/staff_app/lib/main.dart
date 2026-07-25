import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/clone_pos_theme.dart';
import 'screens/master_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
}

class CloneposStaffApp extends StatelessWidget {
  const CloneposStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clone-POS Staff',
      debugShowCheckedModeBanner: false,
      theme: ClonePosTheme.staffAppTheme,
      // Prototype note: this always launches straight into the Master
      // dashboard. The real build needs a pairing/role-selection flow
      // first (Set up as Master / Pair to existing Master as Satellite)
      // per the roadmap doc, Phase 3.
      home: const MasterDashboardScreen(),
    );
  }
}
