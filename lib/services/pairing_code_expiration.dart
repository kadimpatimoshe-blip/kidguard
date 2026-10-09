const pairingCodeLifetime = Duration(minutes: 5);

DateTime? pairingCodeExpiresAt(String timestamp) {
  final createdAt = DateTime.tryParse(timestamp);
  return createdAt?.toUtc().add(pairingCodeLifetime);
}

Duration pairingCodeTimeRemaining(
  String timestamp, {
  DateTime? now,
}) {
  final expiresAt = pairingCodeExpiresAt(timestamp);
  if (expiresAt == null) return Duration.zero;

  final remaining = expiresAt.difference((now ?? DateTime.now()).toUtc());
  return remaining.isNegative ? Duration.zero : remaining;
}

bool isPairingCodeExpired(
  String timestamp, {
  DateTime? now,
}) {
  return pairingCodeTimeRemaining(timestamp, now: now) == Duration.zero;
}
