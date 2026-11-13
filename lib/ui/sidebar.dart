import 'package:flutter/material.dart';

import 'theme.dart';

/// Where the sidebar can take you.
enum NavDest {
  home,
  library,
  photos,
  books,
  playlists,
  history,
  player,
  private,
  settings,
}

/// How much of the sidebar is shown.
enum SidebarMode {
  /// Icons and names.
  open,

  /// Icons only.
  rail,

  /// Not shown (the menu button in the title bar brings it back).
  hidden;

  static SidebarMode parse(String s) => SidebarMode.values.firstWhere(
    (m) => m.name == s,
    orElse: () => SidebarMode.open,
  );

  double get width => switch (this) {
    SidebarMode.open => 208,
    SidebarMode.rail => 64,
    SidebarMode.hidden => 0,
  };
}

/// Left navigation: Home, Library, Photos, Books, Playlists, History, Player and Settings, shown on
/// every page so any of them is one click away. Can be collapsed to icons or
/// hidden.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.mode,
    required this.current,
    required this.onSelect,
    required this.onToggleWide,
    this.showPrivate = false,
  });

  final SidebarMode mode;
  final NavDest current;
  final ValueChanged<NavDest> onSelect;

  /// Switches between [SidebarMode.open] and [SidebarMode.rail].
  final VoidCallback onToggleWide;

  /// Show the Private entry (it can be hidden, then only its shortcut opens it).
  final bool showPrivate;

  static const _items = [
    (NavDest.home, Icons.home_outlined, 'Home', 'Home (H)'),
    (NavDest.library, Icons.folder_outlined, 'Library', 'Library'),
    (NavDest.photos, Icons.photo_library_outlined, 'Photos', 'Photos'),
    (NavDest.books, Icons.menu_book_outlined, 'Books', 'Books'),
    (NavDest.playlists, Icons.queue_music_outlined, 'Playlists', 'Playlists'),
    (NavDest.history, Icons.history, 'History', 'History'),
    (NavDest.player, Icons.play_circle_outline, 'Player', 'Player'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final wide = mode == SidebarMode.open;
    final target = mode.width;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: target,
      decoration: BoxDecoration(
        color: p.titleBar,
        border: Border(
          right: BorderSide(
            color: p.panelBorder,
            width: mode == SidebarMode.hidden ? 0 : 1,
          ),
        ),
      ),
      // Lay the content out at its final width and clip it while the width
      // animates, so the items do not squash on the way.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          maxWidth: mode == SidebarMode.hidden
              ? SidebarMode.rail.width
              : target,
          child: SizedBox(
            width: mode == SidebarMode.hidden ? SidebarMode.rail.width : target,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 10 : 8,
                vertical: 10,
              ),
              child: ExcludeFocus(
                excluding: mode == SidebarMode.hidden,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (dest, icon, label, tip) in _items)
                      _NavItem(
                        icon: icon,
                        label: label,
                        tooltip: tip,
                        wide: wide,
                        selected: current == dest,
                        onTap: () => onSelect(dest),
                      ),
                    if (showPrivate)
                      _NavItem(
                        icon: Icons.lock_outline,
                        label: 'Private',
                        tooltip: 'Private',
                        wide: wide,
                        selected: current == NavDest.private,
                        onTap: () => onSelect(NavDest.private),
                      ),
                    const Spacer(),
                    Divider(height: 13, color: p.panelBorder),
                    _NavItem(
                      icon: Icons.tune,
                      label: 'Settings',
                      tooltip: 'Settings',
                      wide: wide,
                      selected: current == NavDest.settings,
                      onTap: () => onSelect(NavDest.settings),
                    ),
                    _NavItem(
                      icon: wide
                          ? Icons.keyboard_double_arrow_left
                          : Icons.keyboard_double_arrow_right,
                      label: wide ? 'Collapse' : 'Expand',
                      tooltip: wide ? 'Collapse to icons' : 'Expand',
                      wide: wide,
                      selected: false,
                      onTap: onToggleWide,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.wide,
    required this.selected,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool wide;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = selected ? p.accentInk : p.icon;
    final item = Material(
      color: selected ? p.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 0),
          alignment: wide ? Alignment.centerLeft : Alignment.center,
          child: Row(
            mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              if (wide) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: selected ? p.text : p.icon,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // Names are hidden when collapsed, so say what each icon is.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: Semantics(label: label, button: true, child: item),
      ),
    );
  }
}
