import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/app_services.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../models/saved_route.dart';
import 'create_trip_screen.dart';
import 'saved_route_form_screen.dart';

/// Driver's saved route templates.
/// [pickMode] = true: tapping a route returns it (used by the create-trip wizard).
class SavedRoutesScreen extends StatefulWidget {
  final bool pickMode;
  const SavedRoutesScreen({super.key, this.pickMode = false});

  @override
  State<SavedRoutesScreen> createState() => _SavedRoutesScreenState();
}

class _SavedRoutesScreenState extends State<SavedRoutesScreen> {
  late Future<List<SavedRoute>> _future;

  @override
  void initState() {
    super.initState();
    _future = AppServices.of(context).trips.savedRoutes();
  }

  Future<void> _reload() async {
    final f = AppServices.of(context).trips.savedRoutes();
    setState(() => _future = f);
    await f.catchError((_) => <SavedRoute>[]);
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push<SavedRoute>(
      MaterialPageRoute(builder: (_) => const SavedRouteFormScreen()),
    );
    if (created != null && mounted) _reload();
  }

  Future<void> _delete(SavedRoute r) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${r.name}"?',
      message: 'Trips already created from this route are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppServices.of(context).trips.deleteSavedRoute(r.id);
      if (mounted) _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  void _tap(SavedRoute r) {
    if (widget.pickMode) {
      Navigator.pop(context, r);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => CreateTripScreen(fromSavedRoute: r)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pickMode ? 'Choose a saved route' : 'Saved routes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New route'),
      ),
      body: FutureBuilder<List<SavedRoute>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final routes = snap.data!;
          if (routes.isEmpty) {
            return const EmptyView(
              icon: Icons.bookmarks_outlined,
              message: 'Save routes you drive often,\nthen create trips from them in one tap.',
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: routes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = routes[i];
                return ListTile(
                  leading: const Icon(Icons.route),
                  title: Text(r.name),
                  subtitle: Text(r.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => _tap(r),
                  trailing: widget.pickMode
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(r),
                        ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
