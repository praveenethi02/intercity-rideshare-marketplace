import 'package:flutter/material.dart';

import '../../../core/widgets/common_widgets.dart';
import '../data/driver_repository.dart';
import '../widgets/driver_widgets.dart';

/// SCRUM-38: registers the signed-in user as a driver. Pops with true on success.
class BecomeDriverScreen extends StatefulWidget {
  final DriverRepository repository;
  const BecomeDriverScreen({super.key, required this.repository});

  @override
  State<BecomeDriverScreen> createState() => _BecomeDriverScreenState();
}

class _BecomeDriverScreenState extends State<BecomeDriverScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licence = TextEditingController();
  final _nic = TextEditingController();
  final _address = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  String? _licenceExpiry;
  String? _dateOfBirth;
  String? _licenceExpiryError;
  String? _dateOfBirthError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _licence.dispose();
    _nic.dispose();
    _address.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final fieldsValid = _formKey.currentState!.validate();
    setState(() {
      _licenceExpiryError = _licenceExpiry == null ? 'Choose the expiry date' : null;
      _dateOfBirthError = _dateOfBirth == null ? 'Choose your date of birth' : null;
      _error = null;
    });
    if (!fieldsValid || _licenceExpiry == null || _dateOfBirth == null) return;

    setState(() => _busy = true);
    try {
      await widget.repository.register(
        licenceNumber: _licence.text.trim(),
        licenceExpiry: _licenceExpiry!,
        nic: _nic.text.trim(),
        dateOfBirth: _dateOfBirth!,
        address: _address.text.trim(),
        emergencyContactName: _contactName.text.trim(),
        emergencyContactPhone: _contactPhone.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final latestBirthDate = DriverValidators.latestAdultBirthDate(today);
    return Scaffold(
      appBar: AppBar(title: const Text('Become a driver')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Enter your details exactly as they appear on your licence and NIC.'),
          const SectionTitle('Licence'),
          TextFormField(
            controller: _licence,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Licence number', hintText: 'B1234567'),
            validator: DriverValidators.licence,
          ),
          const SizedBox(height: 12),
          DriverDateField(
            label: 'Licence expiry date',
            value: _licenceExpiry,
            firstDate: today,
            lastDate: DateTime(today.year + 20),
            initialDate: today,
            errorText: _licenceExpiryError,
            onChanged: (v) => setState(() {
              _licenceExpiry = v;
              _licenceExpiryError = null;
            }),
          ),
          const SectionTitle('Identity'),
          TextFormField(
            controller: _nic,
            decoration: const InputDecoration(labelText: 'NIC number', hintText: '199912345678'),
            validator: DriverValidators.nic,
          ),
          const SizedBox(height: 12),
          DriverDateField(
            label: 'Date of birth',
            value: _dateOfBirth,
            firstDate: DateTime(1940),
            lastDate: latestBirthDate,
            initialDate: latestBirthDate,
            errorText: _dateOfBirthError,
            onChanged: (v) => setState(() {
              _dateOfBirth = v;
              _dateOfBirthError = null;
            }),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _address,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Address'),
            validator: DriverValidators.required,
          ),
          const SectionTitle('Emergency contact'),
          TextFormField(
            controller: _contactName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Contact name'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the contact\'s name' : null,
          ),
          TextFormField(
            controller: _contactPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Contact mobile number', hintText: '0771234567'),
            validator: DriverValidators.phone,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 20),
          BusyButton(busy: _busy, onPressed: _submit, label: 'Register as a driver'),
          const SizedBox(height: 8),
          Text(
            'Next, you will upload your documents. An admin reviews them before you can offer trips.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}
