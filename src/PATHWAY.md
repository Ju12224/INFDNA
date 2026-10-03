# InfDNA upgrade pathway

Each milestone ships as its own Judah-InfDNA.zip + source zip. Items are grouped so one
milestone touches one system; anything that changes the economy comes after the balance
harness, so it can be measured instead of guessed.

## M1 - World & footing  (v0.10, this build)
- Truly infinite world both ways: the surface profile is generated outward on demand, the
  sim arrays grow in 64-column steps when units approach, terrain streams in chunks
  around the camera. Food, raids, trees and the nest blueprint still use the v0.9
  playfield (x 0..259) so balance numbers stay comparable.
- Footing: ants only stand on open cells touching dirt (floor, wall, ceiling) or on the
  ground-level rim over a shaft mouth. No walking through mid-air in rooms, no climbing
  the old world edge or the top of the sky. An ant that loses footing falls.
- Layer stack: sky -> 5 parallax layers (far peaks, near peaks, hills, forest, bushes;
  each moves and zooms less the farther it is) -> tunnel back wall (own parallax, drop
  shadow from the front dirt, lit side walls) -> room contents -> front dirt -> surface
  band -> props/food/queen -> ants.
- Dirt: strata (humus + roots, clay, sand/gravel, red clay + fossils, bedrock) with wavy
  seams, clods, grain, pebbles, bevelled tunnel rims.
- Surface: turf gradient, batched swaying grass, soft back edge, lit front lip, ant-hill
  mound that grows with the nest, contact shadows under every surface ant, caste
  badges fade out when zoomed out.

### M1 measured (2026-09-28)
- Footing audit (`tests/footing_audit.gd`, 660 sim-s with raids, seeds 11 + 44): 0 units seen in the
  sky; longest stretch without footing 2.55 s -> 0.55 s after `_footing_fix`; 0 units off footing > 2 s.
- Infinite check: units ranged x = -87..293 (playfield 0..259); terrain + 5 parallax layers rendered
  4,200 px past the playfield edge with no seam. Depth is still finite (150 rows, bedrock floor).
- Cost: world init 154 ms; growing the sim by one 64-column chunk ~25 ms.
- Balance A/B, old v0.9 vs this build, same 7 seeds, 20 sim-min, Balanced bot: 4/7 collapsed in BOTH
  (old: seeds 22, 44, 55, 66; new: 11, 33, 55, 77). Different seeds die because RNG draws shifted, so this
  says "no measurable change", not "no change". Survivors end tiny in both (old 80/9/53 ants, new 33/7/5).
  The raid 9-10 collapse is the known M3 problem and is untouched.
- Weak: distant peaks have no snowcaps (removed; they floated), ant-hill is decoration (ants walk
  under it at ground level), ants that wander outside the playfield find no food (piles/trees stay inside).


## M2 - Digging & the maze
- Organic tunnel growth: winding galleries, forks, loops that reconnect, dead-end scout
  tunnels, multiple nest levels, room shapes per purpose.
- Strata matter: sand digs fast, clay slow, bedrock not at all; stones and fossils block.
- Spoil: diggers carry pellets up and the mound grows from real dirt, not a formula.
- Two tunnel planes (front/back) that cross over and under each other, joined by holes;
  back-plane ants drawn dimmer and smaller. Nest may expand past the old playfield.

### M2 status (v0.12.0, lean build)
Built and compile-checked. Last measured before the lean switch (seed 44, raids on, 660 s):
126 ants, 17 rooms (5 back-plane), 0 stone/bedrock dug, 0 units off footing > 2 s, sim
50.4 vs 37.5 ms/sim-s (seed 11). Not measured after: spoil/back-room/economy/M4 changes.

## M3.5 - Scale (thousands visible, millions simulated)
- Half-rate ant brains with interpolated rendering (render extrapolates a.t), spatial
  hash for combat and food lookups, batched ant drawing.
