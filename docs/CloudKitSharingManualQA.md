# CloudKit Shared Library Manual QA

Current MVP manual QA for the single shared `Our Library` flow.

## Prerequisites
- Run on signed-in physical iPhones with an iCloud container that matches `PersistenceController.Configuration.live` and [SouvieShelf.entitlements](/Users/jongalante/Desktop/souvieshelf/SouvieShelf.entitlements).
- Use two Apple IDs: one owner and one partner.
- Confirm CloudKit sharing is enabled for the app target.

## Owner Flow
1. Launch SouvieShelf.
2. Create `Our Library`.
3. Open the `Library` tab.
4. Tap the gear button to open `Settings`.
5. Tap `Invite Partner`.
5. Confirm Apple's native CloudKit sharing sheet appears.
6. Send the invite to the partner.

## Partner Flow
1. Open the invite link on the partner device.
2. Accept the share.
3. Confirm SouvieShelf launches or foregrounds.
4. Confirm the app resolves into the shared library without a relaunch.
5. Confirm `Settings` shows the partner/shared-library state without exposing owner-only controls.

## Post-Share Validation
1. On the owner device, add a souvenir with a `Got it in` place and optionally assign it to a trip.
2. Confirm it appears in `Library > Items`, `Library > Places`, and `Map`.
3. Wait for CloudKit sync on the partner device.
4. Confirm the same souvenir appears in the partner's `Library` and `Map`.
5. Edit the souvenir on one device and confirm the updated title or story syncs to the other device.
6. Soft-delete the souvenir and confirm it disappears from `Library`, `Places`, `Map`, and trip detail while appearing in `Recently Deleted`.
7. Restore the souvenir from `Recently Deleted` and confirm it reappears through the normal library views.
8. Add another souvenir after sharing is already set up and confirm it also syncs across devices.

## Logs To Watch
- Existing share fetch vs new share creation
- Native share UI preparation
- Incoming share metadata receipt
- Share acceptance success or failure
- Shared-library launch resolution after acceptance
- Owner-side child-object attachment to the existing library share
