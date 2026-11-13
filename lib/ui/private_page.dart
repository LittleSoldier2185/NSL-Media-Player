import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../player_controller/player_controller.dart';
import '../services/library_service.dart';
import '../services/media_types.dart';
import '../services/private_hub.dart';
import '../services/private_service.dart';
import 'books_view.dart';
import 'library_view.dart';
import 'photos_view.dart';
import 'theme.dart';

/// The Private section: asks for the PIN, then shows private music/video,
/// pictures and books with the same pages as the normal library.
class PrivatePage extends StatelessWidget {
  const PrivatePage({
    super.key,
    required this.hub,
    required this.controller,
    required this.onOpenPlayer,
  });

  final PrivateHub hub;

  /// The player (none in tests: the media tabs are then left empty).
  final NslPlayerController? controller;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: hub.lock,
      builder: (context, _) {
        final lock = hub.lock;
        if (!lock.hasPin) return _SetPin(hub: hub);
        if (!lock.unlocked) return _Unlock(hub: hub);
        return _Open(
          hub: hub,
          controller: controller,
          onOpenPlayer: onOpenPlayer,
        );
      },
    );
  }
}

// ---- lock screens ----

class _Card extends StatelessWidget {
  const _Card({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: p.panelTop,
              border: Border.all(color: p.panelBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _title(NslPalette p, IconData icon, String title, String body) => Column(
  children: [
    Icon(icon, size: 40, color: p.accentInk),
    const SizedBox(height: 12),
    Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: p.text,
      ),
    ),
    const SizedBox(height: 8),
    Text(
      body,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: p.textDim, height: 1.4),
    ),
    const SizedBox(height: 20),
  ],
);

/// First visit: choose a PIN.
class _SetPin extends StatefulWidget {
  const _SetPin({required this.hub});
  final PrivateHub hub;

  @override
  State<_SetPin> createState() => _SetPinState();
}

class _SetPinState extends State<_SetPin> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_a.text.length < PrivateService.minPinLength) {
      setState(
        () =>
            _error = 'Use at least ${PrivateService.minPinLength} characters.',
      );
      return;
    }
    if (_a.text != _b.text) {
      setState(() => _error = 'The two PINs are not the same.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.hub.lock.setPin(_a.text);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return _Card(
      children: [
        _title(
          p,
          Icons.lock_outline,
          'Set up Private',
          'Choose a PIN. Private files are hidden from the rest of the app '
              'until you enter it.\n\nThis locks the app only: the files are not '
              'encrypted and can still be opened in File Explorer. If you forget '
              'the PIN it cannot be recovered; you can only reset Private.',
        ),
        TextField(
          controller: _a,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New PIN'),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _b,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Repeat PIN'),
          onSubmitted: (_) => _save(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Colors.red.shade400)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Set PIN and open'),
        ),
      ],
    );
  }
}

/// Locked: ask for the PIN.
class _Unlock extends StatefulWidget {
  const _Unlock({required this.hub});
  final PrivateHub hub;

  @override
  State<_Unlock> createState() => _UnlockState();
}

class _UnlockState extends State<_Unlock> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Counts the waiting time down after too many wrong tries.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.hub.lock.waitLeft != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_busy || _pin.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.hub.lock.unlock(_pin.text);
    _pin.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Wrong PIN.';
    });
  }

  Future<void> _forgot() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Private?'),
        content: const Text(
          'This removes the PIN and empties Private: the private folders, '
          'tags, playlists, albums and reading places are forgotten, and the '
          'files go back to the normal library. No file is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.hub.reset();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final wait = widget.hub.lock.waitLeft;
    return _Card(
      children: [
        _title(
          p,
          Icons.lock,
          'Private is locked',
          'Enter your PIN to see private music, videos, pictures and books.',
        ),
        TextField(
          controller: _pin,
          obscureText: true,
          autofocus: true,
          enabled: wait == null,
          decoration: const InputDecoration(labelText: 'PIN'),
          onSubmitted: (_) => _go(),
        ),
        if (wait != null) ...[
          const SizedBox(height: 10),
          Text(
            'Too many wrong tries. Try again in ${_fmt(wait)}.',
            style: TextStyle(color: Colors.red.shade400),
          ),
        ] else if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Colors.red.shade400)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy || wait != null ? null : _go,
          child: Text(_busy ? 'Checking…' : 'Unlock'),
        ),
        const SizedBox(height: 6),
        TextButton(onPressed: _forgot, child: const Text('Forgot the PIN?')),
      ],
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}

