# Rescue Town Studio source snapshot — place version 211

This snapshot binds the current Roblox Studio script sources for Rescue Town to Git without replacing the Studio place.

- Place ID: `78904936179345`
- Expected root: `Workspace.PlayableGateV1`
- Studio place version: `211`
- MissionType at capture: `Random`
- Captured from Studio in Edit mode on 2026-09-16 UTC
- Exported BaseScripts outside ServerStorage: `18`
- ServerStorage backup/inspection scripts intentionally excluded: `156`
- Obvious secret/token indicator scan: `0`

`src/studio-current/` contains the current script set. `src/studio-archived-reference/` contains the two disabled legacy reference scripts that remain outside ServerStorage. The exact DataModel paths, SHA-256 hashes, byte lengths, and roles are recorded in `RESCUE_TOWN_STUDIO_SOURCE_MANIFEST_v211.json`.

This is a code recovery snapshot, not a full place backup. Terrain, models, binary assets, and the complete DataModel are not recoverable from these files alone. Do not use this tree to overwrite a newer Studio place without first comparing the live source hashes and place version.
