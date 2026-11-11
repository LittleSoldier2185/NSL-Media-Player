import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nsl_media_player/ui/sidebar.dart';
import 'package:nsl_media_player/ui/theme.dart';

void main() {
  Widget host({
    required SidebarMode mode,
    NavDest current = NavDest.player,
    ValueChanged<NavDest>? onSelect,
    VoidCallback? onToggle,
    Brightness brightness = Brightness.dark,
  }) => MaterialApp(
    theme: buildTheme(brightness, const Color(0xFFF2B155)),
    home: Scaffold(
      body: Row(
        children: [
          AppSidebar(
            mode: mode,
            current: current,
            onSelect: onSelect ?? (_) {},
            onToggleWide: onToggle ?? () {},
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    ),
  );

  testWidgets('open: shows every name', (tester) async {
    await tester.pumpWidget(host(mode: SidebarMode.open));
    await tester.pumpAndSettle();
    for (final label in [
      'Home',
      'Library',
      'Playlists',
      'History',
      'Player',
      'Settings',
      'Collapse',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(tester.getSize(find.byType(AppSidebar)).width, 208);
  });

  testWidgets('rail: icons only, narrower', (tester) async {
    await tester.pumpWidget(host(mode: SidebarMode.rail));
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsNothing);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(tester.getSize(find.byType(AppSidebar)).width, 64);
  });

  testWidgets('hidden: takes no room', (tester) async {
    await tester.pumpWidget(host(mode: SidebarMode.hidden));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AppSidebar)).width, 0);
  });

  testWidgets('animating between modes does not overflow', (tester) async {
    await tester.pumpWidget(host(mode: SidebarMode.open));
    for (final m in [
      SidebarMode.rail,
      SidebarMode.hidden,
      SidebarMode.open,
      SidebarMode.hidden,
      SidebarMode.rail,
    ]) {
      await tester.pumpWidget(host(mode: m));
      await tester.pump(const Duration(milliseconds: 60)); // mid-animation
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('works in the light theme too', (tester) async {
    await tester.pumpWidget(
      host(mode: SidebarMode.open, brightness: Brightness.light),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping an item reports where to go', (tester) async {
    final picked = <NavDest>[];
    await tester.pumpWidget(host(mode: SidebarMode.open, onSelect: picked.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.tap(find.text('Library'));
    await tester.tap(find.text('Playlists'));
    await tester.tap(find.text('History'));
    await tester.tap(find.text('Player'));
    await tester.tap(find.text('Settings'));
    expect(picked, [
      NavDest.home,
      NavDest.library,
      NavDest.playlists,
      NavDest.history,
      NavDest.player,
      NavDest.settings,
    ]);
  });

  testWidgets('the collapse button asks to toggle', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      host(mode: SidebarMode.open, onToggle: () => toggled++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Collapse'));
    expect(toggled, 1);
  });

  testWidgets('in the rail the same buttons still work', (tester) async {
    final picked = <NavDest>[];
    await tester.pumpWidget(host(mode: SidebarMode.rail, onSelect: picked.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.queue_music_outlined));
    expect(picked, [NavDest.playlists]);
  });

  test('stored mode names round-trip, unknown falls back to open', () {
    for (final m in SidebarMode.values) {
      expect(SidebarMode.parse(m.name), m);
    }
    expect(SidebarMode.parse('nonsense'), SidebarMode.open);
  });
}
