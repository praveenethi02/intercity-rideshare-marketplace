import 'package:go_router/go_router.dart';

import 'screens/vehicle_documents_screen.dart';
import 'screens/vehicle_form_screen.dart';
import 'screens/vehicle_list_screen.dart';
import 'screens/vehicle_verification_screen.dart';

/// Spread into M1's core/router.dart (`...vehicleRoutes`).
///
///   /vehicles                    my vehicles list
///   /vehicles/new                add vehicle
///   /vehicles/:id/edit           edit vehicle
///   /vehicles/:id/documents      upload documents
///   /vehicles/:id/verification   status + submit
final List<RouteBase> vehicleRoutes = [
  GoRoute(
    path: '/vehicles',
    builder: (context, state) => const VehicleListScreen(),
    routes: [
      GoRoute(
        path: 'new',
        builder: (context, state) => const VehicleFormScreen(),
      ),
      GoRoute(
        path: ':id/edit',
        builder: (context, state) => VehicleFormScreen(vehicleId: state.pathParameters['id']),
      ),
      GoRoute(
        path: ':id/documents',
        builder: (context, state) => VehicleDocumentsScreen(vehicleId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: ':id/verification',
        builder: (context, state) => VehicleVerificationScreen(vehicleId: state.pathParameters['id']!),
      ),
    ],
  ),
];
