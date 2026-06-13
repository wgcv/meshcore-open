import '../models/contact.dart';
import '../connector/meshcore_protocol.dart';

class PathHelper {
  static String formatPathHex(List<int> pathBytes) {
    return pathBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(',');
  }

  static String hopHex(int byte) {
    return byte.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  static String? hopName(int byte, List<Contact> allContacts) {
    final matches = allContacts
        .where(
          (c) =>
              c.publicKey.first == byte &&
              (c.type == advTypeRepeater || c.type == advTypeRoom),
        )
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first.name;
    return matches.map((c) => c.name).join(' | ');
  }

  static String resolvePathNames(
    List<int> pathBytes,
    List<Contact> allContacts,
  ) {
    return pathBytes
        .map((b) => hopName(b, allContacts) ?? hopHex(b))
        .join(' \u2192 ');
  }
}