// ---- unlocked ----

enum _Tab { media, photos, books, settings }

class _Open extends StatefulWidget {
  const _Open({
    required this.hub,
    required this.controller,
    required this.onOpenPlayer,
  });
  final PrivateHub hub;
  final NslPlayerController? controller;
  final VoidCallback onOpenPlayer;

  @override
  State<_Open> createState() => _OpenState();
}

class _OpenState extends State<_Open> {
  _Tab _tab = _Tab.media;

  PrivateHub get hub => widget.hub;

  Future<void> _addFiles() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        ...audioExtensions,
        ...videoExtensions,
        ...imageExtensions,
        ...pdfExtensions,
      ],
    );
    final paths = r?.paths.whereType<String>().toList() ?? const <String>[];
    if (paths.isEmpty) return;
    hub.lock.addFiles(paths);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Made ${paths.length} file(s) private.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.lock_open, color: p.accentInk),
              Text(
                'Private',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
              const SizedBox(width: 12),
              for (final (t, label) in const [
                (_Tab.media, 'Music & Video'),
                (_Tab.photos, 'Photos'),
                (_Tab.books, 'Books'),
                (_Tab.settings, 'Settings'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _tab == t,
                  onSelected: (_) => setState(() => _tab = t),
                ),
              OutlinedButton.icon(
                onPressed: _addFiles,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add files'),
              ),
              FilledButton.tonalIcon(
                onPressed: hub.lock.lock,
                icon: const Icon(Icons.lock, size: 18),
                label: const Text('Lock now'),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            _Tab.media =>
              widget.controller == null
                  ? const SizedBox.shrink()
                  : LibraryView(
                      library: hub.library,
                      playlists: hub.playlists,
                      controller: widget.controller!,
                      onOpenPlayer: widget.onOpenPlayer,
                    ),
            _Tab.photos => PhotosView(
              library: hub.library,
              albums: hub.albums,
              controller: widget.controller,
              onOpenPlayer: widget.onOpenPlayer,
              onOpenLibrary: () => setState(() => _tab = _Tab.media),
            ),
            _Tab.books => BooksView(
              library: hub.library,
              books: hub.books,
              controller: widget.controller,
              onOpenPlayer: widget.onOpenPlayer,
              onOpenLibrary: () => setState(() => _tab = _Tab.media),
            ),
            _Tab.settings => _PrivateSettings(hub: hub),
          },
        ),
      ],
    );
  }
}

// ---- settings ----

class _PrivateSettings extends StatefulWidget {
  const _PrivateSettings({required this.hub});
  final PrivateHub hub;

  @override
  State<_PrivateSettings> createState() => _PrivateSettingsState();
}

class _PrivateSettingsState extends State<_PrivateSettings> {
  PrivateService get lock => widget.hub.lock;

  static const _idle = [0, 1, 5, 10, 30, 60];

