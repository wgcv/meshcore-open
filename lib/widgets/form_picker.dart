import 'package:flutter/material.dart';
import 'package:meshcore_open/l10n/l10n.dart';
import 'package:meshcore_open/forms/form_catalog.dart';

class FormPicker extends StatefulWidget {
  final Function(List<String> formText) onFormSelected;

  const FormPicker({super.key, required this.onFormSelected});

  @override
  State<FormPicker> createState() => _FormPickerState();
}

class _FormPickerState extends State<FormPicker> {
  Future<void> _openForm(FormCatalogItem form) async {
    final builder = form.builder;
    if (builder == null) return;

    final formText = await Navigator.of(
      context,
    ).push<List<String>>(MaterialPageRoute<List<String>>(builder: builder));

    if (!mounted || formText == null) return;

    widget.onFormSelected(formText);
    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_add, size: 28),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                context.l10n.chat_addForm,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final group in formCatalog) ...[
            _FormGroup(group: group, onFormTap: _openForm),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _FormGroup extends StatelessWidget {
  final FormCatalogGroup group;
  final ValueChanged<FormCatalogItem> onFormTap;

  const _FormGroup({required this.group, required this.onFormTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final form in group.forms)
            _FormListItem(
              form: form,
              onTap: form.builder == null ? null : () => onFormTap(form),
            ),
        ],
      ),
    );
  }
}

class _FormListItem extends StatelessWidget {
  final FormCatalogItem form;
  final VoidCallback? onTap;

  const _FormListItem({required this.form, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      title: Text(form.title),
      subtitle: form.subtitle == null ? null : Text(form.subtitle!),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
