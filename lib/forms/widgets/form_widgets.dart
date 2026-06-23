import 'package:flutter/material.dart';

class FormPageTitle extends StatelessWidget {
  final String title;

  const FormPageTitle(this.title, {super.key});

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

class FormSectionHeader extends StatelessWidget {
  final String title;

  const FormSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class IndentedFormSection extends StatelessWidget {
  final List<Widget> children;

  const IndentedFormSection({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Column(children: children),
    );
  }
}

class LabeledFormField extends StatelessWidget {
  final String labelText;
  final Widget child;

  const LabeledFormField({
    super.key,
    required this.labelText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelText, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class FormTextField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final bool readOnly;
  final Widget? suffixIcon;
  final VoidCallback? onTap;

  const FormTextField({
    super.key,
    required this.controller,
    required this.labelText,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength = 25,
    this.readOnly = false,
    this.suffixIcon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LabeledFormField(
      labelText: labelText,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        maxLength: maxLength,
        readOnly: readOnly,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          suffixIcon: suffixIcon,
        ),
        onTap: onTap,
      ),
    );
  }
}

class ResponsiveFieldRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  const ResponsiveFieldRow({
    super.key,
    required this.children,
    this.breakpoint = 520,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(children: children);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) SizedBox(width: spacing),
              Expanded(child: child),
            ],
          ],
        );
      },
    );
  }
}

class GpsLocationButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  final String labelText;
  final String loadingLabelText;

  const GpsLocationButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
    this.labelText = 'Use GPS location',
    this.loadingLabelText = 'Getting location...',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
        label: Text(isLoading ? loadingLabelText : labelText),
      ),
    );
  }
}
