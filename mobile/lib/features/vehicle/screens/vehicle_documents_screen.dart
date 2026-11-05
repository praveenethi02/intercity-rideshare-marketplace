import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

const _maxBytes = 5 * 1024 * 1024; // API limit: 5 MB

/// A file chosen for upload.
class PickedVehicleFile {
  final List<int> bytes;
  final String name;
  const PickedVehicleFile(this.bytes, this.name);
}

Future<PickedVehicleFile?> pickVehicleFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
  );
  if (file == null) return null;
  return PickedVehicleFile(await file.readAsBytes(), file.name);
}

/// SCRUM-53: one card per document type; re-upload replaces.
class VehicleDocumentsScreen extends StatefulWidget {
  const VehicleDocumentsScreen({
    super.key,
    required this.api,
    required this.vehicleId,
    this.pickFile = pickVehicleFile,
  });

  final VehicleApi api;
  final String vehicleId;

  /// Lets tests supply a file without opening the system picker.
  final Future<PickedVehicleFile?> Function() pickFile;

  @override
  State<VehicleDocumentsScreen> createState() => _VehicleDocumentsScreenState();
}

class _VehicleDocumentsScreenState extends State<VehicleDocumentsScreen> {
  late Future<List<VehicleDocument>> _future = widget.api.documents(widget.vehicleId);

  void _reload() {
    setState(() {
      _future = widget.api.documents(widget.vehicleId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle documents')),
      body: FutureBuilder<List<VehicleDocument>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);

          final byType = {for (final d in snap.data!) d.docType: d};
          final missingRequired =
              requiredVehicleDocTypes.where((t) => byType[t] == null || byType[t]!.status == 'REJECTED').length;
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                missingRequired == 0
                    ? 'All required documents are uploaded.'
                    : '$missingRequired required document(s) still needed. Files: JPG, PNG or PDF, max 5 MB.',
              ),
              const SizedBox(height: 8),
              for (final entry in vehicleDocTypes.entries)
                _DocCard(
                  api: widget.api,
                  vehicleId: widget.vehicleId,
                  docType: entry.key,
                  label: entry.value,
                  isRequired: requiredVehicleDocTypes.contains(entry.key),
                  doc: byType[entry.key],
                  pickFile: widget.pickFile,
                  onUploaded: _reload,
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).pushNamed('/vehicles/${widget.vehicleId}/verification');
                  if (mounted) _reload();
                },
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Go to verification'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DocCard extends StatefulWidget {
  const _DocCard({
    required this.api,
    required this.vehicleId,
    required this.docType,
    required this.label,
    required this.isRequired,
    required this.pickFile,
    required this.onUploaded,
    this.doc,
  });

  final VehicleApi api;
  final String vehicleId;
  final String docType;
  final String label;
  final bool isRequired;
  final Future<PickedVehicleFile?> Function() pickFile;
  final VoidCallback onUploaded;
  final VehicleDocument? doc;

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> {
  bool _uploading = false;

  Future<void> _upload() async {
    final PickedVehicleFile? file;
    try {
      file = await widget.pickFile();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the file: $e');
      return;
    }
    if (file == null || !mounted) return; // user cancelled
    if (file.bytes.length > _maxBytes) {
      showSnack(context, 'File is larger than 5 MB.');
      return;
    }

    setState(() => _uploading = true);
    try {
      await widget.api.uploadDocument(widget.vehicleId, widget.docType, file.bytes, file.name);
      if (!mounted) return;
      showSnack(context, '${widget.label} uploaded');
      widget.onUploaded();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: doc == null
                    ? Container(color: Colors.black12, child: const Icon(Icons.upload_file))
                    : doc.isPdf
                        ? Container(color: Colors.black12, child: const Icon(Icons.picture_as_pdf, size: 32))
                        : Image.network(
                            doc.fileUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                          ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    StatusBadge(doc?.status ?? 'MISSING'),
                    if (widget.isRequired) const Text('Required', style: TextStyle(fontSize: 12)),
                  ]),
                ],
              ),
            ),
            _uploading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : TextButton(
                    onPressed: _upload,
                    child: Text(doc == null ? 'Upload' : 'Replace'),
                  ),
          ],
        ),
      ),
    );
  }
}
