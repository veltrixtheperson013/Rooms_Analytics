# Applied and verified

Applied to Rooms Depth of the darkness dev server (place 138524255136204), Studio 14f20f82-207f-4a7e-8e20-ddef76ae4318, on 2026-09-12. Studio was returned to Edit mode. Seven source files were changed: TelemetryService, both movement modules, both kill modules, A-85's kill initializer, and A-200's initializer. Game assets, lighting, camera source, textures, effects, and existing backend configuration were preserved.

## Verification

- 12 Play/Server movement checks passed: bounded steps, direct movement, retry recovery, cancellation, wall obstruction, and Model support.
- 15 Play/Server attack checks passed using isolated player-service fixtures: exposed/hidden targets, wall obstruction, zero-distance rays, lethal attribution, dead targets, and respawn targeting.
- 6 isolated telemetry checks passed: visited-room count, revision, death totals, category breakdowns, duplicate death listeners, and opt-out. The cloned rig was explicitly transitioned to Dead to drive Died.
- All seven affected entity assets completed a roughly 38-stud route through a generated RightBasicIntersection room, finishing within four studs of the exit. Asset scripts and sounds were disabled in these movement-only clones.
- All seven jumpscare references resolve, including corrected A-85 -> a85jumpscar.
- Live TelemetryService reported LastUploadUtc=2026-09-12T21:14:37Z and UploadFailures=0. Shutdown reached the session-saving path; durable post-shutdown persistence was not separately read back.
- Eight isolated website HTTP tests passed.

Regression harnesses are in tests/ and are intended for Play/Server through Studio MCP, not ordinary game scripts. They clean up their fixtures. Attack tests replace only Players/ServerStorage service access in temporary copies of the real modules.

## Limits and deployment

This is a shared-module and initializer repair, not an exhaustive audit of standalone entity scripts. Full multiplayer chases, every rebound configuration, visible jumpscare animation, consent preference persistence, and published-server shutdown behavior have not all been exercised. The Play screenshot tool returned a black image, so no screenshot-based visual claim is made.

Existing archived/mismatched sound warnings and plugin warnings remain. The game changes are applied in Studio but not published. The website changes remain local in this repository; deploy them and set ROOMS_DASHBOARD_CODE to enable private access on the hosted site.
