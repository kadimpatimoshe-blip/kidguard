import 'package:flutter_test/flutter_test.dart';
import 'package:kidguard/services/pairing_code_expiration.dart';

void main() {
  group('pairing code expiration', () {
    final now = DateTime.utc(2026, 10, 9, 0, 0);

    test('returns the remaining lifetime from the creation timestamp', () {
      final createdAt = now.subtract(const Duration(minutes: 4, seconds: 30));

      expect(
        pairingCodeTimeRemaining(
          createdAt.toIso8601String(),
          now: now,
        ),
        const Duration(seconds: 30),
      );
    });

    test('expires at the five-minute boundary', () {
      final createdAt = now.subtract(pairingCodeLifetime);

      expect(
        isPairingCodeExpired(createdAt.toIso8601String(), now: now),
        isTrue,
      );
      expect(
        pairingCodeTimeRemaining(createdAt.toIso8601String(), now: now),
        Duration.zero,
      );
    });

    test('treats an invalid timestamp as expired', () {
      expect(isPairingCodeExpired('not-a-timestamp', now: now), isTrue);
      expect(
        pairingCodeTimeRemaining('not-a-timestamp', now: now),
        Duration.zero,
      );
    });
  });
}
