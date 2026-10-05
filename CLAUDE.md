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
- Build hosting: GitHub refuses files over 100 MB in the repo, so a zip in `releases/` must stay under 100 MB (`exclude_filter` in
  `game/export_presets.cfg` leaves out art nothing draws yet). `.github/workflows/build-windows.yml` builds the full game on GitHub's
  servers and publishes it as a Release file (no size limit) when `release_request.txt` changes (first line = release name, e.g. v0.6.1).
  It needs the owner's GitHub account to be free of its billing lock ("your account is locked due to a billing issue"); until then use
  the zip-in-repo way. Git LFS is blocked by the same lock.

