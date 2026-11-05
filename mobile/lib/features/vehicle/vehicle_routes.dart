import 'package:flutter/material.dart';

import 'data/vehicle_api.dart';
import 'screens/vehicle_documents_screen.dart';
import 'screens/vehicle_form_screen.dart';
import 'screens/vehicle_list_screen.dart';
import 'screens/vehicle_verification_screen.dart';

/// The vehicle screens' named routes. Used by MaterialApp.onGenerateRoute in main.dart.
///
///   /vehicles                    my vehicles list
///   /vehicles/new                add vehicle
///   /vehicles/:id/edit           edit vehicle
///   /vehicles/:id/documents      upload documents
///   /vehicles/:id/verification   status + submit
Route<dynamic>? vehicleRoute(RouteSettings settings, VehicleApi api) {
  final Widget? screen = switch (Uri.parse(settings.name ?? '').pathSegments) {
    ['vehicles'] => VehicleListScreen(api: api),
    ['vehicles', 'new'] => VehicleFormScreen(api: api),
    ['vehicles', final id, 'edit'] => VehicleFormScreen(api: api, vehicleId: id),
    ['vehicles', final id, 'documents'] => VehicleDocumentsScreen(api: api, vehicleId: id),
    ['vehicles', final id, 'verification'] => VehicleVerificationScreen(api: api, vehicleId: id),
    _ => null,
  };
  if (screen == null) return null;
  return MaterialPageRoute<void>(settings: settings, builder: (_) => screen);
}
