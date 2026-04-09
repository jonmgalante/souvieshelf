# SouvieShelf Agent Guide

## Project Purpose
SouvieShelf is a native iPhone app for two travel partners to save and revisit souvenirs together.
The product centers on one shared couple library called "Our Library".
It is iCloud-backed through the user's Apple account. There is no custom auth and no profile system.
The app has only two top-level surfaces: Library and Map, plus a central Add action.
Preserve this simple couple-first shape. Do not expand it into a broader social or marketplace product.

## Stack
- SwiftUI
- Core Data with `NSPersistentCloudKitContainer`
- CloudKit private sharing
- MapKit
- PhotosUI
- iOS 17+

## Architecture Rules
- Use live Core Data queries for reads. Prefer `@FetchRequest`, `@SectionedFetchRequest`, or equivalent live observation over manual read caches.
- Use repositories and services for writes and platform actions. Views should not own persistence, sharing, or Photos/Map side effects.
- Souvenirs and trips use soft delete. Do not hard-delete them unless the task explicitly adds a purge path.
- Places are derived from souvenir location fields unless the codebase later introduces an explicit place model.
- Prefer native Apple APIs over third-party dependencies.
- Keep patches small, compileable, and reviewable. Avoid speculative architecture.

## Product Guardrails
- One shared couple library only. Not "my library plus optional sharing".
- No custom auth.
- No profiles.
- No public profiles, marketplace, or social graph.
- No extra top-level tabs beyond Library and Map.
- Keep the product couple-first and intentionally narrow.

## Repo Map
Current repo state on 2026-04-08:
- `SouvieShelf.xcodeproj` contains one iOS app target (`SouvieShelf`) and one unit test target (`SouvieShelfTests`).
- The repo is scaffolded for incremental product work, but persistence, CloudKit sharing, Photos import, and real MapKit behavior are still intentionally placeholders.

Current top-level structure:
- `App/`: app entry, launch gating, root app state, and the Library / Add / Map shell.
- `Core/Routing/`: app routes and future detail payloads.
- `Core/Repositories/`: repository protocols only.
- `Core/Services/`: service protocols only.
- `Core/DependencyInjection/`: the composition root and placeholder implementations.
- `Features/Launch/`: launch, iCloud-required, and pairing screens.
- `Features/Library/`: library surface placeholder.
- `Features/Map/`: map surface placeholder.
- `Features/Souvenir/`, `Features/Trip/`, `Features/Settings/`, `Features/Deleted/`: reserved seams for later prompts.
- `Shared/Models/`: stable app, library, place, and repository DTO types.
- `Shared/UI/`: lightweight shared spacing and state-card UI.
- `SouvieShelfTests/`: focused unit tests.

## Coding Conventions
- Screens use `...Screen` when they represent routed or top-level SwiftUI surfaces, for example `LibraryScreen`, `MapScreen`, and `AddSouvenirScreen`.
- View models, when needed, use `...ViewModel` and should stay screen-scoped. Do not add view models where a live Core Data query and a focused service call are enough.
- Repositories use concrete names such as `SouvenirRepository`, `TripRepository`, and `LibraryRepository`.
- Services use concrete platform names such as `LibrarySharingService`, `PhotoImportService`, and `LocationLookupService`.
- Shared models and form state use explicit names such as `SouvenirDraft`, `TripDraft`, and `SouvenirMapAnnotation`.
- Prefer small focused types over large coordinators, inheritance hierarchies, or "base" abstractions.
- Avoid unnecessary protocols or indirection unless there is a real platform or testing seam.
- Favor compileable incremental work over broad refactors.

## CloudKit Caution
- Sharing code is high risk. When touching `NSPersistentCloudKitContainer` sharing or CloudKit private sharing flows, validate that owner-created objects made after a share already exists still behave as part of the single shared library.
- Do not regress shared-library behavior into owner-only objects, per-user libraries, or opt-in sharing paths.
- If an Apple API edge case is genuinely uncertain, document the uncertainty clearly in code comments and in the final task summary. Do not invent a backend workaround.

## Build And Test
Current repo state:
- The project builds as a simulator app from `SouvieShelf.xcodeproj`.

Validation commands:
- `git diff --check`
- `xcodebuild -project SouvieShelf.xcodeproj -scheme SouvieShelf -destination 'generic/platform=iOS Simulator' -derivedDataPath .deriveddata build CODE_SIGNING_ALLOWED=NO`
- `xcodebuild -project SouvieShelf.xcodeproj -scheme SouvieShelf -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -derivedDataPath .deriveddata test CODE_SIGNING_ALLOWED=NO`

If simulator runtimes change on this machine, update the explicit test destination immediately after confirming the new working device.

## Codex Task Workflow
- Read this file first, then any deeper `AGENTS.md` files that apply to the files you touch.
- Stay within the prompt scope. Do not redesign unrelated product or architecture.
- Add the smallest safe scaffolding needed when required pieces are missing.
- Run relevant validation after changes.
- Final responses must include: files changed, what was implemented, how it was verified, and blockers or TODOs.
- Prefer one well-scoped task at a time over giant multi-feature prompts.