- Past ~1,500 individuals: aggregate populations per task and region (counts, not
  agents) that spawn real ants near the camera and absorb them far away. The colony can
  then count in the millions while the screen shows the thousands nearest you.

## M3 - Balance harness + economy fix
- Measured v0.17: borers cut 20-min populations roughly in half or worse (see README).
- v0.18 borer pass (README table): lever 1 (count/start by colony size) mixed, 1 collapse;
  lever 2 (+ HP by colony size) kept: mean end pop 19 -> 44, 0/5 collapses, still under half
  of borers-off (97). Queen min HP stays 246-292/300, so borers are a weak queen threat.
- Next lever (not built): the defend response. A raider underground adds +0.5 defend to the
  whole colony; cap defenders per borer (e.g. 6 + 0.1 x ants) while queen HP >= 60%, then
  re-run the same 5 seeds. Run 40-min probes to judge the raid-12 target.
- Headless harness: fixed bot policies (Balanced, Forage-heavy, Defend-on-raid,
  Lab-greedy) x all 64 queens x N seeds, CSV out, detached runs.
- Fix the raid 8-12 starvation spiral (Defend no longer strips every forager, reserve
  foragers, raid-12 double-borer tuning), measured before/after on the harness.

## M4 - Ant anatomy & traits + visible evolution   (brief step 3)
- v0.12.0 did bodies + 8 heritable genes + Lab strains; v0.13 raider HP counter-evolution.
- v0.18.0: lineage view (trait-spread chart + ancestry strip, L key), sweep/extinction toasts.
- Still open: raiders that counter specific traits (armor -> piercing, thorns -> thick hide)
  instead of flat HP; screenshot pass on the lineage panel.
- Measured v0.18 (lever 2, 20 min): top plan holds 6-38% (median 11%), below the 30-55%
  target: colonies stay too diverse for plans to take over.
- More detailed bodies: waist/petiole, patterned gaster, compound eyes, elbowed
  antennae, tarsi, hair, colour patterns.
- New heritable traits with real trade-offs: wings, stinger, acid spray, big-headed
  majors, repletes, spines, glow, camouflage, pheromone strength. Bodies diverge.
- Lineage view that shows change over generations; raiders that counter-evolve.

### M4/M6 pull-forward (v0.13.0): fate & the black market
Hidden side effects, gambles, synergies, colony events, monoculture plague, raider
counter-evolution, first-organ milestones. Unmeasured; see Balance targets.

### Fish-tank pass (v0.15.0)
Done: upside-down fix, 1.6x bakes, living queen, 11 rooms/level + midden, particle
ambience, back-wall depth layers. Open: light-green stair dashes on the mound's slope
edge (seen in screenshots, source not yet found), caste badges crowd the main shaft at
mid zoom (consider default off in a watch mode), VRAM of 1.6x bakes (~1.3 MB per body
plan) unmeasured on a laptop GPU.
Done in v0.25: watch mode (`V`, auto-camera), day/night light, new-strain spotlight, ants no longer dither,
Fights layer lightened. Still open for watching: ants carrying food visibly down to granaries.

