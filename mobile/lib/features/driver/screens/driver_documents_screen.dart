import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../models/driver_models.dart';

/// SCRUM-40, SCRUM-41: one card per required document, with upload and replace.
class DriverDocumentsScreen extends StatefulWidget {
  final DriverRepository repository;

  /// Lets tests supply a file without opening the system picker.
  final Future<PickedDocument?> Function() pickFile;

  const DriverDocumentsScreen({super.key, required this.repository, this.pickFile = pickDocumentFile});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class PickedDocument {
  final List<int> bytes;
  final String name;
  const PickedDocument(this.bytes, this.name);
}

const _maxFileBytes = 5 * 1024 * 1024;

Future<PickedDocument?> pickDocumentFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
  );
  if (file == null) return null;
  return PickedDocument(await file.readAsBytes(), file.name);
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  late Future<DriverProfile?> _future = widget.repository.myProfile();
  final Set<String> _uploading = {};

  void _reload() => setState(() => _future = widget.repository.myProfile());

  Future<void> _upload(DriverProfile driver, String type) async {
    final replacesApproved = driver.isApproved && type != 'PROFILE_PHOTO';
    if (replacesApproved) {
      final ok = await confirmDialog(
        context,
        title: 'Replace this document?',
        message: 'You are approved now. A new ${driverDocumentLabel(type)} sends you back to review, '
            'and you cannot offer trips until an admin approves you again.',
        confirmLabel: 'Replace',
      );
      if (!ok) return;
    }

    final PickedDocument? file;
    try {
      file = await widget.pickFile();
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the file: $e');
      return;
    }
    if (file == null || !mounted) return;
    if (file.bytes.length > _maxFileBytes) {
      showSnack(context, 'That file is over 5 MB. Choose a smaller one.');
      return;
    }

    setState(() => _uploading.add(type));
    try {
      await widget.repository.uploadDocument(type, file.bytes, file.name);
      if (!mounted) return;
      showSnack(context, '${driverDocumentLabel(type)} uploaded');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _uploading.remove(type));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My documents')),
      body: FutureBuilder<DriverProfile?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          final driver = snap.data;
          if (driver == null) return const EmptyView(icon: Icons.badge_outlined, message: 'Register as a driver first.');

          final byType = {for (final d in driver.documents) d.type: d};
          final uploaded = driverDocumentTypes.where(byType.containsKey).length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('$uploaded of ${driverDocumentTypes.length} uploaded', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: uploaded / driverDocumentTypes.length),
            const SizedBox(height: 8),
            Text(
              uploaded == driverDocumentTypes.length
                  ? 'All your documents are in.'
                  : 'Your application goes to an admin once all ${driverDocumentTypes.length} are uploaded.',
            ),
            const SizedBox(height: 4),
            Text('JPG, PNG or PDF, up to 5 MB each.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final type in driverDocumentTypes)
              _DocumentCard(
                type: type,
                document: byType[type],
                busy: _uploading.contains(type),
                onUpload: () => _upload(driver, type),
              ),
          ]);
        },
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final String type;
  final DriverDocument? document;
  final bool busy;
  final VoidCallback onUpload;

  const _DocumentCard({required this.type, required this.document, required this.busy, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    final doc = document;
    final uploadedAt = doc?.uploadedAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          _Thumbnail(document: doc),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(driverDocumentLabel(type), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                doc == null
                    ? 'Not uploaded'
                    : uploadedAt == null
                        ? 'Uploaded'
                        : 'Uploaded ${formatDate(uploadedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
          const SizedBox(width: 8),
          busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : doc == null
                  ? FilledButton(onPressed: onUpload, child: const Text('Upload'))
                  : OutlinedButton(onPressed: onUpload, child: const Text('Replace')),
        ]),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final DriverDocument? document;
  const _Thumbnail({required this.document});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final doc = document;
    Widget icon(IconData data) => Icon(data, color: colors.outline);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 56,
        color: colors.surfaceContainerHighest,
        child: doc == null
            ? icon(Icons.upload_file)
            : doc.isPdf
                ? icon(Icons.picture_as_pdf_outlined)
                : Image.network(
                    doc.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => icon(Icons.image_outlined),
                  ),
      ),
    );
  }
}
