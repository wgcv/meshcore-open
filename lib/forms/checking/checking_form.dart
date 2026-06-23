import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/forms/form_payload.dart';
import 'package:meshcore_open/forms/widgets/form_widgets.dart';
import 'package:provider/provider.dart';

const checkingFormTitle = 'Checking';

Widget buildCheckingForm(BuildContext context) => const CheckingForm();

const _checkingFieldLabels = [
  'Check-In Form',
  '1. Header',
  '1.1 Incident/Exercise ID',
  '1.2 From',
  '1.3 To',
  '1.4 Date/Time',
  '2. Location',
  '2.1 Location Name',
  '2.2 Latitude',
  '2.3 Longitude',
  '3. Comments',
  '3.1 Comments',
];

class CheckingFormPayload extends FormPayload {
  static const id = 100;

  final String incidentId;
  final String dateTimeUnixSeconds;
  final String from;
  final String to;
  final String locationName;
  final String latitude;
  final String longitude;
  final String comments;

  CheckingFormPayload({
    required this.incidentId,
    required this.dateTimeUnixSeconds,
    required this.from,
    required this.to,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.comments,
  });

  @override
  int get formId => id;

  @override
  List<String> get values => [
    incidentId,
    dateTimeUnixSeconds,
    from,
    to,
    locationName,
    latitude,
    longitude,
    comments,
  ];
}

class CheckingForm extends StatefulWidget {
  const CheckingForm({super.key});

  @override
  State<CheckingForm> createState() => _CheckingFormState();
}

class _CheckingFormState extends State<CheckingForm> {
  final _formKey = GlobalKey<FormState>();
  final _incidentController = TextEditingController();
  final _dateTimeController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _locationNameController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _commentsController = TextEditingController();
  DateTime? _selectedDateTime;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();

    final nodeName = context.read<MeshCoreConnector>().selfName?.trim();
    if (nodeName != null && nodeName.isNotEmpty) {
      _fromController.text = nodeName;
    }
  }

  @override
  void dispose() {
    _incidentController.dispose();
    _dateTimeController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _locationNameController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );

    if (!mounted || time == null) return;

    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    _selectedDateTime = dateTime;
    _dateTimeController.text = _formatDateTime(dateTime);
  }

  String _dateTimeUnixSeconds() {
    final dateTime = _selectedDateTime;
    if (dateTime == null) return '';
    return (dateTime.millisecondsSinceEpoch ~/ 1000).toString();
  }

  String _formatDateTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day $hour:$minute';
  }

  Future<void> _populateCurrentLocation() async {
    if (_isLocating) return;

    setState(() => _isLocating = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('Location services are disabled on this device.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        _showSnackBar('Location permission is required to use GPS.');
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar(
          'Location permission is disabled for MeshCore.',
          action: SnackBarAction(
            label: 'Settings',
            onPressed: Geolocator.openAppSettings,
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      _latitudeController.text = position.latitude.toStringAsFixed(6);
      _longitudeController.text = position.longitude.toStringAsFixed(6);
      _showSnackBar('Location updated from device GPS.');
    } on TimeoutException {
      _showSnackBar('Timed out while waiting for a GPS location.');
    } on LocationServiceDisabledException {
      _showSnackBar('Location services are disabled on this device.');
    } catch (error) {
      _showSnackBar('Could not get location: $error');
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _showSnackBar(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      CheckingFormPayload(
        incidentId: _incidentController.text.trim(),
        dateTimeUnixSeconds: _dateTimeUnixSeconds(),
        from: _fromController.text.trim(),
        to: _toController.text.trim(),
        locationName: _locationNameController.text.trim(),
        latitude: _latitudeController.text.trim(),
        longitude: _longitudeController.text.trim(),
        comments: _commentsController.text.trim(),
      ).toMessageParts(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(checkingFormTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            FormPageTitle(_checkingFieldLabels[0]),
            FormSectionHeader(_checkingFieldLabels[1]),
            IndentedFormSection(
              children: [
                FormTextField(
                  controller: _incidentController,
                  labelText: _checkingFieldLabels[2],
                ),
                FormTextField(
                  controller: _fromController,
                  labelText: _checkingFieldLabels[3],
                  maxLength: 32,
                ),
                FormTextField(
                  controller: _toController,
                  labelText: _checkingFieldLabels[4],
                  maxLength: 32,
                ),
                FormTextField(
                  controller: _dateTimeController,
                  labelText: _checkingFieldLabels[5],
                  readOnly: true,
                  suffixIcon: const Icon(Icons.calendar_today),
                  onTap: _pickDateTime,
                ),
              ],
            ),
            FormSectionHeader(_checkingFieldLabels[6]),
            IndentedFormSection(
              children: [
                FormTextField(
                  controller: _locationNameController,
                  labelText: _checkingFieldLabels[7],
                ),
                ResponsiveFieldRow(
                  children: [
                    FormTextField(
                      controller: _latitudeController,
                      labelText: _checkingFieldLabels[8],
                      maxLength: 9,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                    FormTextField(
                      controller: _longitudeController,
                      labelText: _checkingFieldLabels[9],
                      maxLength: 9,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ],
                ),
                GpsLocationButton(
                  isLoading: _isLocating,
                  onPressed: _populateCurrentLocation,
                ),
              ],
            ),
            FormSectionHeader(_checkingFieldLabels[10]),
            IndentedFormSection(
              children: [
                FormTextField(
                  controller: _commentsController,
                  labelText: _checkingFieldLabels[11],
                  maxLines: 4,
                  maxLength: 147,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submit,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.send),
              label: const Text('Send form'),
            ),
          ],
        ),
      ),
    );
  }
}
