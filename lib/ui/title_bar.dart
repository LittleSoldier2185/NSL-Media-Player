import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import 'theme.dart';

class NslTitleBar extends StatelessWidget {
  const NslTitleBar({super.key, required this.title, this.onMenu, this.onLogo});
  final String title;

  /// The menu button: shows or hides the sidebar.
  final VoidCallback? onMenu;

  /// Clicking the logo / app name (goes to Home).
  final VoidCallback? onLogo;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: context.pal.titleBar,
      child: Row(
        children: [
          if (onMenu != null)
            Tooltip(
              message: 'Show or hide the sidebar (Ctrl+B)',
              child: _WinBtn(Icons.menu, onMenu!, width: 48, iconSize: 18),
            ),
          // Logo and name: click for Home. The rest of the bar drags the window.
          Tooltip(
            message: 'Home (H)',
            child: MouseRegion(
              cursor: onLogo == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onLogo,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(left: onMenu == null ? 14 : 4),
                  child: Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: context.pal.accent,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 14,
                          color: context.pal.onAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'NSL Media Player',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.pal.textDim),
                  ),
                ),
              ),
            ),
          ),
          _WinBtn(Icons.remove, () => windowManager.minimize()),
          _WinBtn(Icons.crop_square, () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          }),
          _WinBtn(Icons.close, () => windowManager.close(), danger: true),
        ],
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  const _WinBtn(
    this.icon,
    this.onTap, {
    this.danger = false,
    this.width = 46,
    this.iconSize = 14,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final double width;
  final double iconSize;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: 40,
          color: _hover
              ? (widget.danger ? const Color(0xFFC42B1C) : context.pal.hover)
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: context.pal.icon,
          ),
        ),
      ),
    );
  }
}
