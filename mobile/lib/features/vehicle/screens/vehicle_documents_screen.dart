import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../data/vehicle_api.dart';
import '../data/vehicle_models.dart';
import '../widgets/vehicle_widgets.dart';

const _maxBytes = 5 * 1024 * 1024; // API limit: 5 MB

/// SCRUM-53: one card per document type; camera / gallery / PDF; re-upload replaces.
class VehicleDocumentsScreen extends ConsumerWidget {
  const VehicleDocumentsScreen({super.key, required this.vehicleId});
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(vehicleDocumentsProvider(vehicleId));

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle documents')),
      body: docs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          message: apiErrorMessage(e),
          onRetry: () => ref.invalidate(vehicleDocumentsProvider(vehicleId)),
        ),
        data: (list) {
          final byType = {for (final d in list) d.docType: d};
          final missingRequired = requiredVehicleDocTypes
              .where((t) => byType[t] == null || byType[t]!.status == 'REJECTED')
              .length;
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
                  vehicleId: vehicleId,
                  docType: entry.key,
                  label: entry.value,
                  isRequired: requiredVehicleDocTypes.contains(entry.key),
                  doc: byType[entry.key],
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.push('/vehicles/$vehicleId/verification'),
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

class _DocCard extends ConsumerStatefulWidget {
  const _DocCard({
    required this.vehicleId,
    required this.docType,
    required this.label,
    required this.isRequired,
    this.doc,
  });

  final String vehicleId;
  final String docType;
  final String label;
  final bool isRequired;
  final VehicleDocument? doc;

  @override
  ConsumerState<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends ConsumerState<_DocCard> {
  bool _uploading = false;

  Future<void> _pick(String source) async {
    String? path;
    String? name;
    try {
      if (source == 'pdf') {
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
        path = result?.files.single.path;
        name = result?.files.single.name;
      } else {
        final image = await ImagePicker().pickImage(
          source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
          imageQuality: 80,
          maxWidth: 2000,
        );
        path = image?.path;
        name = image?.name;
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open the picker (check permissions).', error: true);
      return;
    }
    if (path == null || name == null) return; // user cancelled

    if (await File(path).length() > _maxBytes) {
      if (mounted) showSnack(context, 'File is larger than 5 MB.', error: true);
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref.read(vehicleApiProvider).uploadDocument(widget.vehicleId, widget.docType, path, name);
      refreshVehicle(ref, widget.vehicleId);
      if (mounted) showSnack(context, '${widget.label} uploaded');
    } catch (e) {
      if (mounted) showSnack(context, apiErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _chooseSource() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Choose a PDF'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
        ]),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.doc;
    final api = ref.read(vehicleApiProvider);

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
                            api.absoluteUrl(doc.fileUrl),
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
                    onPressed: _chooseSource,
                    child: Text(doc == null ? 'Upload' : 'Replace'),
                  ),
          ],
        ),
      ),
    );
  }
}