  Future<void> _changePin() async {
    final old = TextEditingController();
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Change PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: old,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current PIN'),
              ),
              TextField(
                controller: a,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New PIN'),
              ),
              TextField(
                controller: b,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repeat new PIN'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: TextStyle(color: Colors.red.shade400),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (a.text.length < PrivateService.minPinLength) {
                  setLocal(
                    () => error =
                        'Use at least ${PrivateService.minPinLength} characters.',
                  );
                } else if (a.text != b.text) {
                  setLocal(() => error = 'The new PINs are not the same.');
                } else if (await lock.changePin(old.text, a.text)) {
                  if (context.mounted) Navigator.pop(context, true);
                } else {
                  setLocal(() => error = 'The current PIN is wrong.');
                }
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    old.dispose();
    a.dispose();
    b.dispose();
    if (done == true && mounted) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('PIN changed.')));
    }
  }

  Future<void> _reset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Private?'),
        content: const Text(
          'This removes the PIN and empties Private: its folders, tags, '
          'playlists, albums and reading places are forgotten, and the files '
          'go back to the normal library. No file is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.hub.reset();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: Listenable.merge([lock, widget.hub.library]),
      builder: (context, _) {
        final folders = widget.hub.library.folders;
        final files = lock.taggedFiles;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _section(p, 'Locking'),
            ListTile(
              title: const Text('Lock after being idle'),
              trailing: DropdownButton<int>(
                value: _idle.contains(lock.autoLockMinutes)
                    ? lock.autoLockMinutes
                    : 10,
                onChanged: (v) {
                  if (v != null) lock.autoLockMinutes = v;
                },
                items: [
                  for (final m in _idle)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m == 0 ? 'Never' : '$m min'),
                    ),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Lock when the window is minimized'),
              value: lock.lockOnMinimize,
              onChanged: (v) => lock.lockOnMinimize = v,
            ),
            ListTile(
              title: const Text('Lock now'),
              subtitle: const Text('Ctrl+Shift+L from anywhere'),
              trailing: FilledButton.tonal(
                onPressed: lock.lock,
                child: const Text('Lock'),
              ),
            ),
            _section(p, 'Privacy'),
            SwitchListTile(
              title: const Text('Show "Private" instead of file names'),
              subtitle: const Text(
                'In the window title and the Windows media panel while a '
                'private file plays',
              ),
              value: lock.maskTitles,
              onChanged: (v) => lock.maskTitles = v,
            ),
            SwitchListTile(
              title: const Text('Hide Private from the sidebar'),
              subtitle: const Text('Open it with Ctrl+Shift+P'),
              value: lock.hideEntry,
              onChanged: (v) => lock.hideEntry = v,
            ),
            _section(p, 'Private folders'),
            if (folders.isEmpty)
              _hint(p, 'None yet. Add one from Music & Video > Add folder.'),
            for (final f in folders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${widget.hub.library.countIn(f)} playable files',
                ),
                trailing: TextButton(
                  onPressed: () => widget.hub.library.removeFolder(f),
                  child: const Text('Make public'),
                ),
              ),
            _section(p, 'Private files'),
            if (files.isEmpty)
              _hint(p, 'None yet. Use "Add files" at the top.'),
            for (final f in files)
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(
                  LibraryService.folderName(f),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(f, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(
                  onPressed: () => lock.removeFiles([f]),
                  child: const Text('Make public'),
                ),
              ),
            _section(p, 'PIN'),
            ListTile(
              title: const Text('Change PIN'),
              trailing: OutlinedButton(
                onPressed: _changePin,
                child: const Text('Change…'),
              ),
            ),
            ListTile(
              title: const Text('Reset Private'),
              subtitle: const Text(
                'Forget the PIN and everything private (no file is deleted)',
              ),
              trailing: OutlinedButton(
                onPressed: _reset,
                child: const Text('Reset…'),
              ),
            ),
            const SizedBox(height: 12),
            _hint(
              p,
              'Private locks the app only. Files are not encrypted or hidden '
              'on disk, so File Explorer and other programs can still open '
              'them.',
            ),
          ],
        );
      },
    );
  }

  Widget _section(NslPalette p, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
    child: Text(
      t,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: p.textDim,
      ),
    ),
  );

  Widget _hint(NslPalette p, String t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: Text(t, style: TextStyle(fontSize: 12.5, color: p.textDim)),
  );
}
