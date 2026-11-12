import 'package:flutter/material.dart';

import '../services/library_service.dart';
import 'theme.dart';

/// Books page (PDF). Same stage as [PhotosView]: the shelf and the reader
/// come next.
class BooksView extends StatelessWidget {
  const BooksView({
    super.key,
    required this.library,
    required this.onOpenLibrary,
  });

  final LibraryService library;
  final VoidCallback onOpenLibrary;

  @override
  Widget build(BuildContext context) => _KindPage(
    library: library,
    onOpenLibrary: onOpenLibrary,
    title: 'Books',
    icon: Icons.menu_book_outlined,
    count: () => library.bookCount,
    noun: 'PDF book',
  );
}

class _KindPage extends StatelessWidget {
  const _KindPage({
    required this.library,
    required this.onOpenLibrary,
    required this.title,
    required this.icon,
    required this.count,
    required this.noun,
  });

  final LibraryService library;
  final VoidCallback onOpenLibrary;
  final String title;
  final IconData icon;
  final int Function() count;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final n = count();
        final noFolders = library.folders.isEmpty;
        final String message;
        if (library.scanning) {
          message = 'Looking through your library folders…';
        } else if (noFolders) {
          message =
              'Add a folder in Library and your ${noun}s will show up here.';
        } else if (n == 0) {
          message = 'No ${noun}s found in your library folders.';
        } else {
          message =
              '$n ${noun}${n == 1 ? '' : 's'} found in your library folders. '
              'The ${title.toLowerCase()} view is coming next.';
        }
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: p.textDim),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: p.textDim),
                ),
                if (noFolders && !library.scanning) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: onOpenLibrary,
                    child: const Text('Open Library'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
