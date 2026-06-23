abstract class FormPayload {
  int get formId;

  List<String> get values;

  List<String> toMessageParts() => [formId.toString(), ...values];
}
