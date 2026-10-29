# KidGuard Kid Pro Security Specification

## Data Invariants
1. A parent document can only be created by the owner (matching UID).
2. A child device record under a parent can only be read or written by that parent.
3. A global device registry entry (/devices/{pairingCode}) can be read by anyone for initial pairing but can only be updated if the parent UID matches the authenticated user claiming it.

## The "Dirty Dozen" Payloads (Red Team Test Cases)
1. **Identity Spoofing**: Attempting to create a parent document with a UID that doesn't match `request.auth.uid`.
2. **Access Breach**: User A trying to read `parents/userB/children/dev123`.
3. **Ghost Field Injection**: Adding `isAdmin: true` to a device record.
4. **Invalid Type**: Sending a string for the `batteryLevel` number field.
5. **ID Poisoning**: Using a 10KB string as a `deviceId`.
6. **Orphaned Write**: Creating a child device under a parent that doesn't exist.
7. **Bypass Sync**: Updating a device status to `synced` without being authenticated.
8. **PII Leak**: Trying to 'list' all parents.
9. **Update Gap**: Changing the `parentUid` of a paired device to someone else.
10. **Resource Exhaustion**: Sending an array of 1,000,000 notifications in one write.
11. **Spoofed Timestamp**: Manually setting `updatedAt` to a future date instead of `request.time`.
12. **Unverified Auth**: Performing a write without `email_verified == true`.

## Test Runner (firestore.rules.test.ts placeholder)
Tests will verify that all above payloads return `PERMISSION_DENIED`.