### Underground city (v0.16.0)
Done: 8 levels, workshops (armory, cistern, venom, sting battery, architects), outposts,
frontier food. Finding: room count is gated by population (colonies plateau at 40-80
ants under raids), not by the planner. A real city needs the M3 balance pass: bigger
sustainable colonies (cheaper brood late, raid pacing vs colony size), then more rooms.
Known: workshop count can overshoot PER_KIND by one (jobs in flight aren't counted).
Next city ideas: guard posts at outposts, food caravans between outposts and the core,
a throne room that upgrades the queen, workshops visibly staffed by ants.

### Balance findings (v0.26, balanced bot, 4-8 seeds x 25 min)
Before the fix, every seed survived 25 minutes but the population boomed and crashed (peak 130-170 ants at minute 8-10, trough of 3-30 around
minute 14-18, one seed in seven died). Chased through the economy ledger: income hit exactly zero for minutes while 40-80 foragers were
"out". Cause: a walking bug. Around a shaft the top row of soil is flagged nest ("under"); surface walkers preferred that row, so a forager
leaving an outpost mouth was treated as underground, sent back down, and shuffled in and out for ever (fixed in `_walk_surface`). After the
fix: no collapses, steady income, population grows to 170-220 and holds. Lesson: look at the ledger and at individual ants' states before
tuning numbers; the tuning experiments below (wider lifespan spread, 1.4x piles, scrap piles, lower frontier cap, laying limit) were all
chasing a bug and have been dropped. Kept as sound on their own: recruitment of foragers to piles nestmates already found, and the defender
cap by threat.
Late game (v0.27): raids now arrive in waves, scale with colony size and toughen quadratically after raid 8; the bot's colony is worn down from
about raid 17 and two of four seeds lost the queen by raid 27-38 (minute 41-45). Next to look at: how a human with no bot's perfect
purchases fares, and whether the first 15 minutes should be a little harder (raid 1-8 are currently never a threat).
Use `bal.gd` with MINS=25 and SEED=11,22,33,66,77,88;
results are deterministic per seed, so A/B a change on the same seeds.

## Balance targets (measure on the M3 harness; these are the pass/fail lines)
- Run length: Balanced bot reaches raid 12 in 40-60% of runs; no single collapse cause
  (starvation, queen kill, plague, siege) above 40% of losses.
- Food: stores above 25% of target at least 80% of the time outside raids.
- Evolution: top body plan holds 30-55% of the colony at 20 min. Plague hits under 20% of
  runs without Purebred Line, 50-80% with it.
- Raiders: counter-evolution multiplier median <= 1.5 at raid 12.
- Perf: <= 45 ms per sim-second at 150 ants.

## Lab design rules (the shop should be worth it, and able to ruin you)
- Every offer changes a decision. Flat +% items stay small; big swings carry a cost.
- Black market: the cost is hidden, real from purchase, revealed by time or a trigger.
  Target: buying one is net positive in only 40-60% of runs (a true gamble, not a trap).
- At least one hidden-upside item per tier so "???" isn't always bad.
- Synergies reward builds; some synergies carry their own cost (Titans, Blood Pact).
- Metrics per item on the harness: pick rate, win rate when owned, collapse rate when
  owned. Any item above 65% win-when-owned gets nerfed; any under 25% gets reworked.
- Done in v0.14: Lab rumors, Antidote, famine brood-eating.
- Next: a synergy + curse log in the HUD, items that react to colony events, sell-back.
- Famine gap: brood-eating needs eggs, and the queen stops laying when food is gone. Add
  a no-egg fallback (rationing: upkeep -40% while starving, at a speed cost).
- Bot finding: a player spending to ~25 food every Lab starves by raid 6-8. Consider a
  "reserve" warning on the Lab when a purchase leaves food under 1 minute of upkeep.

## M5 - Underground farming   (measured on the M3 harness)
- Leaf-cutter fungus: foragers cut leaves from trees, gardens grow in visible stages,
  mould outbreaks, gardener caste.
- Aphid ranching on roots (honeydew), seed granaries, honeypot repletes as living storage.

## M6 - Run structure + polish   (brief step 4)
- Run goals, queen unlocks, save/load; HUD pass at 1280x720 (v0.25: HUD scales below 1080p); surface life (day/night: done in v0.25, next: night raids, nocturnal prey).

### v0.29 notes (seasons, rival nest, anteater, heirlooms, gardens, sound)
- Seasons (`core/seasons.gd`): every number the sim and the views use for the year is one pure function of the colony clock, so nothing needs
  saving and a test can ask "what is winter doing at t = 1010". A season is 300 s, a year 1200 s; winters get colder (severity 0.55, 0.8, 1.0).
  The views rebuild their cached scenery a piece per frame when the season stage (year phase x 16) changes (stale-while-revalidate).
- Rival colony (`core/rival.gd`): pure data plus a step; the sim owns its raiders (every third raid, `_raid_rival`) and the strike party is
  the rally flag planted at its mound (`strike_t`), so the strike reuses the rally code. Guards are ordinary raiders with `guard_x` set.
- Anteater: a boss that is not in the raid roster (own timer, own hit points: 400 + 6.5 per ant). Lesson: anything that scales with `raid_n`
  becomes unkillable late, so a one-off boss needs its own scaling.
- Legacy (`core/legacy.gd`): one trait handed to the next founders, kept in `user://infdna_legacy.json`; optional and failure-proof.
- Gardens (`_step_gardens`): age gives growth (150 s to full), a timer picks a garden for mould, nurses per garden weed it out.
  Wanted next: leaf pieces carried down by ants, a gardener caste, aphids, and Brotato's own art (waiting for the file list).
- Sound (`content/colony/ambience.gd`): synthesised in `_process` into an `AudioStreamGenerator` on the "Sound" bus. Nobody has listened to it yet.

### Balance findings (v0.29, balanced bot, 8 seeds x 30-42 min)
First run of the full build: 3 of 8 colonies were down to 35 ants or fewer by minute 20 and never recovered, all starting as the first winter set in, none because of the winter's food alone.
Traces of single runs found the causes (the way the v0.26 walking bug was found): (1) the defend response counted every hostile anywhere, so a cave spider
still 450-650 cells away held 88 of 124 ants on guard and the larder went from 396 to 0 (now only hostiles within `ALERT_RANGE` = 240 cells of the entrance, or
underground, count); (2) with ~4-minute lifespans a pause in laying is lethal on its own, and winter pauses laying, so winter now slows ageing
(`Seasons.age_k`, down to half). Lessons: ants live 4-5 minutes, so the colony is a conveyor belt and any lasting stop in laying halves it;
raids are time-driven and sized by colony only down to 0.85x, so a colony that falls under ~70 ants around raid 10 cannot come back
(a softer floor on raid size for small colonies is the next lever if this turns out too harsh for a person).
Probe scripts: `bal8.gd` style (one TL row per sim-minute: ants, food, eggs, raid, hostiles, queen hp, tasks, deaths); for a collapse, print the enemy list and
the ledger every 5-10 sim-seconds around it.
Measured after these fixes (same 8 seeds): 30 min 8 of 8 alive (71-183 ants); 42 min five healthy, one overrun at minute 33 (raid 23), one lost its queen at minute 41, one at 23 ants;
zero starvation deaths in any run, and the first winter is a non-event for the bot (160-205 ants at its end, larders from 7 to 1314 food). If playtests find winters toothless,
raise `Seasons.severity` or cap the larder; if they find them brutal, soften the upkeep bump (`Seasons.upkeep_k`).

### v0.30 notes (the Wild)
- The unique direction is persistence with consequences: the colony you lose becomes the enemy you meet. `core/wild.gd` is the whole persistence layer (JSON file, genome
  to and from dict, species names, kin stat bands, `pick_ancestor`); `Rival` owns the kin genome (`evolve`, `kin_def`, `abilities`, `_reclaim`); the sim only spawns raiders from
  `kin_def` and runs `_kin_abilities`. `Sim.new(seed, queen, heirloom, kin)` takes the line as data, so the probes stay deterministic and never touch the file.
- Lesson: a colony's "champion" (the strain with the most ants at some moment) is usually just the founders' own plan, so it says nothing about what the colony became;
  the ancestor is picked by body strength and number of visible changes instead.
- Kin stat bands are deliberately narrow (x0.85-1.35, armor up to 0.25): the kin must be a sharper enemy, not an impossible one. Balance is only measured with the balanced bot
  (README v0.30.0); whether meeting your own ants is fun is the open question.
- Kin organ abilities (`_kin_abilities`) are a mirror of the player's: arc, pulse, lash, regen from tier 1 (the player's own come at tier 3). Silk, shell and the part forms are not
  mirrored yet.
