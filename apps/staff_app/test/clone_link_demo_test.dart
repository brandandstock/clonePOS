// Tests for the master↔satellite control plane ([CloneLinkService]).
//
// Two kinds of test live here:
//
//  1. DEMO-MODE tests (run by default) — exercise the in-app "simulate a
//     satellite" path that lights the master's LINKED pill without a second
//     device. Deterministic, no networking.
//
//  2. REAL round-trip tests (skipped) — drive the actual UDP handshake with a
//     master + clone. These are skipped because both endpoints bind the SAME
//     port (47772), and a single host cannot faithfully shuttle the
//     broadcast-login + unicast-grant exchange between two sockets on one
//     port. They pass on two real devices sharing a WiFi. Remove the `skip:`
//     to run them against a second endpoint.
//
// Run:  flutter test test/clone_link_demo_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';

import 'package:clone_pos_staff_app/comm/clone_link_service.dart';

const _biz = 'BIZ-DEMO7';
const _cloneId = 'CLN-9F3K';
const _grant =
    LinkGrant('Mia', 'Front Desk', ['Carts', 'Inventory', 'Analytics']);

/// Poll [cond] until true or [timeout] elapses (real wall-clock time).
Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 6),
  required String reason,
}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) fail('Timed out waiting for: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('demo mode (no second device)', () {
    test('simulating a sign-in lists the clone as online', () {
      final master = CloneLinkService();
      final seen = <Set<String>>[];
      master.onlineClones.addListener(() => seen.add(master.onlineClones.value));

      expect(master.demoActive, isFalse);
      master.setDemoLinked(_cloneId, true);

      expect(master.isDemoLinked(_cloneId), isTrue);
      expect(master.demoActive, isTrue);
      expect(master.onlineClones.value, contains(_cloneId));
      print('DEMO  linked $_cloneId → onlineClones=${master.onlineClones.value}');

      master.setDemoLinked(_cloneId, false);
      expect(master.onlineClones.value, isEmpty);
      print('DEMO  unlinked $_cloneId → onlineClones=${master.onlineClones.value}');

      // Notifier fired for each state change (drives the LINKED pill live).
      expect(seen.length, greaterThanOrEqualTo(2));
      master.dispose();
    });

    test('clearDemo drops every simulated link', () {
      final master = CloneLinkService();
      master.setDemoLinked('CLN-9F3K', true);
      master.setDemoLinked('CLN-2B8T', true);
      expect(master.onlineClones.value, hasLength(2));

      master.clearDemo();
      expect(master.onlineClones.value, isEmpty);
      expect(master.demoActive, isFalse);
      master.dispose();
    });

    test('empty Clone ID is ignored', () {
      final master = CloneLinkService();
      master.setDemoLinked('', true);
      expect(master.onlineClones.value, isEmpty);
      master.dispose();
    });

    test('onCall starts false; dialling an unlinked clone is a safe no-op', () {
      final clone = CloneLinkService();
      expect(clone.onCall.value, isFalse);
      clone.dispose();

      // Master with no live clones: callClone must not throw and changes
      // nothing (you can only dial a device that is actually linked).
      final master = CloneLinkService();
      expect(() => master.callClone('CLN-9F3K', true), returnsNormally);
      expect(master.onlineClones.value, isEmpty);
      master.dispose();
    });
  });

  group('real LAN round-trip (needs two hosts)', () {
    test('a clone pairs with the master and receives its grant', () async {
      final master = CloneLinkService();
      final clone = CloneLinkService();
      await master.startMaster(
        businessId: _biz,
        resolve: (biz, id) => (biz == _biz && id == _cloneId) ? _grant : null,
      );
      await clone.startClone(businessId: _biz, cloneId: _cloneId);

      await _waitFor(
        () => clone.linkState.value == CloneLinkState.connected,
        reason: 'clone reaches connected',
      );
      expect(clone.grant.value?.features, _grant.features);
      await _waitFor(
        () => master.onlineClones.value.contains(_cloneId),
        reason: 'master lists the clone online',
      );

      // CALL → the clone shows an active call; CUT → it clears.
      master.callClone(_cloneId, true);
      await _waitFor(() => clone.onCall.value, reason: 'clone rings on CALL');
      master.callClone(_cloneId, false);
      await _waitFor(() => !clone.onCall.value, reason: 'clone clears on CUT');

      await clone.stop();
      await master.stop();
      clone.dispose();
      master.dispose();
    }, skip: 'Requires a second host; one machine shares UDP :47772.');
  });
}
