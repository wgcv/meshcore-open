import 'package:flutter/material.dart';
import 'package:meshcore_open/widgets/forms/checking/checking_form.dart';

class FormCatalogGroup {
  final String title;
  final List<FormCatalogItem> forms;

  const FormCatalogGroup({required this.title, required this.forms});
}

class FormCatalogItem {
  final String title;
  final String? subtitle;
  final WidgetBuilder? builder;

  const FormCatalogItem({required this.title, this.subtitle, this.builder});
}

const formCatalog = [
  FormCatalogGroup(
    title: 'General',
    forms: [
      FormCatalogItem(
        title: checkingFormTitle,
        subtitle: 'Incident / exercise check-in form',
        builder: buildCheckingForm,
      ),
      FormCatalogItem(title: 'Form 1', subtitle: 'Coming soon'),
    ],
  ),
  FormCatalogGroup(
    title: 'FEMA Forms',
    forms: [FormCatalogItem(title: 'Form 2', subtitle: 'Coming soon')],
  ),
];
