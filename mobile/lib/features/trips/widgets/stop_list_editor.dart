import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../models/trip_draft.dart';
import '../screens/shared/stop_picker_screen.dart';

/// Edits an ordered list of stops: change, add, remove and move middle stops.
/// The parent owns the list and gets a new copy through [onChanged].
class StopListEditor extends StatelessWidget {
  final List<TripStop> stops;
  final ValueChanged<List<TripStop>> onChanged;
  final bool enabled;

  const StopListEditor({super.key, required this.stops, required this.onChanged, this.enabled = true});

  String _label(int i) {
    if (i == 0) return 'Start';
    if (i == stops.length - 1) return 'End';
    return 'Stop $i';
  }

  Future<void> _change(BuildContext context, int i) async {
    final picked = await StopPickerScreen.open(context, title: 'Choose ${_label(i).toLowerCase()} point');
    if (picked == null) return;
    final copy = List<TripStop>.of(stops);
    copy[i] = picked;
    onChanged(copy);
  }

  Future<void> _addStop(BuildContext context) async {
    final picked = await StopPickerScreen.open(
      context,
      title: 'Add a stop',
      exclude: stops.map((s) => s.name).toList(),
    );
    if (picked == null) return;
    final copy = List<TripStop>.of(stops)..insert(stops.length - 1, picked);
    onChanged(copy);
  }

  void _remove(int i) => onChanged(List<TripStop>.of(stops)..removeAt(i));

  void _move(int i, int delta) {
    final copy = List<TripStop>.of(stops);
    final item = copy.removeAt(i);
    copy.insert(i + delta, item);
    onChanged(copy);
  }

  @override
  Widget build(BuildContext context) {
    final error = TripRules.checkStops(stops);
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < stops.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: enabled,
          leading: Icon(
            i == 0 ? Icons.trip_origin : (i == stops.length - 1 ? Icons.flag : Icons.more_vert),
            color: scheme.primary,
          ),
          title: Text(stops[i].name),
          subtitle: Text(_label(i)),
          onTap: enabled ? () => _change(context, i) : null,
          trailing: (!enabled || i == 0 || i == stops.length - 1)
              ? const Icon(Icons.edit_outlined, size: 18)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: i > 1 ? () => _move(i, -1) : null,
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.arrow_downward, size: 20),
                    onPressed: i < stops.length - 2 ? () => _move(i, 1) : null,
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _remove(i),
                  ),
                ]),
        ),
      if (enabled && stops.length >= 2 && stops.length < TripRules.maxStops)
        TextButton.icon(
          onPressed: () => _addStop(context),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Add a stop on the way'),
        ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(error, style: TextStyle(color: scheme.error)),
        ),
    ]);
  }
}
