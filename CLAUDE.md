# How we work on InfDNA

The roadmap is the plan: https://claude.ai/artifact/Ed2J4qRfFKQ52b8TNLwwu5
(its database: collection `plan`, doc `meta/plan`).

- Follow the roadmap in order, one step at a time. Each finished step ships as a zip in `releases/`.
- A new request from the owner is not done on the spot. Add it to the roadmap as `status: "inbox"` (Your requests),
  slot it into a phase, and keep working on the current step, unless the owner says it is urgent.
- Only the owner's hand-drawn art goes on screen. If a picture doesn't work in the game, ask for a redraw
  instead of patching around it. Anything with no picture yet is left out and goes on the art list.
- Art requests (owner's rule): ask for each picture on its own, one picture per prompt, never a sheet of many, and make
  every prompt very detailed: the subject, its pose and view (side view), its size and proportions, materials and textures,
  colours, lighting, the outline style, what is left out, and how it will be used in the game.
- Keep the roadmap's statuses current (`doing` / `next` / `done` / `waiting` / `later`) as steps move.

## The game

- `game/` is the game: a standalone Godot 4.7 project (Compatibility renderer). `src/mods-unpacked/Judah-InfDNA/` is the old
  Brotato mod, kept only as a reference while the rebuild replaces it; don't add to it.
- `game/core/` is the colony simulation (no drawing), `game/art/` the owner's art (cut by `tools/art/`), `game/main.gd` the screen.
- Godot 4 shares packed arrays on assignment (Godot 3 copied them): write `x.duplicate()` whenever a copy is meant.
- Checks (Godot 4.7.2 binary, `--headless`):
  - compile everything: `godot --headless --path game --script res://tests/check.gd`
  - run colonies with no screen: `godot --headless --path game --script res://tests/sim_run.gd -- seeds=11,22 t=1800`
  - closing writes the report: `godot --headless --path game --script res://tests/close_test.gd`
  - screenshot: `xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --script res://tests/shot.gd -- out=/tmp/s.png`
- Build for the owner (Windows): `godot --headless --path game --export-release "Windows Desktop" ../build/InfDNA.exe`
  (needs the 4.7.2 Windows export templates in `~/.local/share/godot/export_templates/4.7.2.stable/`), then zip `InfDNA.exe`
  into `releases/`, commit and push it. The chat can't send files over 30 MiB and the game zip is ~60 MB, so give the owner the
  GitHub download link (`https://github.com/Ju12224/INFDNA/raw/<branch>/releases/<zip>`). The owner unzips it and double-clicks
  InfDNA.exe (Windows asks once: More info, Run anyway).
- Build hosting: GitHub refuses any single file over 100 MiB in the repo, so a build bigger than that ships as parts: zip `InfDNA.exe`,
  `split -n N --numeric-suffixes=1 -a 1` the zip into `releases/InfDNA_vX.Y.Z/InfDNA_vX.Y.Z.part1 ...` (each part well under 100 MiB), and
  put `JOIN_ME.bat` (CRLF; joins with `copy /b`, unzips with `tar -xf`, deletes the parts, starts the game) and a README.txt beside them
  (copy them from `releases/InfDNA_v0.6.1/` and change the name and the part list). Give the owner one raw link per file. No art compression
  and no left-out art: the owner wants the art exactly as drawn. The free build server (`.github/workflows/build-windows.yml`, triggered by
  changing `release_request.txt`) and Git LFS are both blocked while the owner's GitHub account has its billing lock, and other file hosts are
  blocked by this environment's network policy, so parts are the way for now.

