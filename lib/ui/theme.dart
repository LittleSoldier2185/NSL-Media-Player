import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colors that depend on theme mode and accent. Values follow the UI design.
@immutable
class NslPalette extends ThemeExtension<NslPalette> {
  const NslPalette({
    required this.bg,
    required this.titleBar,
    required this.panelTop,
    required this.panelBottom,
    required this.panelBorder,
    required this.text,
    required this.icon,
    required this.textDim,
    required this.track,
    required this.border,
    required this.hover,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
  });

  final Color bg, titleBar, panelTop, panelBottom, panelBorder;
  final Color text, icon, textDim, track, border, hover;

  /// The raw accent (fills, glows).
  final Color accent;

  /// Accent adjusted to read as text on a panel (>= 4.5:1).
  final Color accentInk;

  /// Foreground on top of an accent fill.
  final Color onAccent;

  static NslPalette of(Brightness b, Color accent) {
    final light = b == Brightness.light;
    final surface = light ? Colors.white : const Color(0xFF14151A);
    return NslPalette(
      bg: light ? const Color(0xFFF1F2F6) : const Color(0xFF0C0D10),
      titleBar: light ? const Color(0xFFE7E9EF) : const Color(0xFF0A0B0D),
      panelTop: light ? Colors.white : const Color(0xFF18191F),
      panelBottom: light ? const Color(0xFFF5F6FA) : const Color(0xFF121318),
      panelBorder: light ? const Color(0xFFE3E6EC) : const Color(0xFF272932),
      text: light ? const Color(0xFF14161C) : const Color(0xFFECEDF1),
      icon: light ? const Color(0xFF3A3F4E) : const Color(0xFFC9CCD6),
      textDim: light ? const Color(0xFF5A6171) : const Color(0xFF9DA1AE),
      track: light ? const Color(0xFFE4E7EE) : const Color(0xFF1B1D23),
      border: light ? const Color(0xFFC3C9D5) : const Color(0xFF2E313B),
      hover: light ? const Color(0xFFE6E9F0) : const Color(0xFF1C1E24),
      accent: accent,
      accentInk: inkFor(accent, surface, light),
      onAccent: onAccentFor(accent),
    );
  }

  @override
  NslPalette copyWith() => this;

  @override
  NslPalette lerp(ThemeExtension<NslPalette>? other, double t) => this;
}

extension NslThemeContext on BuildContext {
  NslPalette get pal => Theme.of(this).extension<NslPalette>()!;
}

/// Dark video stage colors: always dark, in both themes.
class NslStage {
  static const center = Color(0xFF10121A);
  static const edge = Color(0xFF040506);
  static const text = Color(0xFF9DA1AE);
}

const defaultAccent = Color(0xFFF4B860);

const accentPresets = <(String, Color)>[
  ('Amber', Color(0xFFF4B860)),
  ('Teal', Color(0xFF7DD3C0)),
  ('Blue', Color(0xFF8AB4F8)),
  ('Coral', Color(0xFFF08A8A)),
];

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Darkens (light theme) or lightens (dark theme) [accent] until it has
/// at least 4.5:1 contrast against [surface].
Color inkFor(Color accent, Color surface, bool light) {
  final toward = light ? Colors.black : Colors.white;
  var ink = accent;
  for (var k = 1; contrast(ink, surface) < 4.5 && k <= 20; k++) {
    ink = Color.lerp(accent, toward, k / 20)!;
  }
  return ink;
}

Color onAccentFor(Color accent) {
  const dark = Color(0xFF1A1204);
  return contrast(accent, dark) >= contrast(accent, Colors.white)
      ? dark
      : Colors.white;
}

ThemeData buildTheme(Brightness b, Color accent) {
  final p = NslPalette.of(b, accent);
  return ThemeData(
    brightness: b,
    scaffoldBackgroundColor: p.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
    ).copyWith(primary: p.accentInk, surface: p.panelTop),
    fontFamily: 'Segoe UI',
    useMaterial3: true,
    extensions: [p],
  );
}
