import 'package:latlong2/latlong.dart';

import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';

class PathHopResolver {
  const PathHopResolver._();

  static List<Contact?> resolve({
    required List<int> pathBytes,
    required List<Contact> contacts,
    LatLng? endpoint,
    bool resolveFromEnd = false,
  }) {
    final candidatesByPrefix = <int, List<Contact>>{};
    for (final contact in contacts) {
      if (contact.publicKey.isEmpty) continue;
      if (contact.type != advTypeRepeater && contact.type != advTypeRoom) {
        continue;
      }
      candidatesByPrefix
          .putIfAbsent(contact.publicKey.first, () => <Contact>[])
          .add(contact);
    }
    for (final candidates in candidatesByPrefix.values) {
      candidates.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    }

    final resolved = List<Contact?>.filled(pathBytes.length, null);
    final indexes = resolveFromEnd
        ? List<int>.generate(pathBytes.length, (i) => pathBytes.length - 1 - i)
        : List<int>.generate(pathBytes.length, (i) => i);
    final distance = Distance();
    var previousPosition = endpoint;

    for (final index in indexes) {
      final candidates = candidatesByPrefix[pathBytes[index]];
      if (candidates == null || candidates.isEmpty) continue;

      var bestIndex = 0;
      if (previousPosition != null && candidates.length > 1) {
        double? nearestDistance;
        for (var i = 0; i < candidates.length; i++) {
          final position = _positionOf(candidates[i]);
          if (position == null) continue;
          final candidateDistance = distance(previousPosition, position);
          if (nearestDistance == null || candidateDistance < nearestDistance) {
            nearestDistance = candidateDistance;
            bestIndex = i;
          }
        }
      }

      final contact = candidates.removeAt(bestIndex);
      resolved[index] = contact;
      previousPosition = _positionOf(contact) ?? previousPosition;
    }

    return resolved;
  }

  static LatLng? _positionOf(Contact contact) {
    if (!contact.hasLocation ||
        contact.latitude == null ||
        contact.longitude == null) {
      return null;
    }
    return LatLng(contact.latitude!, contact.longitude!);
  }
}
