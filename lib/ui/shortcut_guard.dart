import 'package:flutter/widgets.dart';

/// True while the user is typing in a text field.
bool textFieldHasFocus() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

/// Runs [onInvoke] for a keyboard shortcut, but steps aside while a text
/// field has focus and the shortcut is a plain key (Space, K, H ...). Without
/// that, typing a search in the Library would play, mute or navigate instead of
/// typing. Shortcuts with Ctrl (Ctrl+O, Ctrl+B ...) still work while typing.
///
/// When the action is disabled the key event is not handled, so it reaches
/// the text field as normal typing.
class GuardedAction<T extends Intent> extends Action<T> {
  GuardedAction({required this.onInvoke, required this.isPlainKey});

  final void Function(T intent) onInvoke;

  /// True for shortcuts made of a single character key (no Ctrl / Alt).
  final bool Function(T intent) isPlainKey;

  @override
  bool isEnabled(T intent) => !(isPlainKey(intent) && textFieldHasFocus());

  @override
  Object? invoke(T intent) {
    onInvoke(intent);
    return null;
  }
}
