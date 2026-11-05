import 'package:flutter/material.dart';

import '../../../core/formatters.dart';
import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../models/driver_models.dart';
import '../widgets/driver_widgets.dart';

/// SCRUM-39, SCRUM-46: view and edit driver details, and see the rating.
class DriverProfileScreen extends StatefulWidget {
  final DriverRepository repository;
  final DriverProfile driver;
  const DriverProfileScreen({super.key, required this.repository, required this.driver});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late DriverProfile _driver = widget.driver;
  late final _licence = TextEditingController(text: _driver.licenceNumber);
  late final _address = TextEditingController(text: _driver.address ?? '');
  late final _contactName = TextEditingController(text: _driver.emergencyContactName ?? '');
  late final _contactPhone = TextEditingController(text: _driver.emergencyContactPhone ?? '');
  late String _licenceExpiry = _driver.licenceExpiry;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _licence.dispose();
    _address.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    super.dispose();
  }

  Map<String, dynamic> _changes() {
    final licence = _licence.text.trim().toUpperCase();
    final address = _address.text.trim();
    final name = _contactName.text.trim();
    final phone = _contactPhone.text.trim();
    return {
      if (licence != _driver.licenceNumber) 'licenceNumber': licence,
      if (_licenceExpiry != _driver.licenceExpiry) 'licenceExpiry': _licenceExpiry,
      if (address != (_driver.address ?? '')) 'address': address,
      if (name != (_driver.emergencyContactName ?? '')) 'emergencyContactName': name,
      if (phone != (_driver.emergencyContactPhone ?? '')) 'emergencyContactPhone': phone,
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final changes = _changes();
    if (changes.isEmpty) {
      showSnack(context, 'There are no changes to save.');
      return;
    }

    final licenceChanged = changes.containsKey('licenceNumber') || changes.containsKey('licenceExpiry');
    if (licenceChanged && _driver.isApproved) {
      final ok = await confirmDialog(
        context,
        title: 'Change your licence details?',
        message: 'This sends you back to review, and you cannot offer trips until an admin approves you again.',
        confirmLabel: 'Change',
      );
      if (!ok) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await widget.repository.update(changes);
      if (!mounted) return;
      setState(() => _driver = updated);
      showSnack(context, 'Profile saved');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateOfBirth = _driver.dateOfBirth == null ? null : DateTime.tryParse(_driver.dateOfBirth!);
    final rating = _driver.ratingCount == 0
        ? 'No ratings yet'
        : '${_driver.averageRating.toStringAsFixed(1)} from ${_driver.ratingCount} '
            '${_driver.ratingCount == 1 ? 'rating' : 'ratings'}';
    return Scaffold(
      appBar: AppBar(title: const Text('Driver profile')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            Expanded(child: Text('Verification', style: Theme.of(context).textTheme.titleMedium)),
            DriverStatusChip(_driver.verification),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('Account', style: Theme.of(context).textTheme.titleMedium)),
            DriverStatusChip(_driver.accountStatus),
          ]),
          const SizedBox(height: 8),
          InfoRow(icon: Icons.star_outline, label: 'Rating', value: rating),
          InfoRow(icon: Icons.flag_outlined, label: 'Completed trips', value: '${_driver.completedTrips}'),
          if (dateOfBirth != null)
            InfoRow(icon: Icons.cake_outlined, label: 'Date of birth', value: formatDate(dateOfBirth)),
          const SectionTitle('Licence'),
          TextFormField(
            controller: _licence,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Licence number'),
            validator: DriverValidators.licence,
          ),
          const SizedBox(height: 12),
          DriverDateField(
            label: 'Licence expiry date',
            value: _licenceExpiry,
            firstDate: today,
            lastDate: DateTime(today.year + 20),
            initialDate: today,
            onChanged: (v) => setState(() => _licenceExpiry = v),
          ),
          const SectionTitle('Contact details'),
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Address'),
            validator: DriverValidators.required,
          ),
          TextFormField(
            controller: _contactName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Emergency contact name'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the contact\'s name' : null,
          ),
          TextFormField(
            controller: _contactPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Emergency contact mobile number'),
            validator: DriverValidators.phone,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 20),
          BusyButton(busy: _busy, onPressed: _save, label: 'Save changes'),
        ]),
      ),
    );
  }
}
