import 'package:flutter/material.dart';
import 'package:window_manager/legacy.dart';

import 'theme.dart';

class NslTitleBar extends StatelessWidget {
  const NslTitleBar({super.key, required this.title, this.onHome});
  final String title;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: context.pal.titleBar,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.pal.textDim,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onHome != null) _WinBtn(Icons.home_outlined, onHome!),
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
  const _WinBtn(this.icon, this.onTap, {this.danger = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

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
          width: 46,
          height: 40,
          color: _hover
              ? (widget.danger ? const Color(0xFFC42B1C) : context.pal.hover)
              : Colors.transparent,
          child: Icon(widget.icon, size: 14, color: context.pal.icon),
        ),
      ),
    );
  }
}
