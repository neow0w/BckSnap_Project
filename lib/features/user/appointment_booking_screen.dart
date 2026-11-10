import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_client.dart';
import '../../services/clinic_service.dart';

import 'dart:typed_data';

import 'package:image/image.dart' as img;

class AppointmentBookingScreen extends StatefulWidget {
  const AppointmentBookingScreen({required this.clinicId, super.key});

  final String clinicId;

  @override
  State<AppointmentBookingScreen> createState() =>
      _AppointmentBookingScreenState();
}

class _AppointmentBookingScreenState
    extends State<AppointmentBookingScreen> {
  final ClinicService _service = ClinicService();
  final ImagePicker _imagePicker = ImagePicker();

  XFile? _referralImage;

  bool get _requiresReferral {
    return _doctor?.requiresReferral == true ||
        _doctor?.professionalType == 'Physical Therapist';
  }

  ClinicInfo? _clinic;
  ClinicDoctor? _doctor;
  String? _mode;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  List<AppointmentSlot> _slots = [];
  AppointmentSlot? _selectedSlot;
  bool _loadingClinic = true;
  bool _loadingSlots = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClinic();
  }

  Future<void> _loadClinic() async {
    try {
      final clinic = await _service.clinic(widget.clinicId);
      if (!mounted) return;
      setState(() {
        _clinic = clinic;
        _doctor = clinic.doctors.length == 1 ? clinic.doctors.single : null;
        final modes = _availableModes(clinic, _doctor);
        _mode = modes.isEmpty ? null : modes.first;
      });
      await _loadSlots();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loadingClinic = false);
    }
  }

  List<String> _availableModes(ClinicInfo clinic, ClinicDoctor? doctor) {
    final modes = <String>[];
    if (clinic.supportsPhysical ||
        (doctor?.isDemo == true &&
            clinic.demoAppointmentTypes.any(
              (type) => type.mode == 'physical',
            ))) {
      modes.add('physical');
    }
    if (clinic.supportsOnline ||
        (doctor?.isDemo == true &&
            clinic.demoAppointmentTypes.any((type) => type.mode == 'online'))) {
      modes.add('online');
    }
    return modes;
  }

  String _modeLabel(ClinicInfo clinic, String mode) {
    if (_doctor?.isDemo == true) {
      final demoTypes = clinic.demoAppointmentTypes.where(
        (type) => type.mode == mode,
      );
      return demoTypes.isEmpty ? 'DEMO' : demoTypes.first.name;
    }
    return mode == 'online' ? 'Online' : 'In person';
  }

  Future<void> _loadSlots() async {
    final clinic = _clinic;
    final doctor = _doctor;
    final mode = _mode;
    if (clinic == null || doctor == null || mode == null) {
      setState(() {
        _slots = [];
        _selectedSlot = null;
      });
      return;
    }
    setState(() {
      _loadingSlots = true;
      _error = null;
      _selectedSlot = null;
    });
    try {
      final slots = await _service.slots(
        clinicId: clinic.id,
        doctorId: doctor.id,
        date: _date,
        mode: mode,
      );
      if (mounted) setState(() => _slots = slots);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _slots = [];
          _error = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _selectDate() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final selected = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(now) ? now : _date,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (selected == null || !mounted) return;
    setState(() => _date = DateUtils.dateOnly(selected));
    await _loadSlots();
  }

  Future<void> _pickReferralImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1200,
        maxHeight: 1200,
      );

      if (image == null || !mounted) return;

      setState(() {
        _referralImage = image;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to select the referral image. Please try again.';
      });
    }
  }

  Future<void> _submit() async {
    final clinic = _clinic;
    final doctor = _doctor;
    final mode = _mode;
    final slot = _selectedSlot;
    if (_requiresReferral && _referralImage == null) {
      setState(() {
        _error = "Please upload your doctor's referral before booking.";
      });
      return;
    }
    if (clinic == null || doctor == null || mode == null || slot == null) {
      setState(
        () => _error = 'Select a doctor, appointment type, and available time.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final appointment = await _service.book(
        clinicId: clinic.id,
        doctorId: doctor.id,
        mode: mode,
        startsAt: slot.startsAt,
        referralImageBytes: _requiresReferral
          ? await _compressReferralImage(_referralImage!)
          : null,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline, size: 42),
          title: const Text('Request received'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Your appointment is pending clinic approval.'),
              const SizedBox(height: 12),
              Text('Reference: ${appointment.reference ?? 'Unavailable'}'),
              Text('Status: ${appointmentStatusLabel(appointment.status)}'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (mounted) context.go('/appointments');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
      if (error.statusCode == 409) await _loadSlots();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<Uint8List> _compressReferralImage(XFile file) async {
    final originalBytes = await file.readAsBytes();
    final decodedImage = img.decodeImage(originalBytes);

    if (decodedImage == null) {
      throw Exception('Unable to read the referral image.');
    }

    var resizedImage = img.copyResize(
      decodedImage,
      width: decodedImage.width > 1200 ? 1200 : decodedImage.width,
    );

    var quality = 85;
    var compressedBytes = img.encodeJpg(resizedImage, quality: quality);

    while (compressedBytes.length > 400 * 1024 && quality > 40) {
      quality -= 10;
      compressedBytes = img.encodeJpg(resizedImage, quality: quality);
    }

    while (compressedBytes.length > 400 * 1024 && resizedImage.width > 600) {
      resizedImage = img.copyResize(
        resizedImage,
        width: (resizedImage.width * 0.8).round(),
      );

      compressedBytes = img.encodeJpg(resizedImage, quality: quality);
    }

    if (compressedBytes.length > 400 * 1024) {
      throw Exception(
        'The referral image is too large. Please choose a smaller image.',
      );
    }

    return Uint8List.fromList(compressedBytes);
  }

  @override
  Widget build(BuildContext context) {
    final clinic = _clinic;
    return Scaffold(
      appBar: AppBar(title: const Text('Book an appointment')),
      body: _loadingClinic
          ? const Center(child: CircularProgressIndicator())
          : clinic == null
          ? _errorView()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      clinic.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(clinic.address),
                    if (clinic.demoAppointmentTypes.isNotEmpty)
                      Card(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'DEVELOPMENT DEMO ONLY — Any provider, specialty, time, or appointment marked DEMO is fictional. Online appointments are simulated and do not provide a real consultation.',
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      '1. Choose a doctor',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (clinic.doctors.isEmpty)
                      const Text(
                        'No doctors are currently available for booking.',
                      )
                    else
                      DropdownButtonFormField<ClinicDoctor>(
                        initialValue: _doctor,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Doctor',
                        ),
                        items: [
                          for (final doctor in clinic.doctors)
                            DropdownMenuItem(
                              value: doctor,
                              child: Text(
                                '${doctor.name ?? 'Doctor'}${doctor.isDemo ? ' — DEMO' : ' · ${doctor.isPresentToday ? 'In clinic today' : 'Not in today'}'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (doctor) {
                          setState(() {
                            _doctor = doctor;
                            _referralImage = null;
                            final modes = _availableModes(clinic, doctor);
                            _mode = modes.isEmpty ? null : modes.first;
                          });
                          _loadSlots();
                        },
                      ),
                    const SizedBox(height: 20),
                    Text(
                      '2. Choose an appointment type',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final mode in _availableModes(clinic, _doctor))
                          ChoiceChip(
                            label: Text(_modeLabel(clinic, mode)),
                            selected: _mode == mode,
                            onSelected: (_) {
                              setState(() => _mode = mode);
                              _loadSlots();
                            },
                          ),
                      ],
                    ),
                    if (!clinic.supportsPhysical && !clinic.supportsOnline) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Real appointments are not yet configured for this clinic. Marked DEMO appointment types below are fictional test options only.',
                      ),
                    ],
                    if (_requiresReferral) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Doctor\'s Referral (Required)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please upload a photo of the referral provided by your previous doctor.',
                      ),
                      const SizedBox(height: 12),
                      if (_referralImage != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: FutureBuilder<Uint8List>(
                            future: _referralImage!.readAsBytes(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return Image.memory(
                                  snapshot.data!,
                                  height: 180,
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                );
                              }
                              return const SizedBox(
                                height: 100,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _pickReferralImage,
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                          _referralImage == null
                              ? 'Upload referral image'
                              : 'Change referral image',
                        ),
                      ),
                      if (_referralImage != null)
                        TextButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _referralImage = null),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Remove image'),
                        ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      '3. Choose a date',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        MaterialLocalizations.of(context)
                            .formatMediumDate(_date),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '4. Choose an available time',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_loadingSlots)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_slots.isEmpty)
                      Text(
                        _doctor == null
                            ? 'Appointments are not yet available because no doctors have been configured.'
                            : _mode == null
                            ? 'Appointments are not yet available because no visit type has been confirmed.'
                            : 'No available times are published for this doctor, visit type, and date. The clinic must configure a schedule before booking.',
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final slot in _slots)
                            ChoiceChip(
                              label: Text(
                                MaterialLocalizations.of(context)
                                    .formatTimeOfDay(
                                      TimeOfDay.fromDateTime(slot.startsAt),
                                    ),
                              ),
                              selected: _selectedSlot == slot,
                              onSelected: (_) =>
                                  setState(() => _selectedSlot = slot),
                            ),
                        ],
                      ),
                    if (_selectedSlot != null) ...[
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '5. Review request',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text('Clinic: ${clinic.name}'),
                              Text('Doctor: ${_doctor?.name ?? 'Unavailable'}'),
                              Text('Visit: ${_modeLabel(clinic, _mode!)}'),
                              if (_doctor?.isDemo == true)
                                const Text(
                                  'DEMO booking — fictional data; online mode is simulated only.',
                                ),
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatMediumDate(_date),
                              ),
                              Text(
                                MaterialLocalizations.of(context)
                                    .formatTimeOfDay(
                                      TimeOfDay.fromDateTime(
                                        _selectedSlot!.startsAt,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'The clinic will confirm or reject your request.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed:
                          _submitting || _selectedSlot == null || _slots.isEmpty
                          ? null
                          : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Request appointment'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _errorView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? 'Clinic information is unavailable.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loadClinic,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
