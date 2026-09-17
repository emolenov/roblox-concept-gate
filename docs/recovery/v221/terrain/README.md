# Rescue Town Terrain recovery — place v221

This directory contains the bounded Terrain recovery payload captured read-only from Roblox place `78904936179345` in Edit mode with `MissionType=Random`.

- `TERRAIN_VOXELS_V221_FULLBOX.jsonl.gz` contains all occupied `ReadVoxels(..., 4)` cells found inside cell bounds `[2303,2623) x [-126,32) x [-256,256)`: 155,120 occupied cells.
- `TERRAIN_VOXELS_V221_VERIFIED_MANIFEST.json` records hashes, occupied extents and materials. The decompressed payload is byte-identical to the independently captured v220 fullbox payload.
- `TERRAIN_EXTERIOR_SCAN_V221_RESULT.json` records a read-only scan of the complete 256-stud shell surrounding that fullbox; the shell contained zero occupied voxels.

`Terrain:CountCells()` is intentionally not used as an equality/completeness test because it reports a different metric than `ReadVoxels` occupancy. The evidence proves the captured cluster is self-contained within the tested 256-stud shell; it does not claim that arbitrary infinitely distant Terrain is impossible.

No Studio writes, Save, or Publish were performed while producing these artifacts.
