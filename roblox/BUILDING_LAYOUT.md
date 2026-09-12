# Building layout

Applied to the confirmed Rooms dev Studio on 2026-09-12; not published. `RoomGeneration` uses Perlin-weighted template queue selection and `Room` applies the same bias during fallback selection. `Room/BuildingLayout` produces smoothly varying, seeded weights. Existing mini-section cycling, room connections, special-room lookup, furniture, lighting, and collision rejection remain in the original pipeline.

Straight rooms and corridors are preferred; turns form occasional changes of direction. Staircases are downweighted and separated by at least twelve room numbers. The existing early-room safety list now compares names without case sensitivity and also applies to fallback candidates. No room models or RoomInfo metadata were edited.

Optional attributes on `ServerScriptService.RoomGeneration`:

| Attribute | Default | Effect |
| --- | --- | --- |
| BuildingSeed | fresh random server seed | Reproduces the noise field; other existing random systems still affect the final layout. |
| BuildingNoiseScale | 18 | Rooms per broad noise interval, clamped to 6–80. |
| BuildingNoiseStrength | 0.8 | Bias from 0–1; zero disables noise weighting and the additional stair spacing. |

`Room.ActiveBuildingSeed` exposes the selected runtime seed. No client can choose it. Weights stay positive so the existing templates remain eligible when safe; this arranges prefabs and does not generate a complete architectural floor plan.

Validation: 208 Play/Server assertions passed, including deterministic same-seed noise, different-seed variation, adjacent-sample change below 0.12, corridor preference, stair spacing, and early-turn protection. Across the fixed 200-sample test, average multipliers were corridor 2.83, turn 0.83, stairs 0.39; these are weights, not guaranteed room frequencies. The actual generation pipeline advanced twenty rooms and had 21 generated/preloaded rooms with zero measured doorway gaps. All 17,245 room-template descendants retained the same geometry/appearance/source fingerprint after returning to Edit mode. These checks do not establish that every possible long-running layout is overlap-free.
