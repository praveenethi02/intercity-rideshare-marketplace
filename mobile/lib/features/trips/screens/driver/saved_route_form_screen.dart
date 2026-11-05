import 'package:flutter/material.dart';

import '../../../../core/api_client.dart';
import '../../../../core/app_services.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../data/towns.dart';
import '../../models/trip.dart';
import '../../models/trip_draft.dart';
import '../../widgets/stop_list_editor.dart';

/// Create a saved route. Pops with the created SavedRoute.
class SavedRouteFormScreen extends StatefulWidget {
  final List<TripStop>? initialStops;
  final String? initialName;
  const SavedRouteFormScreen({super.key, this.initialStops, this.initialName});

  @override
  State<SavedRouteFormScreen> createState() => _SavedRouteFormScreenState();
}

class _SavedRouteFormScreenState extends State<SavedRouteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late List<TripStop> _stops = widget.initialStops
          ?.map((s) => TripStop(name: s.name, lat: s.lat, lng: s.lng))
          .toList() ??
      [kTowns[0], kTowns[8]];
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final error = TripRules.checkStops(_stops);
    if (error != null) {
      showSnack(context, error);
      return;
    }
    setState(() => _saving = true);
    try {
      final route = await AppServices.of(context).trips.createSavedRoute(_name.text.trim(), _stops);
      if (!mounted) return;
      showSnack(context, 'Route saved');
      Navigator.pop(context, route);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Save a route')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Route name', hintText: 'e.g. Weekday Colombo → Kandy'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
          ),
          const SectionTitle('Stops'),
          StopListEditor(stops: _stops, onChanged: (s) => setState(() => _stops = s)),
          const SizedBox(height: 24),
          BusyButton(busy: _saving, onPressed: _save, label: 'Save route'),
        ]),
      ),
    );
  }
}
