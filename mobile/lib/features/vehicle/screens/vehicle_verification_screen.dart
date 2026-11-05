import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

/// SCRUM-54: shows status, missing documents and the rejection reason; Submit button.
class VehicleVerificationScreen extends ConsumerStatefulWidget {
  const VehicleVerificationScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  ConsumerState<VehicleVerificationScreen> createState() => _VehicleVerificationScreenState();
}

class _VehicleVerificationScreenState extends ConsumerState<VehicleVerificationScreen> {
  bool _submitting = false;

  static const _explain = {
    'NOT_SUBMITTED': 'Upload the required documents, then submit the vehicle for admin review.',
    'PENDING': 'An admin is reviewing your vehicle. You will be able to use it once it is approved.',
    'APPROVED': 'Your vehicle is approved. If it is active you can use it for trips.',
    'REJECTED': 'Your vehicle was rejected. Fix the problem below, re-upload documents and submit again.',
  };

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ref.read(vehicleApiProvider).submit(widget.vehicleId);
      refreshVehicle(ref, widget.vehicleId);
      if (mounted) showSnack(context, 'Submitted for review');
    } catch (e) {
      if (mounted) showSnack(context, apiErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(vehicleVerificationProvider(widget.vehicleId));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: info.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: apiErrorMessage(e),
          onRetry: () => ref.invalidate(vehicleVerificationProvider(widget.vehicleId)),
        ),
        data: (v) => RefreshIndicator(
          onRefresh: () => ref.refresh(vehicleVerificationProvider(widget.vehicleId).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Text('Status', style: text.titleMedium),
                const Spacer(),
                StatusBadge(v.status),
              ]),
              const SizedBox(height: 12),
              Text(_explain[v.status] ?? ''),
              if (v.status == 'REJECTED' && v.rejectionReason != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.red.shade50,
                  child: ListTile(
                    leading: Icon(Icons.info_outline, color: Colors.red.shade700),
                    title: const Text('Reason from admin'),
                    subtitle: Text(v.rejectionReason!),
                  ),
                ),
              ],
              if (v.missingDocuments.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Missing documents', style: text.titleMedium),
                for (final t in v.missingDocuments)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.close, color: Colors.red),
                    title: Text(vehicleDocTypes[t] ?? t),
                  ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/vehicles/${widget.vehicleId}/documents'),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload documents'),
                ),
              ],
              const SizedBox(height: 24),
              if (v.status == 'NOT_SUBMITTED' || v.status == 'REJECTED')
                FilledButton.icon(
                  onPressed: v.canSubmit && !_submitting ? _submit : null,
                  icon: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Submit for review'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
