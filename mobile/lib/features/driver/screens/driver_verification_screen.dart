import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../models/driver_models.dart';
import '../widgets/driver_widgets.dart';
import 'driver_documents_screen.dart';

/// SCRUM-42: where the driver stands in review, and what to do next.
class DriverVerificationScreen extends StatefulWidget {
  final DriverRepository repository;
  const DriverVerificationScreen({super.key, required this.repository});

  @override
  State<DriverVerificationScreen> createState() => _DriverVerificationScreenState();
}

class _DriverVerificationScreenState extends State<DriverVerificationScreen> {
  late Future<DriverVerification> _future = widget.repository.verification();

  void _reload() => setState(() => _future = widget.repository.verification());

  Future<void> _openDocuments() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DriverDocumentsScreen(repository: widget.repository)),
    );
    if (mounted) _reload();
  }

  String _message(DriverVerification v) {
    if (v.status == 'APPROVED') return 'You are verified.';
    if (v.status == 'REJECTED') return 'Your application needs changes. Replace the documents an admin asked about.';
    if (v.missingDocuments.isNotEmpty) return 'Upload the documents below to send your application for review.';
    return 'An admin is reviewing your documents.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification status')),
      body: FutureBuilder<DriverVerification>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final v = snap.data!;
          final submittedAt = v.submittedAt;
          final decidedAt = v.decidedAt;
          final reason = v.reason;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: Text('Status', style: Theme.of(context).textTheme.titleMedium)),
                DriverStatusChip(
                  v.status == 'PENDING' && v.missingDocuments.isNotEmpty ? driverStatusDocumentsNeeded : v.status,
                ),
              ]),
              const SizedBox(height: 12),
              Text(_message(v)),
              if (reason != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('Reason from the admin: $reason'),
                  ),
                ),
              ],
              if (submittedAt != null)
                InfoRow(icon: Icons.send_outlined, label: 'Sent for review', value: formatDateTime(submittedAt)),
              if (decidedAt != null)
                InfoRow(icon: Icons.gavel_outlined, label: 'Decided', value: formatDateTime(decidedAt)),
              if (v.missingDocuments.isNotEmpty) ...[
                const SectionTitle('Still needed'),
                for (final type in v.missingDocuments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.radio_button_unchecked),
                    title: Text(driverDocumentLabel(type)),
                  ),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openDocuments,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open my documents'),
              ),
            ]),
          );
        },
      ),
    );
  }
}
