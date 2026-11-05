import 'package:flutter/material.dart';

import '../../data/towns.dart';
import '../../models/trip.dart';

/// Full-screen list for choosing a town. Returns a [TripStop] via Navigator.pop.
/// Later: replace the list with Google Places autocomplete + a map pin.
class StopPickerScreen extends StatefulWidget {
  final String title;
  final List<String> excludeNames;
  const StopPickerScreen({super.key, this.title = 'Choose a place', this.excludeNames = const []});

  static Future<TripStop?> open(BuildContext context, {String title = 'Choose a place', List<String> exclude = const []}) {
    return Navigator.of(context).push<TripStop>(
      MaterialPageRoute(builder: (_) => StopPickerScreen(title: title, excludeNames: exclude)),
    );
  }

  @override
  State<StopPickerScreen> createState() => _StopPickerScreenState();
}

class _StopPickerScreenState extends State<StopPickerScreen> {
  String _filter = '';

  List<TripStop> get _visible => kTowns
      .where((t) => !widget.excludeNames.contains(t.name))
      .where((t) => t.name.toLowerCase().contains(_filter.toLowerCase()))
      .toList();

  Future<void> _customPlace() async {
    final stop = await showDialog<TripStop>(context: context, builder: (_) => _CustomPlaceDialog(initialName: _filter));
    if (stop != null && mounted) Navigator.pop(context, stop);
  }

  @override
  Widget build(BuildContext context) {
    final towns = _visible;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search town',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final t in towns)
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(t.name),
                subtitle: Text('${t.lat.toStringAsFixed(4)}, ${t.lng.toStringAsFixed(4)}'),
                onTap: () => Navigator.pop(context, t),
              ),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text('Other place (enter coordinates)'),
              onTap: _customPlace,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CustomPlaceDialog extends StatefulWidget {
  final String initialName;
  const _CustomPlaceDialog({required this.initialName});
  @override
  State<_CustomPlaceDialog> createState() => _CustomPlaceDialogState();
}

class _CustomPlaceDialogState extends State<_CustomPlaceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _lat = TextEditingController();
  final _lng = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  String? _range(String? v, double min, double max) {
    final d = double.tryParse(v ?? '');
    if (d == null || d < min || d > max) return 'Between $min and $max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true, signed: true);
    return AlertDialog(
      title: const Text('Other place'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
          ),
          TextFormField(
            controller: _lat,
            keyboardType: numberKeyboard,
            decoration: const InputDecoration(labelText: 'Latitude', hintText: '6.9271'),
            validator: (v) => _range(v, -90, 90),
          ),
          TextFormField(
            controller: _lng,
            keyboardType: numberKeyboard,
            decoration: const InputDecoration(labelText: 'Longitude', hintText: '79.8612'),
            validator: (v) => _range(v, -180, 180),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              TripStop(name: _name.text.trim(), lat: double.parse(_lat.text), lng: double.parse(_lng.text)),
            );
          },
          child: const Text('Use place'),
        ),
      ],
    );
  }
}
