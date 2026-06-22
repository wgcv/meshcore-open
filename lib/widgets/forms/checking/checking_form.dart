import 'package:flutter/material.dart';

const checkingFormTitle = 'Checking';

Widget buildCheckingForm(BuildContext context) => const CheckingForm();

const _checkingFieldLabels = [
  'Incident/Exercise ID',
  '1.1 Date/Time',
  '1.2 From',
  '1.3 To',
  '2.1 Location Name',
  '2.2 Latitude',
  '2.3 Longitude',
  '3.1 Comments',
];

String buildCheckingFormString(List<String> values) {
  final fieldValues = List<String>.generate(
    _checkingFieldLabels.length,
    (index) => index < values.length ? values[index] : '',
  );

  return '''
$checkingFormTitle
Incident/Exercise ID: ${fieldValues[0]}

1. STATION
1.1 Date/Time: ${fieldValues[1]}
1.2 From: ${fieldValues[2]}
1.3 To: ${fieldValues[3]}

2. LOCATION
2.1 Location Name: ${fieldValues[4]}
2.2 Latitude: ${fieldValues[5]}
2.3 Longitude: ${fieldValues[6]}

3. COMMENTS
3.1 Comments: ${fieldValues[7]}
'''
      .trim();
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
    _dateTimeController.text = _formatDateTime(dateTime);
  }

  String _formatDateTime(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day $hour:$minute';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      buildCheckingFormString([
        _incidentController.text.trim(),
        _dateTimeController.text.trim(),
        _fromController.text.trim(),
        _toController.text.trim(),
        _locationNameController.text.trim(),
        _latitudeController.text.trim(),
        _longitudeController.text.trim(),
        _commentsController.text.trim(),
      ]),
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
            const _Header('Checking Form'),
            const _SectionHeader('1. Header'),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: [
                  _TextFormField(
                    controller: _incidentController,
                    labelText: '1.1 Incident/Exercise ID',
                  ),
                  _TextFormField(
                    controller: _fromController,
                    labelText: '1.2 From',
                  ),
                  _TextFormField(
                    controller: _toController,
                    labelText: '1.3 To',
                  ),
                  _LabeledFormField(
                    labelText: '1.4 Date/Time',
                    child: TextFormField(
                      controller: _dateTimeController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      onTap: _pickDateTime,
                    ),
                  ),
                ],
              ),
            ),
            const _SectionHeader('2. Location'),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: [
                  _TextFormField(
                    controller: _locationNameController,
                    labelText: '2.1 Location Name',
                  ),
                  _TextFormField(
                    controller: _latitudeController,
                    labelText: '2.2 Latitude',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                  _TextFormField(
                    controller: _longitudeController,
                    labelText: '2.3 Longitude',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ],
              ),
            ),
            const _SectionHeader('3. Additional Information'),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                children: [
                  _TextFormField(
                    controller: _commentsController,
                    labelText: '3.1 Comments',
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: const Text('Insert form'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;

  const _Header(this.title);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _TextFormField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final TextInputType? keyboardType;
  final int maxLines;

  const _TextFormField({
    required this.controller,
    required this.labelText,
    this.keyboardType,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledFormField(
      labelText: labelText,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
    );
  }
}

class _LabeledFormField extends StatelessWidget {
  final String labelText;
  final Widget child;

  const _LabeledFormField({required this.labelText, required this.child});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelText, style: textTheme.labelLarge),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
