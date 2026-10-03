# InfDNA (Brotato mod) - v0.33.0

## v0.33.0 - look and feel: readable fights, grounded trees, real seasons, smoother everything
From the second playtest. The big items (a self-steering movement system, a faster sim, the zoom-into-the-grass view, the mutation score and the world-takeover arc) are next.
- **Fights you can see.** The rival's ants were drawn two to three times the size of yours (the plain red ants at 1x to 2.2x of a 75 px drawing next to a 35 px ant, and the kin at 1.15x of their class
  scale on top); they are now the size of yours, soldiers a little bigger. Hit sparks, dust and bursts are small and faint and are drawn UNDER the ants and raiders, not over them (a fight is dozens of hits a
  second). A raider that is fighting drifts to one shared depth lane (0.78) and the ants fighting it line up with it within a few percent, instead of standing in different lanes up to 115 px apart.
- **Orders and powers cost a little food.** Orders: 1 + 0.25 per ant to guard, 1.5 + 0.3 per ant to attack, 1 + 0.15 per ant to harvest, 2 + 0.4 per ant to dig, never more than 12. Powers: Rally 6, Harvest 4, Recall 3,
  Surge 5, Breed 10, Strike 12, scent flag 2 (on top of the Will). Nothing takes the larder under 5 food. The right-click menu shows the cost (f = food, w = Will) and greys out what the larder cannot pay.
- **Ants stand down by themselves.** A guard squad you are not looking at (off screen and not selected) for 30 s goes back to work; so does one that has seen no raider and no fight for 150 s, and one in a nearly empty
  larder. Harvesters and diggers finish their job and are freed as before. A toast says why.
- **Trees.** Trunks end in a rounded knot that divides into limbs (no flat cut at the top) and grow out of a mound of turf with root lumps (no flat cut at the foot, no dark plate under them). Branches are slim and fork into
  twigs that fork again, so a bare winter tree looks like a tree; the crown now thins from the outside in through autumn (finer steps, about every 19 s of the year) and is bare in winter. Fewer knot holes. A bug that
  drew leaf clusters over the canopy as dark discs is gone. Meshes bigger than 65k vertices are split instead of being silently cut.
- **Boulders** are angular, with lit and shaded planes, strata, forking cracks, speckle, lichen, moss, pebbles and blades of grass round the foot, and a snow cap in winter.
- **Weather moves in phases.** The sky clouds over for 30-45 s first (darker, more and bigger clouds, dimmer light), the rain then builds to its peak over about half a minute, thins out for 40-60 s, and the clouds
  clear slowly afterwards. Before, the rain went from nothing to full in six seconds.
- **Snow and grass.** Snow lies as long soft drifts that follow the ground across the whole width (the scattered white ovals are gone). Grass grows in meadow patches, thick here and thin there, spread evenly through
  the depth. The backdrop under the trees and hedge is no longer one flat colour: strips of turf, tufts, bushes, flowers (straw and drifts in winter, fallen leaves in autumn).
- **Creatures.** The grasshopper, the anteater and the butterfly were redrawn (the butterfly's wings were being cut off by a bad flap curve). Bees are about the size of an ant. The creature code has new helpers
  (`_poly`, `_bones`) for tapering limbs with joints.
- **Ants change layers slowly.** Going into the nest mouth or across to the back tunnel plane took a tenth of a second (a jump of up to 115 px); it takes about a second now.
- **Not verified:** none of it has been played in Brotato. Everything was checked in renders at 1920x1080 and with the headless tests (smoke, orders, invariants, fuzz, eight balance runs).

## v0.32.0 - view mode: the bare world, and everything done with select + right-click
Second playtest note: "the game shouldn't be a bunch of menus you click; it should be select an area, right-click, pick an option, like a view mode without all that stuff
blocking it."
- **The default screen is the world.** No panels, no colony card, no buttons. One thin translucent status line at the top left (day and season, food, queen, ants, seconds to the
  next raid or the raid itself in red, Will). A small "7 selected - right-click for orders" tag appears at the bottom only while ants are selected. Caste badges, the depth gauge on
  the right and the room labels are off in this mode (the nest panel, U, still opens).
- **The minimap and the speed / Lab / menu bar slide in at the edges.** Move the mouse to the top edge for the map, to the bottom edge for speed, Lab, Menu and Panels; they slide
  away again when the mouse moves off (with some slack so they do not flicker), and never while a drag is going on. Two faint words at the edges ("map", "speed - Lab - menu") and a
  three-line key hint say so for the first minute and then fade.
- **Right-click is the menu.** Right-click (no drag; right-drag still pans) opens a short list at the cursor. With ants selected it starts with what they can do about what is under
  the cursor: *Attack the spider* / *Harvest this pile (46 food)* / *Dig here* (or "Too hard to dig") / *Go here and guard* / *Guard here*, and *Free these ants* when some are under
  orders. Below that, always, the director's powers with their key and cost: *Rally here*, *Harvest this pile*, *Recall every ant*, *Surge*, *Breed from this ant*, *Strike the
  <rival>* (once the nest is found), *Scent flag here*; greyed out when recharging or short of Will. Click an option or press its number; click elsewhere or Esc closes it.
  **Shift + right-click** skips the menu and does the first order on it. The menu takes every click while it is open, so it never starts a drag-box or a camera move by accident.
  The power keys (R E Z J M Y B) still work for anyone who likes them.
- **Tab cycles three screens**: view (the default), standard (colony card, raid timer, minimap, speed bar: what v0.31 started with) and full (every panel). The Panels button does the
  same. Watch mode (V) is still the cinematic one.
- Startup toasts and key hints rewritten for the above. The smoke test now covers the menu (open, Esc, number key, Shift+right-click, picking an order and a power) and the three
  screens; the fuzz test drives the menu with random picks.
- **Not verified:** the menu and the edge reveal have not been used in Brotato with a real mouse. In my render the bare screen at 1920x1080 and the menu look right.

## v0.31.0 - you command the ants, a clean screen, and the first real playtest's bugs
The first playtest in Brotato reported: trees and objects floating or in the wrong place, a bird frozen in the air, too many menus, and "I should be able to select
areas and command ants, not just tap a button".
- **Drag to select, right-click to order.** Drag a box over ants (underground too) to select them (white rings; Shift adds, double-click takes every ant of that caste on
  screen, click an empty spot or Esc clears). Then **right-click**: on open ground = *guard* that spot (they walk there, hold it and go for anything that comes near);
  on a food pile = *harvest* it, trip after trip, until it is empty; on a raider = *attack* it, then guard where it fell; on soil = *dig* a tunnel toward that spot (a
  real planner job: the squad bores it, other diggers help, and the spoil is hauled out); on an open tunnel or chamber underground = *move* there. A plain right-click
  orders; right-drag still pans the camera. **Q** frees the selected ants (Free button too). Ants under an order wear a coloured ring (blue guard, red attack, gold
  harvest, brown dig). Orders cost nothing (the Will meter still pays for the colony-wide powers). They give way by themselves, and come back, while raiders are inside
  the nest, the queen is badly hurt or a Recall is running; carriers are skipped by orders that would make them drop their load; a flag (Rally, Strike) does not call
  ordered ants away; a finished order (pile empty, tunnel dug) frees its squad. A toast warns when the larder is nearly empty while ants are under orders.
- **A clean screen.** By default only the colony card (food, queen, ants), the raid timer, the minimap, speed, Lab and Menu are up, plus a bar for the selected ants.
  **Tab** (or the Panels button) brings back everything: body plans, powers, focus and brood, layers, the full colony card. The hint line is two short lines now.
- **Frozen things fixed.** Four views (the bird, the rally flag and harvest marker, falling leaves and petals, rain and snow) stopped redrawing when they went quiet, and a
  Godot canvas keeps its last drawing until it is told to redraw: the bird that left, the leaf that stopped falling and the raindrops of a finished shower all stayed
  painted on the screen. Each now draws one more (empty) frame. A bird hovering over its prey also wheels about now instead of hanging still.
- **Trees and rocks that follow the ground.** Cached scenery was built once and never checked again, so a spoil mound or an outpost shaft that changed the ground left it
  floating or buried. Each one now checks twice a second and is rebuilt (the old one drawn meanwhile) once it is more than 3 px off. I could not make the floating happen
  in my own tests (the headless check found no mismatch), so if you still see it, a screenshot would tell me which kind it is.
- **Ants trapped in pockets.** A gap in the rim of a big chamber can cut a pocket off from every tunnel; an ant standing in one never foraged, dug or fought again. In
  one test run six ants were found trapped in seven minutes (founders were even placed there). Ants in such a pocket are now carried to the nearest connected cell, and new
  founders are never placed in one.
- **Keys:** O was both "show goals" and "sound": the goals shadowed the sound key, so O never muted anything (the button did). Goals are I now. New: Tab, Q; Esc clears the
  selection first.
- **Robustness tooling** (`src/tests-v023/`): `invariants.gd` runs a long sim with a random player (orders, powers) and checks that nothing leaves the world or the soil, no
  NaN, no ant or raider stuck for no reason, a bird that moves, squads that refer to real orders; `orders_test.gd` covers every order; `fuzz.gd` now also throws random
  drag-boxes, right-clicks and releases at the scene; `layers_smoke.gd` covers box select, right-click, Q, Tab and the bird's last frame.
- **Not verified:** none of this has been played in Brotato (its own input handling, the drag-box and right-click on your mouse, the clean screen at your resolution).
  The headless checks pass and a render of the clean screen at 1920x1080 and 2560x1080 looks right.

## v0.30.0 - the Wild: the colony you lost is the enemy you meet next
**Why this direction.** Evolving ants and a shop between raids are not new: SuperColony (Steam) already has an ant colony, DNA to collect and roguelite runs, and Ants in
Space! mutates space ants. What I could not find anywhere is a game where **your own past runs become the world**. So that is where InfDNA goes from here: every strain you
breed well is a future enemy, and every colony you lose leaves something behind.
- **A fallen colony escapes into the Wild.** When a colony falls, the most evolved strain it ended with (its champion and the plans it had most of, scored by how strong the body
  is and how many visible changes lie behind it; the founders' own plan only as a last resort) is written into `user://infdna_wild.json` with a species name ("Thorned Harriers"),
  the queen it came from, and how far it got. The collapse screen tells you. The Wild keeps six lines; the weakest is forgotten.
- **Your next rival is its child.** The strongest line in the Wild is the rival nest of your next colony: your old ants, same body, same organs, same colours (the flag on the mound
  is their colour), drawn from the same baked sprites as yours with a red cast so you never mix them up. While you were away they evolved: three or more steps (more for a line that
  has already survived runs, and for a colony that went far), each step the strongest of three mutants. They take one more step before every raid of theirs. Their toast says whose
  descendants they are.
- **They fight with their bodies.** Their health and bite follow the body they evolved (x0.85 to x1.35), their speed too (x0.85 to x1.25), and a well-plated line shrugs off up to a
  quarter of an ant's bites. And their soldiers and majors **use the organs the line evolved, against you**: an electric organ throws bolts into one to three ants, a sonic organ sends
  a shockwave over everything close, a tongue lashes out and back, a regrowth organ heals them. (Your own ants only get these at the third tier of an organ; the Kin get a weaker
  version from the first, stronger with every tier.)
- **Break them (Strike, Y) and take their best trait back:** the next 12 eggs are bred from your champion strain with the Kin's most remarkable trait grafted on, and when the run ends
  that line is extinct for good. **Leave them alone** and that line goes on evolving in the Wild, a run older each time (it is your next rival again whenever it is still the strongest line there).
- Queen select shows the line your next rival descends from, with a switch (Wild: Off gives plain red ants, as before). The first colony ever, and any colony with the Wild off, meets the
  plain red ants of v0.29. The headless balance probes never touch the file.
- Code: `core/wild.gd` (file, genome to and from JSON, species names, kin stats), `core/rival.gd` (kin genome, evolution, `kin_def`, `abilities`, reclaim),
  `colony_sim._kin_abilities`, `enemy_view._draw_kin`, `rival_view`, collapse screen and queen select.
**Measured** (the balanced bot, the same 8 seeds, 30 sim-minutes; it knows nothing of the Wild): against plain red ants all 8 colonies live (71-183 ants at minute 30). Against the
descendants of a real colony's most evolved strain (a stinger, six legs) also all 8 (101-208 ants), so an ordinary descendant is not harder than the red ants. The worst case I could
build, an ancestor with four organs at tier 2 and a fusion: the first version, where every soldier used its organs, wiped out all 8 colonies (8-61 ants left) because each soldier's
shockwave hit every ant near it; now only the rare majors use them and a shockwave hits six ants, and 7 of 8 live (77-172 ants; one starved after a bad first winter). Probes are noisy,
so read these as rough counts.
**Not verified:** nobody has played this in Brotato; the Wild file has only been written and read by the headless tests, and I cannot tell whether meeting your own ants is a thrill
or a chore. If it is a chore, the first things to turn are `Rival.EVOLVE_BIAS`, the stat bands in `Wild.kin_mods`, and the number of starting steps in `Rival.setup`.

## v0.29.0 - a year of seasons, a rival nest, an anteater, heirlooms, living gardens, sound, and a graphics pass
Compile-checked; `src/tests-v023/layers_smoke.gd` passes (it now also covers items, seasons, heirlooms, the anteater, the rival and the
gardens); rendered headless under Xvfb (software GL) and fuzzed (random seasons, times of day, weather, watch mode); balance-probed
(8 seeds x 30 and 42 sim-minutes, see "Balance" below). NOT playtested in Brotato by a person (see "Not verified" at the end of this section).
New keys: **O** (sound on/off) and **Y** (send the strike party). The hint line at the bottom of the screen lists all of them.

### Seasons (`core/seasons.gd`)
A year is 20 minutes of colony time: five minutes each of spring, summer, autumn and winter, and a run starts at the start of spring. The
current season is in the header line under the title (day, season, generation, time of day); a toast announces each one and autumn ends with a minute's warning before winter.
| Season | wild food piles | richer piles | fruit trees drop | the colony eats | queen lays | raids | ants walk | what you see |
|---|---|---|---|---|---|---|---|---|
| Spring | x1.25 | | x0.8 | | x1.1 | | | thaw, blossom on the trees, flowers in the meadow |
| Summer | x1.0 | | x1.0 | | x1.0 | | | deep green, warm light |
| Autumn | x1.35 | x1.3 | x1.8 | | x0.95 | | | straw grass, leaves turn gold, orange and red and fall |
| Winter | x(1-0.92w) | | x(1-0.9w) | +30% w | -20% w | -35% w | -15% w | bare branches, snow on ground, bushes and rocks, snowfall |

`w` is how hard winter grips (0 to 1 over the season) times the winter's *severity*: the first winter is mild (0.55), the second 0.8, the
third and later ones 1.0. In winter the ants also huddle and **age at up to half speed** (without this a lean winter was a double cull:
the queen stops laying and every ant dies of old age four minutes later). Autumn is the glut; fill the larder. Living through a winter is
counted on the run summary and earns two run goals. The year changes everything you look at: the meadow, the trees (bud, blossom, turn,
shed, bare), the distant fields, forest, hedges and peaks, the sky tint and the light colour. A change of season never shows as a hitch:
the cached scenery is rebuilt a piece per frame in the background (the old look stays on screen until the new one is ready).

### The rival colony and the Strike command (`core/rival.gd`, `content/colony/rival_view.gd`)
A neighbouring nest of red ants sits on the open ground 80-110 cells from yours, east or west (a dark mound, its own hole and a flag, and a
few of its ants going about their business). **Every third raid is theirs**: the red raiders march out of their own mound, so you see them
coming, and a raid that breaks against you costs them strength. Their strength grows with time. Your foragers find the mound as they range
(a toast and a banner say where, and the minimap marks it). Then you can **Strike (Y, 35 Will, 75 s recharge)**: half the colony, soldiers
first, marches to the nest. Their guards pour out (2 to 8 red soldiers and twice as many red ants, more as they grow); with the guards down
the party storms the mound (its health bar is above it). If you win, the colony is broken for five minutes (no raids from it), you carry off
its stores (a good pile of food) and a mutagen, and its strength halves; it rebuilds afterwards. The party will not march out of a nest with
raiders inside or a hurt queen.

### The anteater (predator two)
From minute ten, and only once the colony has 70+ ants, a shaggy giant lumbers in from the edge of the meadow about every nine to twelve
minutes, sieges the entrance and licks one to three ants at a time off the ground in front of it (a long pink tongue; three at once only
when a crowd is packed in front of it). It is slow, bites weakly, and has a lot of health that grows with the colony (400 + 6.5 per ant). Rally
the soldiers to the entrance (R), Recall the foragers (Z); killing it pays food and a mutagen. Drawn procedurally: long snout, bushy tail,
the shoulder stripe, shuffling walk. (An earlier version scaled with the raid count, so a late anteater could not be killed at all; and its
first visit at minute eight cost a colony 15-45% of its ants. Both fixed.)

### Heirlooms: legacy between runs (`core/legacy.gd`)
When a colony falls, its champion body plan (the one that once outnumbered the others) can hand ONE trait down to the next queen: a
first-tier organ, a part form, an anatomy gene, an extra pair of legs, plating, spines, a little more size, an instinct nudge, or plain
"veteran stock" (+6% health and attack). The collapse screen offers the two most remarkable; the choice is kept in
`user://infdna_legacy.json`, **every founder ant of the next colony is born with it**, and the queen select screen shows it with a switch to turn it off.
If the file cannot be read or written the game simply has no heirloom.

### Fungus gardens that live (`world_view._draw_fungus`, `colony_sim._step_gardens`)
A garden is now drawn as a leafcutter-style comb (a bed of chewed pulp, a pale lumpy body with galleries, food bulbs, white threads) instead of
cartoon mushrooms. A new garden starts as a bed of pulp with threads and **matures over about 2.5 minutes** (a young one gives a quarter of
its food); now and then (every 3 to 6 minutes) **mould** gets into one: a warning sign over the nest, green fuzz creeping over the comb, up to
80% less food. Nurses weed it out, faster with more nurses per garden. New Lab item **Metapleural Glands** (the antibiotic glands real ants carry): mould is rarer
and weeded out faster (stacks twice).

### Director items: eleven new Lab items for the Will meter
Queen's Whisper, Deep Reserve, Pheromone Choir, Frugal Orders, War Standard, Honey Trail, Scarecrow (fewer, shorter bird visits), Adrenal Glands,
Stud Book, the legendary Hive Voice, and the black-market Puppet Strings (strong now, the ants eat more later). The Director panel shows
the effective cost and recharge of every command, and its tooltips say which items change it.

### Sound (`content/colony/ambience.gd`, key O)
No sound files needed: the ambience is synthesised sample by sample while it plays and mixed quietly into Brotato's own "Sound" bus (so the game's volume
settings apply). Wind over the meadow (stronger in winter and in rain), the hush of rain and snow, birdsong by day in the mild seasons,
crickets after dark, and a low murmur of earth with the odd drip once the camera is underground. O (or the Sound button in the layer row) mutes it.

### Graphics and animation pass
- **Soil**: strata now bend smoothly (no per-column stairs); round grains instead of square speckle; pebble layers no longer shear into streaks at layer borders;
  organic holes in the rear wall; stones keep one smooth tint (the "+" seams are gone).
- **Brood** shows egg, wriggling grub, then a silk cocoon that darkens and twitches before the ant hatches. Scent trails are a smooth ribbon with beads
  drifting toward the nest. The mound is shaded from the upper right, with clods.
- **Trees** sway in the wind (more in rain), with a rounder canopy, warm bark light, tidier moss and knots. Cloud shadows drift over the meadow, and puddles
  stay after rain and ripple while it falls.
- **Ground critters**: ladybirds, snails (out in the rain, leaving a slime trail), caterpillars and hopping grasshoppers.
- **Caste badges** keep a constant screen size and sit just above the head; the right-hand HUD panels clear the depth bar.
- **New creature art**: the anteater, the red ants (three sizes) and a rebuilt bird wing.
- **Fix:** the bird's wing polygon crossed itself in some poses, so Godot refused to draw it (a silent "triangulation failed"); found by a fuzz run with
  a validator that reports every polygon Godot rejects. It is now a guaranteed-simple outline and the fuzz runs clean.

### Balance: what the probe found, and what changed
The balanced bot (it buys sensibly but knows nothing of seasons, the Director or the rival) was run on 8 seeds for 30 sim-minutes, and
three colonies were down to 35 ants or fewer by minute 20 and never recovered, all starting just as the first winter set in. Chased through traces rather than by tuning numbers:
- **A far-away hostile locked the colony on guard.** A cave spider (a discovered cave can send one after your scouts) was still 450-650 cells out
  and walking home at 2.8 cells a second, but the colony answered it as if it were at the door: 88 of 124 ants stood guard for over a minute, the
  food runs stopped, the larder went from 396 to 0 and the colony could not recover. The defend response now only counts hostiles within 240 cells of the
  entrance or underground (the threat field only reaches 260 anyway); raids, bosses and the rival's guards all appear well inside that range, so
  nothing else changes. (`ALERT_RANGE`, `_alerts` in `colony_sim.gd`).
- **Winter was a double cull**, see the ageing note above.
- **The anteater** was retuned (see above).

**Measured after the fixes** (same 8 seeds, balanced bot): at 30 minutes, 8 of 8 colonies alive with 71-183 ants (before the fixes 5 of 8). At 42 minutes, five colonies healthy (89-226 ants), one overrun by raids at minute 33, one lost its queen at minute 41, one down to
23 ants at raid 26. **Nobody starved in any run**: the colonies that fell were overrun by raids (raids 23-28, 50+ raiders on the field), which is the late-game end
the raids were built for (v0.27). The first winter is a non-event for the bot (160-205 ants at its end), the second dented a few colonies and starved none. A bot keeps a
perfect larder; a person may not, and may find winters toothless or brutal, which is exactly what I cannot tell from here. Probes are noisy (changing any timer shifts
every random draw), so read these as rough counts, not guarantees.

### Not verified (what I could not test from here)
Nothing here has been played by a person in Brotato. Not checked: Brotato's own font and the HUD scaling inside Brotato's viewport, the item icons
for the new Lab items (they reuse icon names the mod already used), the frame rate on a real graphics card with the multiplying light and the extra
scenery, the sound (only the synthesis code was exercised, nobody has listened), and whether the pacing is fun. Fungus and aphid farming with
real Brotato art is still waiting for the list of Brotato's files (`tools/list_brotato_pck.py`); the gardens use procedural drawings for now.

## v0.28.0 - you direct the colony (Will, five commands, a bird)
The game was boring to just watch, so the player now has a permanent job. **Will** (the gold bar in the Director panel, right side) fills
by 1.5 per second (a full bar in about a minute) and buys commands, each with a cooldown. Keys act at the cursor; the buttons arm and
wait for a click on the ground (Esc or right-click cancels).
- **Rally (R, 30 Will):** plant a flag. About 45% of the colony (soldiers first, never an ant carrying food) walks to it and holds it for
  25 s, and ants within 16 cells bite 35% harder. It will not pull the colony out of a nest with raiders inside or a hurt queen (an early test
  that did lost the queen at raid 3). Use it where a raid is coming from: raids now arrive in waves.
- **Harvest (E, 20 Will):** put the cursor over a food pile; for 60 s most foragers setting out go there, up to 60 already outside are
  redirected, and they carry 30% more.
- **Recall (Z, 15 Will):** everyone outside runs for home and stays in for 12 s, and while they run they are in cover (drawn faded): the bird
  cannot pick them out.
- **Surge (J, 25 Will):** surface ants run 45% faster for 10 s.
- **Breed (M, 40 Will):** the next 8 eggs come from the selected ant, each mutated (or mutate hard if none is selected). With the new-strain
  spotlight (`N`) this is the evolution lever: look at the new strain, then breed from it.
- **Brood caste order** (Mixed / Workers / Soldiers, in the Director panel): what the queen's brood leans toward.
- **Orders on the map:** the rally flag (pole, waving banner, a ring showing the bonus reach and a shrinking arc for the time left), a bobbing
  arrow over the harvested pile, and markers on the minimap.
- **The bird (first predator):** now and then a bird hunts the foragers far from the nest: it stoops toward the nearest ant on the open
  ground and picks one off every ~3.6 s (two when they bunch up), for about 30 s (shorter against a small colony). The banner says where,
  the minimap blinks a red mark, and it leaves the moment nothing is left outside, so Recall ends the hunt at once. Left alone it kills
  ~15 ants a visit, every ~4 minutes. Procedural art (`creature_art.bird`), shadow and stoop (`predator_view.gd`).
- Measured with a deliberately crude bot that casts these on a timer (not a good player): it lasts longer than the same colony left alone
  (queens alive at minute 50 where the undirected ones fell at minute 41-45) but its population crashes earlier, because it rallies at every
  cooldown and starves the food runs. A person who uses the commands sparingly should do better. Next: rival colonies and more predators
  (`src/IDEAS.md`).

## v0.27.0 - late raids that can actually end a run
After the walking fix the balanced bot's colony sat at ~180 ants with a full-health queen through raid 26 (40 minutes): nothing late
could hurt it. Why: a raid's budget was large (raid 15 = 71 raiders) but they spawned one every 0.9 s and were killed one by one as they
trickled in, never more than ~15 on the field. Changes (all in `colony_sim.gd`, constants `RAID_*` at the top):
- **Raiders arrive in waves** (raids of more than 10 raiders): about five waves, 7 s apart, each walking in together and fought as a mass.
  Small raids keep the old trickle so early raids stay gentle.
- **Raid size follows the colony:** budget x (colony size / 90, clamped 0.85-1.7), and x (1 + 0.09 per raid after the sixth).
- **Late toughening:** raider HP and bite gain a quadratic term after raid 8 (`RAID_HP_LATE`, `RAID_BITE_LATE`).
Measured with the balanced bot, 4 seeds up to 48 minutes: unchanged until about raid 17 (minute 27); then peak hostiles rise to 25-50 and
the colony is worn down. Two of four seeds lost their queen (raid 27 at ~41 min, raid 38 at ~45 min), two were still alive at 48 minutes
(raid 33, 91-133 ants). A human who buys less carefully than the bot will fall sooner. Tune with `RAID_LATE`, `RAID_HP_LATE`.


## v0.26.1 - watch mode, calmer ants and raiders, day/night and rain, recruitment, strain spotlight, run summary
Compile-checked, rendered headless under Xvfb (software GL), fuzzed 8 sim-minutes with watch mode and random time of day (no
script errors), balance-probed (8 seeds x 25 min: all survive), `src/tests-v023/layers_smoke.gd` all pass;
NOT playtested in Brotato.
- **Watch mode (`V`, or Esc to leave).** Hides the HUD panels, the nest gauge and the busy layers (badges, tasks, health, follow) and
  leaves a one-line status (`88 ants - gen 5 - night - raid 1`) plus any toasts. `watch_cam.gd` is a slow self-directing camera that
  cuts between shots: a fight at the nest (always wins), a new strain, the farthest forager on its expedition, the traffic at the
  hole, a single ant, a digger underground, the queen's chamber. Any pan key, wheel, drag, jump key or click on an ant hands the camera
  back for ~6 s (a click follows that ant). Leaving restores every layer and panel exactly as they were. The Lab never pauses the
  colony while you watch: it waits (with a toast) until you leave watch mode.
- **Ants stopped looking weird (the "dithering" fix).** Measured on the sim: foragers reversed direction on almost every hop (hops are
  1/18 s), which showed as constant squash-turns. Causes fixed: re-deciding at the edge of the danger zone in front of a raider (now
  they run for 10 hops), a coin-flip turn per hop during the area search (now short sweeps), stepping back and forth on top of prey (now
  they stand and fight), and facing flipping on vertical steps up the mound and at the shaft mouth (now left/right follows the screen on
  open ground). Rapid direction flips per 5 sim-minutes: 3416 -> 455. Surface ants also tilt to a smoothed hill slope instead of the
  6 px stair steps of the grid (big rotation jumps 10392 -> 757).
- **The late-game collapse was a walking bug, now fixed.** Diagnosis from the balance probe: from about minute 9 the colony's income
  dropped to exactly zero for minutes while 40-80 foragers were "out", the population swung 165 -> 3 and one seed in seven died. The foragers
  were stuck at the mouths of the outpost shafts: around a shaft the top row of soil is flagged as nest ("under"), surface walkers preferred
  that row because it hugs the ground, an ant standing on it was treated as underground and sent back down the way out, and so it shuffled
  in and out of the mouth for ever. Surface walking now keeps to the open-air row (and only uses a nest-flagged cell if nothing else leads on).
  A forager standing in the mouth itself now steps out along its heading instead of a random neighbour (forager direction flips per
  5 sim-minutes: ~1200 -> ~50 after the first fix exposed it). Result, 4 seeds x 25 minutes: no collapses and no crashes, income flows, and the colony grows to a steady 170-220 ants (before: peaks
  of 120-170 followed by troughs of 3-30). This also removes much of the "ants shuffling at the hole" look.
- **Recruitment to known piles:** foragers setting out are often told about a pile a nestmate already found and that still holds food (nearer
  ones likelier), so the food frontier cannot outrun what a young forager's own search radius covers.
- **Defender cap by threat:** non-soldiers stop leaving the food runs for a raid once ~6 + 5 per threat point are already defending (a raid of
  7 small raiders used to pull 92 of 166 ants off the food, and into a blob).
- **Raiders stopped shivering too.** Small raiders and siegers used to flip toward whichever ant was nearest every hop (runners weave
  past them at 18 cells/s). They now keep chasing the same ant for ~12 hops, stand and fight when it is within a cell, and reverse at most
  every 5 hops; fleeing prey does the same. Rapid raider direction flips per 10 sim-minutes: 110 -> ~0 for small raiders, 14 -> 0 for brutes.
- **Run summary** on the collapse screen (time survived, raids, peak ants, generation, farthest forager, kills, food hauled, last dominant
  body plan) and a best run per queen kept in `user://infdna_runs.json`.
- **Lanes without shimmer.** An ant's drawn lane is smoothed over time (the sim's per-hop lane jitter never shows) and pulled onto the
  nest mouth's lane near the hole and the pile's lane at food, so nobody reaches into the hole from a different depth; fighters converge
  on their raider's lane faster. Big boulders no longer stand beside the nest and sit toward the back lanes (so does every giant tree),
  so a fight is never hidden behind a rock.
- **Lighter Fights layer:** thin ground rings under raiders (a faint one for wandering small ones, a soft pulse for those fighting), no
  lines between bodies, and a small health bar only on a fighter that is hurt.
- **Day and night (`day_cycle.gd`, `light_view.gd`).** A 7-minute day driven by the colony clock: warm sunrise and sunset, moonlit blue
  night (dark but readable), sun and moon arcs, stars, a glowing nest mouth and fireflies after dark, shadows fade with the sun, the
  HUD shows Dawn/Sunny/Dusk/Night (the Night layer, `K`, keeps it midday). One multiply-blend pass lights everything above the ground line, so the tunnels keep their own warm
  light and the cost is a few polygons (GLES2 ignores `draw_mesh`'s modulate for vertex-coloured meshes, so a per-mesh tint was not
  possible). Purely visual.
- **Rain** (`weather_view.gd`, sim `_step_weather`): every few minutes it rains for 35-70 s. The light turns grey-blue, streaks fall to the
  ground and splash on it, the bees and butterflies shelter, and the scent trails wash away about 4x faster (foragers fall back on route
  memory, the colony has to re-lay its roads). Toasts announce it. The HUD subtitle and watch-mode status say "Rain".
- **New-strain spotlight.** A body plan the colony has never had (new limb count, ability or organ) is announced with a toast; `N` jumps
  the camera to the first ant wearing it, and watch mode cuts to it by itself.
- **HUD scales down below 1080p** (the layout is built for 1920x1080) instead of overlapping at 1280x720.
- Not checked in the real game: everything above in real Brotato (fonts, GPU frame rate, HUD scaling inside Brotato's own viewport
  stretch), how the multiply-blend light looks on every GPU.

## v0.24.0 - optimizer, real walking, better trees, a layered nest, exploration
Compile-checked, rendered headless under Xvfb (software GL), fuzzed (raids with the new creatures, optimizer tier changes,
nest panel, deep-underground camera, world-spanning jumps: no script errors), balance-probed; NOT playtested in Brotato.
- **The optimizer (`perf.gd`, Quality button in the Layers panel, fps readout on the minimap).** Auto watches the real frame time:
  under ~42 fps for 1.5 s it drops a tier, and after 25 smooth seconds it tries a step back up (and backs off for two minutes if the
  step up did not hold). Tiers drop the costliest detail first: far backdrop layers, clouds, birds, sun rays, pollen; unit shadows
  (full -> one ellipse -> none); half then none of the ground clutter; pose animation and dust; combat effects per frame; the sim's
  per-frame time budget; sprite-bake batch size; and a cheaper terrain shader (2 noise octaves, no rear-wall cracks). Click it to lock
  High / Medium / Low. Measured headless, 102 ants: ground band 12 ms -> 0.06 ms, backdrop 2.7 ms -> 0.8 ms, draw script total
  4.9 ms (High) -> 3.0 ms (Minimal). Also: ants off screen skip their animation state, badges are not computed once faded out,
  and ants that are tiny on screen skip pose animation and shadows.
- **Ant walking rebuilt.** The legs barely moved (about 1.4 px of swing while the ant covered 100 px/s), so the feet skated. Now each
  foot has a planted stance and a lifted swing, the knee is solved from the real femur and tibia lengths, the stride is bigger,
  and the walk cycle advances by the distance actually walked (so feet stay planted at any speed). Ants turn around with a quick
  squash instead of snapping, and the trunk, gaster and head each move on their own beat.
- **Trees redrawn:** flared trunk in five shaded bands with bark grooves, knots and moss, thick branches with twigs, a wide
  canopy of ~40 round shaded leaf clusters with leaf flecks, a scalloped edge and fruit. The backdrop no longer loses its far
  chunks when zoomed far out (a scaled `draw_mesh` transform got clipped; layers now use `draw_set_transform`).
- **Layered nest (`nest_decor.gd` + shader):** between the rear wall and the front dirt, so it shows only inside open tunnels: hanging
  roots, dirt drips, pebbles, crumbs, glowing fungus, and light shafts falling down each entrance. The rear wall and the deeper crack
  layer now slide about twice as much against the foreground when you pan, deep tunnels get a warm light pool, the back-plane tunnels
  are deeper, and the blocky soil speckle is finer.
- **From your v0.22 files:** `underground_ui.gd` (depth gauge, nest panel `U`, room labels, `PgUp`/`PgDn` between nest levels, `Q` queen,
  `Home` surface, deep vignette) and, in the sky, ants marching along the farmland and hedge ridges plus drifting pollen.
- **Ambient wildlife (`ambient_view.gd`):** bees working the flower patches and butterflies drifting through the meadow, with ground
  shadows; hidden when zoomed far out or on a low quality tier. Tree branches are now drawn behind the trunk so they grow out of its sides.
- **Exploration:** giant trees, caves and cliff vistas are landmarks. An ant that walks up to one discovers it: trees pay food and
  fruit, caves hold a food hoard plus mutagen (and about half the time a spider that follows your scouts home), vistas pay a little.
  They show on the minimap (faint dots until found). New goals: Explorer (3 landmarks), Cave diver, Deep roots (generation 10),
  Epic haul (800+ cells), Cartographer (8 landmarks); "Far haul" is now 400+ cells.
- Not checked in the real game: HUD placement of the new minimap, Quality button and underground gauge together, real-GPU frame rate,
  whether the tier thresholds suit your machine.

## v0.23.0 - a living world: deep ground, giant trees, creatures, far expeditions, bolder evolution
Compile-checked, rendered headless under Xvfb (software GL), balance-probed on 4-6 seeds and fuzzed for 8 sim-minutes (raids with the
new creatures, flight, random camera/minimap/layer input: no script errors); NOT playtested in Brotato.
- **Startup fix (ant_view.gd):** two bare `randf_range(...)` calls (Godot 4 only) stopped the colony scene from compiling in Godot 3.5.
- **Ground and backdrop rebuilt as cached meshes** (`mesh_kit.gd`, `ground_view.gd`, `sky_layers.gd`). The old per-frame
  ground band cost 12-20 ms; static scenery is now built once per 48-column chunk and drawn with a few `draw_mesh` calls.
  - **Many walking lanes:** the walkable band is 128 px deep (was 46) with nine visible turf rows, lane perspective
    (back ants smaller and hazier) and 14 lane slices plus a foreground slice. Scenery is interleaved with the units, so an ant
    in a back lane walks behind a flower and one in a front lane walks in front of it; tall foreground grass covers every ant.
  - **Scenery:** tufts, flowers, clover, pebbles, mushrooms, berry bushes, ferns, leaf litter, soft baked shadows, wind sway.
  - **Natural landmarks** (`core/world_features.gd`, deterministic along the endless surface): giant trees (trunks 150-260 px,
    up to 1900 px tall, roots, branches, three-tone canopy, fruit), boulders with moss and cracks, cliffs with cave mouths.
    Cliffs never wall in the start. The camera can zoom out ~1.7x further and look much higher to see them.
  - **Backdrop:** 7 parallax layers (faceted snowy peaks, ridge with pines, farmland with barns and a windmill, pine forest,
    leafy forest with trunks, hedge with berries), three cloud depths, birds, slow sun rays.
- **Shadows:** a per-unit shadow pass before the units (soft, leans away from the sun, tilts with the slope, shrinks and stays on
  the ground when an ant flies). The shadow baked into every ant sprite by the painter is gone (it tilted with the ant and doubled up).
- **Click picking** now uses where an ant is drawn (lanes lift ants up to 115 px off their sim position).
- **Flying ants:** winged ants lift off over open ground with beating wings and land at the pile or the nest.
- **Spiders, bees, hornets** (`creature_art.gd`, procedural, animated: gait, wing blur, hover): `spider` is a brute, `bee` a small
  runner, `hornet` an elite; they join the raid rosters. Flyers hover above the ground on the surface and walk in tunnels.
- **Walk animation:** the whole body moves (thorax bob per step, gaster counter-swing, head nod), 6 baked frames (was 4), and
  the leg cycle is driven by the ant's real ground speed so legs no longer skate.
- **Expeditions:** ants run 3.0x faster over open ground (`SURFACE_K`), `RANGE_MAX` 520 -> 1500 cells, the food frontier moves out as the
  colony grows (`_pile_distance`), search radius grows faster, scouts range further, and far loads are worth up to 2.2x (so the
  walk pays). The giant trees are the fruit sources (`_sync_trees`), a few near oases that a big colony outgrows.
  A **world minimap** (top centre) shows nest, piles, trees, ants, raiders and your view; click or drag it to jump along the world.
  `X` follows the selected ant. Balance probe, 12 min, seeds 11/22/33/66: final pop 74/47/116/62 (mean 75) vs 97/43/47/118 (mean 76)
  before. Seed 22 at 8 min: ants reach ~530 cells (3,200 px) and ~310 food-units come from beyond 400 cells (none before).
  New food only appears beyond a minimum distance that grows with time and colony size (`_pile_distance`).
- **Evolution:** mutation chance 0.35 -> 0.55, double mutation 0.25 -> 0.4, bolder size/colour steps, 15 colours (was 7), rare
  macro-mutations (6%: three changes at once), per-generation hue and size drift, and **directed adaptation**: a repelled raid
  breeds eight hardier soldiers (armor, spikes, claws), a far expedition breeds eight long-legged scouts. Before/after lineups
  of 10 min runs: the old colony is almost all one brown ant; the new one shows blue and purple lines, stingers, horns, wings,
  and body-plan changes.
- **View layers** (previous round): `Fights` (F), `Tasks` (T), `Health` (H), `Trails` (P), `Badges` (C), `Follow` (X) in the bottom Layers panel.
- Not checked in the real game: HUD placement (minimap top centre, Layers panel above the bar), how the new scenery reads next to
  Brotato's own UI, frame rate on a real GPU, balance beyond the probed seeds, raids with the new creatures.

## v0.22.0 - speed, long-range foraging, a play layer (compile-checked + 10 sim-minute smoke run; NOT playtested, NOT A/B measured)
- **Speed bug fixed (core/colony_sim.gd `_step_ant`, `_step_enemy`):** the leftover distance of a hop was thrown away on
  arrival, so ants walked at 5.55 / 4.75 / 4.50 cells/s at 1x-frame / 0.05 / 0.1 s steps (nominal 6.10). The overshoot now
  carries into the next hop (measured 5.55-5.65 at every step size), and the egg timer keeps its remainder. The game plays
  the same at 1x, 4x and 10x. Side effect: ants are ~2% (1x) to ~18% (4x) faster than in v0.21, so v0.21 CSVs are not comparable.
- **Lag at 4x / 10x:**
  - colony_scene.gd: stepping moved to `_process` with a 9 ms/frame sim budget (`BUDGET_US`). A slow frame no longer makes
    the engine run extra ticks; the frame rate holds and the effective speed bends. The speed button shows `~7.3x` when the
    sim can't keep up. Above 4x the sim step is 0.1 s (`FAST_STEP`). New 10x button; keys 1-4 set 1x/2x/4x/10x.
  - Sim: neighbour/field/wall lookups inlined, combat precomputes ant positions once per tick (was per raider x ant pair),
    BFS rewritten with flat offsets (same distances), threat BFS every 0.7 s and capped at 260 steps, trail decay only over
    the active trail range every 0.5 s. Pure refactors were bit-identical on seed 11 (8 min) and ~10% faster; then 36 ms
    per sim-s at ~80 ants in the smoke run (v0.21: 42-57).
  - Render (unmeasured, code reading only): ant_view skips units outside the camera (+360 px) and draws depth order from 36
    buckets instead of a GDScript sort every frame; sprite_baker bakes one body plan per frame (BATCH 16 -> 4) because
    mutation, and so new bakes, scale with sim speed.
- **Foraging like real ants (colony_sim.gd `_forage`, `_search`, `_start_trip`):**
  - Route memory: an ant that loaded from a pile goes straight back to it; if it is gone it circles the spot (area-restricted
    search), then scouts.
  - Trails: returning ants lay scent, stronger for richer piles; trails last (`PHER_TAU` 50 s, was 20) so long routes survive;
    outbound ants follow a trail away from the nest, run up to 25% faster on it (`TRAIL_BOOST`), and keep to lanes (laden ants
    on one side).
  - Scouts and recruits: ~15% of departures strike out alone with a long-tailed search radius (150..520 cells); the rest follow
    the stronger trail side or their site. Scouting is persistent legs (mean 70 cells), not the old 45-cell turnback.
  - Search radius starts at 90 cells and grows x1.45 after each empty trip; trip time limit scales with it (was fixed 100 s);
    range is trimmed by remaining lifespan so old ants stay close.
  - Food ecology (`_pile_distance`): half the piles 22-140 cells out, a third 140-300, the rest 300-480 (richer with distance).
    Up to 7 piles + 1 per 60 ants. The world is pre-grown to nest +- 520 cells (about 2 s at colony start; growing it
    mid-game cost 1.6 s per step). `city.frontier_*` is now unused.
  - Smoke run, seed 11: peak 129 ants at 8 min (v0.21 seed 11: 87-95), first hauls from 250+ cells at 10 min.
- **Raid 9-10 crash (tuning from one diagnosed seed; NOT measured across seeds):** the colony was already shrinking from
  ~10 min because old-age deaths outran births (egg reserve scaled with colony size, so laying stalled near 54 food), 49 of
  55 ants were on Defend during a raid, and raid 8's boss hit with food at 5. Changes: lay reserve size term capped at 60 ants;
  foragers/diggers answer the defend call at 55% unless raiders are inside or the queen is under 60% (soldiers unchanged);
  forager reserve 20% -> 30%; raider HP growth 12% -> 9.5% per raid and damage 8% -> 6.5%; at most 1 elite per raid before
  raid 12 (2 after). If raids 9-10 still wipe colonies, the first knobs are `elite_cap`, the 0.55 defend factor and `reserve`.
- **Ant animation (ant_view.gd `_apply_pose`, `_draw_corpses`; untested in game):** procedural poses on top of the baked walk
  cycle, so every body plan gets them: soldiers face and lunge at the raider they fight, defenders with no target rear up,
  diggers jackhammer against their wall and fling crumbs in arcs, nurses rock over the brood, idle ants breathe and groom now
  and then, a double nod when an ant grabs food and a hop of joy when it delivers, foragers flinch near raiders, laden ants
  lean and bob harder, newborns wobble, hurt ants stagger back, running ants kick up dust, and dying ants are knocked up,
  tip over and fade (old age: a quiet curl). Death effects are `fx` kind `corpse` emitted from `colony_sim.kill`.
- **Play layer:**
  - Goals (O shows the next three): 9 milestones paying food and mutagen; toasts + banner on completion.
  - Scent beacon (B at the cursor): foragers leaving the nest are drawn to it and search around it; 2 at a time, 90 s,
    25 s recharge. Direct your colony toward a jackpot.
  - Mutagen (G with an ant selected): the queen breeds the next 8 eggs from that ant, each mutated. +1 mutagen every second
    raid repelled and from goals (max 3). This is the "god influences the genome" lever.
  - Jackpots: every 140-220 s a huge windfall (300-480 cells out, drawn with a gold glow) with a banner. Discovery
    toasts ("A scout found a 140-food pile 380 cells west") for piles 250+ out.
- Harness: tests-v022/ has `bal.gd` (rebuilt headless balance probe; Balanced bot, CSV rows), `compile.gd` (all scripts; the
  two Brotato-dependent ones fail by design outside the game), `smoke.gd`, `run_seeds.sh`.
- Not checked: in-game look and feel of every view change, HUD fit of the 10x button at 1280x720, load time on your machine,
  the 10-seed A/B for the new economy and the crash fixes, whether far foraging is too timid or too costly for your taste.

## v0.21.0 - animal organ lines + fusions (compile, contact sheet, fuzz, live ability run, 10-seed A/B; not playtested)
- Six organ lines borrowed from across the animal kingdom (`genome.organs`, line -> tier 0..3, missing = 0, so
  older genomes load unchanged). Tiers are cumulative and drawn cumulatively, so an ant carries its lineage.

  | Line | Tier 1 | Tier 2 | Tier 3 (live ability) |
  |---|---|---|---|
  | Sound | cricket stridulator: fighting ants rally neighbours within 4 cells (+15% attack) | bat echo horns: sense +6, rally +25% | pistol-shrimp sonic cannon: 6 dmg shockwave, 3.5 cells, every 4 s |
  | Electric | platypus electroreceptors: sense +4 | eel electric organ: thorns +0.9 | torpedo-ray arc: 5 dmg chain to 3 raiders within 5 cells, every 5 s |
  | Shell | turtle scutes: armor +6% | snail shell: hp +10, armor +4% | armadillo roll: below 40% hp, curl 3 s taking 30% damage (cd 10 s) |
  | Silk | spinnerets: carry +0.8 | orb-weaver web: raiders fighting it move at 55% | bolas snare: stun a raider within 4 cells for 2 s (bosses 0.8 s), every 6 s |
  | Tongue | anteater lapping: carry +1, attack +0.2 | frog sticky tongue: bite reach x1.6 | chameleon ballistic tongue: 7 dmg shot, 6 cells, every 3 s |
  | Regrowth | starfish: heal 0.4 hp/s | axolotl gills: heal 1.2 hp/s, life +30 s | planarian: 30% chance a killed ant splits into an egg |

  Costs per tier (cumulative): upkeep on every tier, plus speed (shell, sound 3, tongue 3, gills), hp (ears),
  life (arc), tunnel penalty (shell 2), dig (shell 3, tongue 1), attack (snare). Full numbers in phenotype.gd.
- Four fusions emerge when two lines both reach tier 2 (computed from the genome, always traceable):
  Thunderclap (sound + electric: shockwave x1.5 and arcs to every target), Silk slingshot (silk + tongue: tongue
  range x1.6, shot stuns 1 s), Living fortress (shell + regrowth: curl heals 4 hp/s, cd 7 s), Sonar web
  (sound + silk: sense +6, +30% damage on slowed or snared raiders). Lineage notes "fused into X"; the colony
  gets a toast naming both parent lines the first time a fusion appears.
- Mutation: new `organ` op, weight 12. Lines climb one tier at a time (up 62%, down 20% once started), and a
  started line is favoured. Six Lab strains push a line: Cricket Song, Eel Strain, Shell Strain, Silk Strain,
  Frog Tongue, Axolotl Strain (icons reuse ones the mod already loads).
- Sim (colony_sim.gd): `_step_abilities` after combat; rally precompute; per-ant reach; web slow, snare stun
  (stunned raiders take hits but do not bite or move), curl damage cut, planarian split in `_ant_falls`.
  Ability damage scales with the raid like the Lab zap. Abilities hit raiders only, never prey.
- View: shockwave rings, chain lightning, tongue/silk lines, snare nets (enemy_view.gd); curled ants draw as a
  rolling banded ball; snared raiders wrapped in silk, webbed raiders trail strands. Inspector shows an
  Abilities line. Lineage chart: 7 new traits (6 lines + Fused abilities).
- Tuning knob: `Phenotype.ORGAN_UPKEEP_K` (1.0 = measured config).
- Checked:
  - compile.gd ok.
  - tests-v021/organs_sheet.gd: all 18 tiers, 4 fusions, 2 stacked worst cases inside the 170x136 sprite.
  - tests-v021/form_fuzz.gd: 20,000 mutations, every tier and fusion reached, 1,843 organ/fusion notes, no errors.
  - tests-v021/ability_check.gd seed 11, 12 min, half the colony given every tier 3: 97 arcs, 80 shots,
    27 shockwaves, 20 snares, 1 curl; combat deaths 18 -> 5; sim time +7%.
  - Natural evolution before the drive increase: organs peaked at 3-8% share and never passed tier 1 in
    20 min, hence weight 6 -> 12 and the Lab strains.
  - bal_probe balanced, 20 min, seeds 11,22,33,44,55,66,77,88,99,111 (CSVs in tests-v021/):

    | | v0.20 | v0.21 |
    |---|---|---|
    | queen deaths | 2 (77, 99) | 1 (44) |
    | starving share, calm time after 5 min | 0.33 | 0.22 |
    | median end population | 6.5 | 10.5 |
    | mean population after 10 min | 42.8 (36.3 w/o seed 77's short run) | 38.4 |
    | combat deaths, mean | 56 | 56 |

    Per-ant upkeep is +11% (whole-run ledger, first 5 seeds) but v0.21 starves less; a 30% organ upkeep trim
    was staged and reverted because the untrimmed config is the measured one.
- Not checked: live look at play zoom, effect readability in a crowded raid, lineage legend with 20 traits at
  1280x720, inspector line wrapping, whether bot-bought organ strains change the A/B (the bot buys from the
  wider Lab pool now).
- Known: the raid 9-10 population crash exists in both builds and is the next real balance problem.

## v0.20.0 - part forms (compile-checked, contact-sheet checked, fuzzed, 400 s headless run; not playtested)
- 22 new part forms inside 5 existing families. A form is a subtype gene (`genome.forms`, family -> index,
  missing = 0 = classic), so pre-v0.20 genomes and queen definitions load unchanged.
- Forms can sit hidden in a line that lacks the organ and show when the organ appears. Only a change to a
  visible organ writes a lineage note ("grew digging forelegs", "scorpion tail", "back to spines").
- New mutation op `form`, weight 7 (others sum to ~122, so each existing op is ~5% less likely). Existing Lab
  strains favour their family's forms: leg -> leg forms, spike -> spike forms, stinger -> sting forms,
  acid -> acid forms, eyes -> antenna forms. No new shop items.
- Stats map onto existing phenotype keys only (no sim changes). Effects apply only while the organ exists.
  Carry is now floored at 0.5 (unreachable before v0.20).

  | Family | Form | Gain | Cost |
  |---|---|---|---|
  | Spikes (x spikes) | thorns | thorns +0.25 | speed -0.05 |
  | | hooked barbs | attack +0.25 | tunnel_mult -0.02 |
  | | dorsal ridge | armor_red +0.02 | upkeep +0.0006 |
  | | propodeal spines | armor_red +0.01, thorns +0.15 | carry -0.15 |
  | Acid gland | venom sacs | thorns +0.6 | hp -4, carry -0.5 |
  | | venom-dripping jaws | attack +1.0 | thorns -0.4, upkeep +0.001 |
  | | spray nozzle | attack +0.8 | speed -0.3, upkeep +0.0015 |
  | Legs | digging forelegs | dig +0.6 | speed -0.4 |
  | | jumping hind legs | speed +0.8 | upkeep +0.0015, carry -0.5 |
  | | raptorial forelegs | attack +1.2 | carry -1.0, dig -0.2 |
  | | stilt legs | speed +0.6, sense +2 | tunnel_mult -0.1, hp -4 |
  | Antennae | clubbed | sense +3 | upkeep +0.0005 |
  | | feathered | sense +5 | hp -3, upkeep +0.0008 |
  | | whip | sense +4 | tunnel_mult -0.05 |
  | | forked | sense +2, phero +0.15 | upkeep +0.0006 |
  | Stinger | barbed | attack +0.8 | life -20 s |
  | | scorpion tail | attack +0.6, thorns +0.4 | speed -0.3 |
  | | twin stingers | attack +1.2 | upkeep +0.0015 |

- Art (body_painter.gd): each form drawn in the v0.19 style. Specialised near legs (digging, jumping,
  raptorial) draw in front of the body and slightly lighter so they read. Stilts lengthen legs 1.3x and raise
  the stance. Whip antennae sweep back over the body; the scorpion tail arches over the gaster.
- Castes (ant_view.gd): soldiers draw 1.12x, foragers 0.94x, diggers 1.0x, so castes read with badges faded.
- Lineage panel: 3 new tracked traits - Special legs, Special antennae, Venom organs (non-classic acid form).
- describe() names the form ("4 hooked barbs", "scorpion tail", "stilt legs").
- Checked: compile.gd ok. tests-v020/forms_sheet.gd renders all 22 forms + 2 stacked worst cases inside the
  170x136 frame, 0 triangulation errors (8 fixed during the pass). tests-v020/form_fuzz.gd: 20,000 mutations,
  every form reached with a lineage note, phenotype and describe() error-free, min carry 2.6.
  lineage_check.gd seed 11, 400 s: 100 ants, new traits sampled, no errors.
- Not checked: balance (no bal_probe run; the new op shifts RNG draws, so v0.18.1 CSVs are not comparable),
  live in-colony look, lineage legend overflow with 13 traits, HUD describe() line length.
- Weak: at ~40 px, spike, venom and stinger forms read (bright accents); leg and antenna forms mostly don't,
  except stilts, whip, and feathered.

## v0.19.0 - ant art pass (compile-checked, sprite-sheet checked; not playtested)
- core/body_painter.gd rewritten; public interface unchanged (genome, paint_scale, anim_t, gait), so the
  baker, HUD thumbnails, queen select and lineage panel need no changes.
- Anatomy: teardrop gaster with a drooping tip, humped mesosoma (pronotum hump + propodeal slope), head
  tilted mouth-down and tapered toward the clypeus. Majors get bigger heads with small eyes.
- Stance: six visible legs (near + far side), tapered femur/tibia/tarsus with thinner ink, knees out past
  the body, body raised on the legs. Tripod gait across the 4 baked frames.
- Head: curved toothed mandibles (near + far), beaded elbowed antennae with a club, faceted eye with
  specular, clypeus line, ocelli for extra eyes. Claw and tentacle jaws redrawn.
- Shading: shadow -> lit -> top band -> underside rim light -> soft highlight + specular dot per part.
  Gaster tergite seams, thorax suture, camo mottling, setae, scutes, spines, photophores, sting, acid drop.
- Wings: tapered fore/hind wings with costa, stigma and radial veins, drawn over the body.
- Draw groups: far side -> near legs -> body -> near head parts -> wings, each ink -> fill -> detail.
- ant_view.gd: food gem carried in the mandibles (was floating overhead), dirt clod and dig puff moved to
  the new mouth position, caste badge lowered to match the lower body.
- Checked: compile.gd ok; contact sheet of 10 variants plus extreme genomes (5 segments, 90-len legs,
  50-len antennae, max major/replete) fit inside the 170x136 sprite with no clipping.
- Not checked: in-colony look at play zoom, gem/clod placement on live ants, lineage thumbnails.


## v0.18.1 - honest A/B + lineage polish (compile-checked, measured, screenshot-checked)
- Harness fix: Lab offers and raid rosters now use common random numbers (sim.sub_rng). In v0.18.0
  the first borer shifted every later draw, so on/off runs also got different Lab offers.
- Re-measured (20 min, seeds 11-55, mean ants after 10 min): v0.17 rules 39, borers off 79,
  lever 2 41 (+1 queen collapse), lever 2 + reserve fix 41 (+1 collapse). Levers do not help:
  borer_lever default reverted to 0, reserve_mode stays 0. The v0.18.0 "doubling" was snapshot noise.
- Food ledger (sim.ledger; bal_probe prints LEDGER rows). v0.17, 20 min: forage 1.8-2.7k, upkeep
  1.2-1.8k, eggs 1.1-1.7k, Lab 0.2-0.6k. Borers-off ledger not collected yet: next step.
- New knobs, default off: reserve_mode (forager reserve for all non-soldiers), fate.counter_mode
  (raiders gain piercing vs armor, thick hide vs spines/acid, in place of some flat HP).
- Lineage panel: dimmed modal above all panels, click outside to close, legend fits, labels fixed;
  checked at 1920x1080 and 1280x720 (bottom lever bar overflows at 1280: M6 HUD pass).

## v0.18.0 - borer pacing (measured) + M4 lineage view (compile-checked, headless-checked)
- Borer pacing: `colony_sim._borer_plan()` + `borer_lever` knob (0 = v0.17 rules, 1 = count and
  start scale with colony size, 2 = lever 1 + borer HP scales with colony size). Default is 2.
  - Lever 1: first borer at the first even raid with 50+ ants (forced at raid 10 regardless),
    then 1 per 60 ants, max 1 before raid 12 and 3 after.
  - Lever 2: borer HP x clamp(ants / 80, 0.45, 1.35) (was clamp(ants / 70, 0.55, 1.0)).
- Measured (tests/bal_probe.gd, Balanced bot, 20 sim-min, seeds 11/22/33/44/55, sequential):

  | Config | Ants at 20 min | Mean | Collapses | Lost ants (sum) | Queen min HP |
  |---|---|---|---|---|---|
  | v0.17 rules (lever 0) | 3 / 4 / 33 / 0 / 57 | 19 | 0 | 371 | 280-300 |
  | Borers off | 73 / 72 / 115 / 113 / 113 | 97 | 0 | 379 | 300 |
  | Lever 1 | 41 / 1 / 34 / 7 / 57 | 28 | 1 (seed 22, queen) | 324 | 0-299 |
  | Lever 2 (kept) | 33 / 76 / 8 / 65 / 38 | 44 | 0 | 250 | 246-292 |

  Lever 2 more than doubles the mean and median end population with no collapses, but 2 of 5 seeds
  ended lower than v0.17 (33: 33 -> 8, 55: 57 -> 38) and it is still less than half of borers-off.
- Finding: in every run the colony peaked at 98-127 ants and borers came only 2-3 times, yet
  with borers on colonies crashed and the queen took almost no damage. The borer's cost is the
  colony's response, not its bite: any raider underground adds +0.5 to the defend stimulus
  (`_update_stimuli`), so one slow borer fight pulls most of the workforce off food. That is the
  next lever (M3), not borer count or HP.
- M4 lineage view: press L or the Lineage button. Top: share of the colony carrying each
  trait (wings, stinger, acid, glow, big head, replete, camo, armor, claws, spines) over the
  run, plus the top plan's share. Bottom: the ancestry strip of the selected ant's body plan
  (or the most common plan) from the founder, each step labelled with its generation and what
  changed ("gained wings", "claw jaw", "extra body segment").
  - Genomes now carry `parent`, `note`, `born_gen`, `born_t`. Only visible changes create a
    lineage node; behaviour tweaks and small size/colour drift inherit the parent's node, and a
    double mutation folds into one step. Chains are capped at 40 nodes.
  - `sim.evo_log` samples every 15 s (240 samples kept). Toasts when a trait passes 50% of the
    colony and when a swept trait drops under 15%.
  - The baker keeps ancestor thumbnails alive while the panel is open.
  - Checked headless (tests/lineage_check.gd, seed 11, 300 s): log fills, chains resolve. Not
    screenshot-checked: the panel layout at 1920x1080 and 1280x720 is unverified.

## v0.17.0 - performance + deep world (compile-checked, profiled, 1 screenshot)
- Perf (tests/perf.gd, per-section profiler: set sim.prof = {}): tilt cached per cell,
  footing check staggered over 5 ticks, nav rebuild every 1.5 s (was 0.5 s).
  Seed 11 at ~120 ants: 89 -> 51 ms per sim-second. Stress, 674 ants: 222 ms/sim-s
  (0.25 ms per ant; fine at 1x, laggy at 4x). Ant updates are 64-76% of sim time.
- Deep world: grid 150 -> 225 rows; new strata limestone (digs 0.5x, ammonite fossils)
  and shale (0.38x) below the red clay; bedrock much deeper; 12 nest levels.
- M3 finding (sim_probe, Balanced bot, 20 min): with tunnel borers ants end at 39/10/17
  (seeds 11/22/33); with borers off 73/72 (seeds 11/22). Borers are the population
  killer. Not fixed yet.

## v0.16.0 - the underground city (compile-checked + 2 headless runs)
- 8 nest levels (was 5), 11 rooms per level, nest spread grows with the colony
  (170 -> up to 520 columns; +60 per Architects' Hall), up to 3+ dig jobs at once.
- Workshops unlock by colony size and produce upgrades while nurses tend them (capped):
  Armory (45 ants: armor), Cistern (55: healing; halves flood and heat damage; an
  underground lake), Venom Works (65: attack + thorns), Sting Battery (75: tunnel + gate
  damage), Architects' Hall (90: dig speed, wider city). Drawn with Brotato item icons.
- Reach: outposts (up to 4 far entrances) from 70 ants; frontier food piles beyond the old
  playfield (up to 45% of new piles, up to 320 columns out, richer with distance).
- Measured (seed 11, 25 min, gambler bot): first run 19 rooms, 4 workshop kinds, 2
  outposts, all 8 levels, 22 upgrade batches, survived raid 14. A standing dig crew made
  it worse (15 rooms, ~40 ants, near-wipe at raid 16); now only for 60+ ants with surplus
  food. That final setting is compile-checked only.

## v0.15.0 - the fish tank (compile-checked + 1 screenshot pass)
- Fix: ants no longer flip upside down in tunnels. Root cause: ground_normal sums every
  solid neighbour, so in narrow tunnels floor and ceiling nearly cancel and one extra
  ceiling cell turned the ant over. With a floor underfoot, tilt is clamped to +-63 deg.
- Ants baked at 1.6x resolution (sprite_baker.BAKE), drawn into the same logical rect:
  crisp when zoomed in. New detail: tibial spines, mandible teeth, underside rim light.
- Living queen: paces her chamber with pauses, walk-cycle frames, breathing, a squeeze
  each time she lays, slight sway. Queen bakes now have all 4 walk frames.
- More chambers: 11 per level (was 7), new Midden room (refuse heap of husks that grows
  with the dead; halves plague deaths while you have one).
- Tank ambience from Brotato's particle sprites: warm light pooled in every room (tinted
  by purpose), dust motes drifting through the tunnels, glowing spores rising from fungus
  gardens, a soft halo around glowing ants.
- Back wall depth: cracks open onto a deeper layer with its own parallax, pebbles set in
  the wall, tunnel air brighter in the middle and darker toward the walls.

## v0.14.0 - famine, rumors, antidote (compile-checked + 2 headless gambler runs)
- Famine: at 0 food the colony eats its own brood (1 egg per 1.5 s, 80% of egg cost back).
  Turns the starvation cliff into a spiral you can climb out of.
- Lab rumors: each Lab visit hints at one unrevealed side effect on offer.
- Antidote (Lab item): cures one discovered side effect you own; refunds 20 food if none.
- tests/play.gd: a gambler bot plays and prints the run as a story (-- <minutes> <seed>).
  Seed 7, 20 min: v0.13 starved at 15:00 (73 -> 0 ants in 4 min, queen untouched);
  v0.14 bought different items (events shift the RNG), dipped 106 -> 35 ants, recovered to
  60 by raid 10. Not an A/B; one seed each. Famine did NOT fire in that run: the queen
  had no eggs when food hit 0, so the recovery came from honeydew rain and a smaller colony.

## v0.13.0 - fate & the black market (compile-checked only, NOT sim-tested)
- Black market (11 items): strong effects with a hidden side effect that is real from the
  moment you buy and shows as "Side effect: ???" until noticed (by time, the next raid, the
  next Lab, a plague, or a cave-in). Growth Hormone, Sugar Rush, Purebred Line, Queen's
  Elixir, War Drums, Scent Beacon, Blasting Caps, Cursed Idol, Glass Carapace, Four-Leaf
  Pheromone (hidden upside), Mystery Egg (rolls 1 of 6 outcomes, good or bad).
- Synergies (11): owning both halves fires a named combo (Venom Lance, Firefly Swarm,
  Army of Titans, Plague Engine, Blood Pact...). Lab cards say "Completes combo: X".
- Colony events every ~2.5-3.5 min: honeydew rain, flash flood, cosmic ray storm (next 10
  eggs mutate twice), nuptial flight (half your alates leave for food + mutation), beetle
  trader (+2 Lab offers), fungus bloom, heat wave, windfall.
- Monoculture plague: one body plan past 60% of a 60+ colony gets sick (35% with Purebred).
- Raiders counter-evolve: raider HP scales with your ants' evolved attack/HP (up to +80%).
- Milestone toasts the first time each new organ evolves.
- Knobs: core/fate.gd (SYNERGIES, EVENTS, EVENT_W, plague thresholds), shop_items.gd.

## v0.12.0 - lean build (compile-checked only, NOT sim-tested)
- M2 digging & maze: two tunnel planes joined by holes, strata dig rates (sand fast, clay
  slow, bedrock/stone/fossil never), organic galleries/loops/scouts/shafts over 5 levels,
  back-plane rooms, spoil hauled up to a real mound. Back-plane units drawn smaller/dimmer.
- Diggers finish spoil trips instead of dropping pellets; more back-plane rooms (75%).
- Economy: forager reserve (20% of ants stay on food runs during raids unless the queen is
  under 50% HP) + starvation guard (larder under 25% of target boosts foraging, cuts
  digging and defend pull). Aimed at the raid 8-12 starvation spiral.
- M4 anatomy (first cut): petiole nodes, gaster patterns, compound eyes + ocelli, elbowed
  antennae, tarsi, hair. New heritable genes with costs: wings, stinger, acid gland,
  big-headed majors, repletes, glow, camouflage, pheromone strength. 9 new Lab strains.
- Fixes: toast crash (Tween under toast panel), mound pellet grid, mound stair highlights.

Knobs: colony_sim.gd SPOIL_KEEP, FORAGER_RESERVE; world_grid.gd DIG_RATE; nest_planner.gd
level depths + job weights; phenotype.gd trait costs; genome.gd MORPH_DEFAULT.

Evolving ant-colony mode built on Brotato 1.1.15.1 + Abyssal Terrors, ModLoader 6.3.0,
Godot 3.x (GDScript 3: yield not await, update() not queue_redraw(), no class_name in mod files).

Adds a **Colony (InfDNA)** button under Start on the main menu. The colony is its own
scene: no player character, no waves. Ants act on their own; the player steers.

## Controls
WASD/arrows or right/middle-drag: pan | Wheel: zoom | Left-click ant: inspect |
Space: pause | 1-4: 1x/2x/4x/10x | B: scent beacon | G: mutagen on the selected ant | O: next goals |
P: trails | C: caste badges | L: lineage | Esc: back to title

## Player levers (influence, not control)
- Focus (Forage / Balanced / Dig / Defend): shifts the stimuli ants respond to
- Brood (Low / Normal / High): queen's egg interval and food reserve
- Speed: pause / 1x / 2x / 4x

## Layout
- `core/` - no Brotato dependencies (ports to the standalone infinitedna project)
  - `genome.gd` body plan + behavior genes, mutation, describe()
  - `phenotype.gd` genome -> speed, carry, dig, sense, upkeep, hp, lifespan
  - `world_grid.gd` side-view terrain, digging, walkability, BFS nav fields (home / exit)
  - `colony_sim.gd` ants, tasks (response-threshold model), foraging + trails,
    digging, queen/eggs, selection (fitness-rate tournament), food economy
  - `body_painter.gd` Brotato-style renderer (ink -> fill -> highlight passes)
  - `enemy_defs.gd` raid roster (stats + candidate sprite paths; DLC sprites preferred)
- `content/colony/` - the mode: scene, sprite baker (Viewport -> ImageTexture per genome),
  world view (dirt shader with ink outline), ant view, enemy view + combat FX, camera, HUD
- `extensions/main_menu.gd` - adds the menu button

## Tuning knobs
- `colony_sim.gd`: EGG_COST, HATCH_TIME, MAX_ANTS, MUTATION_CHANCE, MAX_PILES,
  crowding capacity (`open_under / 22.0`), starvation interval, forage timeout
- `phenotype.gd`: all stat formulas (this is what selection optimizes)

## Raids (M3)
- First raid at 3:00, then every ~2 min (shrinking to 1 min). Budget grows per raid.
- Small raiders (baby alien, fly, shrimp) go down the shaft for the queen.
- Brutes/elites (charger, helmet alien, crab, bruiser, giant isopod) siege the
  entrance for 30 s, then retreat. Butcher boss every 8th raid.
- Ants: Defend task (response threshold, gene `defend_t`), alarm re-evaluation,
  foragers flee surface raiders. Combat stats from the body: attack (jaw, claws,
  size, spikes), hp (size, armor), armor damage reduction, thorns (spikes).
- Kills drop food (surface pile, or straight to stores if killed inside).
- Queen: 300 hp, regenerates when left alone; her death ends the colony.
- Kin selection: fallen defenders enter a legacy pool (25% of parent picks) so
  combat traits can spread even though soldiers die.

## Evolution Lab (M4)
- Opens automatically (pausing the sim) when a raid is repelled; also via the Lab
  button between raids. 4 offers weighted by tier (tier odds rise with raid count),
  reroll costs 5 + 4 per reroll, prices scale with raid number and stacks owned.
- Paid in food, so every purchase competes with brood.
- Strains (`bias`) shift mutation odds; instincts (`trait`) nudge newborn genes;
  colony upgrades change queen/brood/selection. Second Entrance digs a new shaft
  and gallery; small raiders target the nearest entrance, sieges only the main one.
- All items live in `core/shop_items.gd` - add new ones there (bias/trait/colony/mods keys).
- Items reuse Brotato item icons (`res://items/all/<id>/<id>_icon.png`, 208 available);
  the Brotato effect is irrelevant - every item is reinterpreted for InfDNA.
- Sounds: `content/colony/sfx.gd` maps sim events to Brotato sounds on the "Sound" bus.

## v0.5 - castes, 2.5D, trade-offs
- Castes: each egg is born Forager / Digger / Soldier by colony need
  (`_needed_caste`), and its parent is the tournament winner on that caste's
  fitness (food delivered / cells dug / damage dealt). Lineages specialize.
- Trade-off: big bodies move slower in tunnels (`tunnel_mult` in phenotype).
- 2.5D: the surface is a ground band (`WorldView.DEPTH`); every unit has a depth
  lane; back lanes draw higher, smaller, darker; ants + raiders are depth-sorted
  in `ant_view.gd`. Fighters drift toward their target's lane.
- Evolution toasts when a new body plan reaches 6+ ants.
- Well-fed queen lays faster; smoother raid curve (floor 75 s).

## v0.6 - nest blueprint, food economy, living surface
- `core/nest_planner.gd`: main shaft + side galleries ending in flat oval chambers
  (food store / nursery / fungus farm). Diggers take jobs; `dig_down` gene picks
  shafts vs galleries. Galleries branch from shafts and from finished chambers;
  new shaft branches start when the network gets crowded.
- Food: storage cap 80 + 45 per food chamber; excess rots (1.2%/s of excess).
  Fungus farms (Brotato garden sprite) produce food, tended by nurses, and
  ferment 40% of rot back into food. Nurseries: eggs laid there, hatch faster.
- Surface: Brotato fruit trees drop fruit piles; rocks; Looter / Looting Pig
  wander as passive prey (flee ants, big food when hunted, never counted as raids).
- World continues past the edges (extended terrain + haze).
- Ants: jointed tapered legs, far-side legs shaded, tripod gait baked as 4 frames.

## Balance notes
- Tested: 3 seeds survive 25+ sim-minutes, 45-60 ants, 15 raids.
- Speed/carry still drive most selection; combat traits rise in raid-heavy runs
  (attack 4 -> 7 on one seed). Knobs: `enemy_defs.gd` hp/dmg/cost,
  `colony_sim.gd` FIRST_RAID, SIEGE_TIME, BOSS_EVERY, budget growth.

## v0.7 - queen under threat, castes on ants
- **Tunnel Borer** (`enemy_defs.gd`, class `burrower`, Brotato lamprey sprite): every other raid from
  raid 4 (never on a Butcher raid), one at a time until raid 12, then two. Breaks ground 22-44 cells
  from the main shaft, winds up for 2 s on the surface (ants can hit it), then bores its OWN tunnel
  to the queen chamber and gnaws her (7 dmg/s). Deals only 30% damage to ants (`ant_mult`) - it is
  after the queen, not the colony. The tunnel it carves stays open.
- Feedback: "DIGGING!" text, dust, pulsing red ring on borers underground, queen HP bar + red
  flash, "THE QUEEN IS UNDER ATTACK!" banner + sound, HUD "N BORING toward the queen".
- Fixed: defenders stayed in the Defend task chasing passive prey (Looters) for up to 70 s, which
  starved the colony. Only hostile raiders count as threats now.
- Fixed: an unreachable cell (`field == -1`) used to count as "next to the queen".
- Caste badges: coloured disc + icon above each ant (green basket = forager, brown tool = digger,
  red helmet = soldier); soldiers pulse while defending; `C` toggles. HUD shows caste counts.

## v0.8 - queens (M5)
- Menu button -> queen select (`content/colony/queen_select.gd`) -> colony. 64 queens defined in
  `core/queens.gd` (50 base characters + 14 Abyssal Terrors; queens whose icon is missing are hidden).
  Arrow keys / click to browse, double-click or Enter to found, Random button.
- Each queen: founder colour + body ops (armor, claws, tentacles, size...), start bias/mods/colony
  changes (same keys as Lab items) and, for 38 of them, one rule implemented in `colony_sim.gd`
  (`rule(key)`): lifesteal, revive, blood_eggs, undead, growth, bloodlust, twin, wild_hatch,
  raid_mutation, tame, zap, reach, wounded_fury, no_tunnel_penalty, dig_jobs, cap_per_chamber,
  rot_mult, farm_boost, fruit_boost, prey_boost, lab_offers, free_reroll, lab_luck, caste_bias,
  start_food, start_entrance.
- 26 queens are stat/body queens with a trade-off, not a new rule (Founder, King, Knight, Cyborg,
  Golem, Chunky, Ogre, Speedy, Wildling, Explorer, Hiker, Elder, Plague, Peace, Shadow, Renegade,
  Loud, Merchant, Healer, Trapper, Brawler, Lone Claw, Tentacle, Swarm, Generalist, Boss).
- Add a queen: one `r.append(_q(...))` in `queens.gd`; add a rule key by reading `rule("key")` in the sim.
- New colony after a collapse returns to the queen select.

## v0.9 - UI + motion pass
- Shared UI kit built from Brotato's own art (`content/colony/ui_kit.gd`): ink-outlined chunky panels
  (`ui_panel_normal`), lifebar textures (`ui_lifebar_*`), stat icons (`items/stats/*`), material and
  misc icons, particle sprites (`particles/sprites/particle_*`), button sounds. Reusable widgets:
  `ui_button.gd` (hover lift, press squash, accent selected state, icon, hover/click sounds),
  `ui_bar.gd` (smooth fill + trailing loss bar + flash), `ui_num.gd` (count-up numbers that pop).
- HUD (`hud.gd`, rewritten): colony card with queen portrait, food and queen lifebars, count chips,
  caste chips, stacked task bar, stat row; raid card with countdown/raiders-left bar and a BORING
  warning; styled graph; lineage cards that update in place (no more flicker); inspector with HP/age
  bars and stat icons; bottom lever bar with icons and tooltips; pause chip; slam-in banner;
  stacked toasts; red damage vignette when the queen is hit; scene fades in from black.
- Evolution Lab: dim + pop-in, staggered card entrance, hover lift, tier rims (legendary pulses),
  flash on buy, shake on can't-afford, owned items as an icon grid, animated food counter.
- Queen select: drifting Brotato particles, staggered card pop-in, hover/selection animation,
  breathing queen preview, effect chips (green good / red bad) generated from each queen's data,
  fade into the colony.
- World FX use Brotato particle sprites: dust puffs, hit sparks, death bursts, rings (boss/elite),
  heal plusses (queen regen), hatch sparkle. Eggs wobble harder before hatching, newborns pop out,
  hurt ants flash, the queen shakes/reddens when hit, camera kicks on queen hits, boss spawn/death.
- Fixed: Hunters item icon (Brotato names that one `icon.png`), a texture-lifetime bug that spammed
  RID errors (draw calls only hold RIDs; never `load()` a texture as a temporary inside `_draw`).

## v0.10 - world & footing (see PATHWAY.md, milestone M1)
- `core/world_grid.gd`: infinite in x. Surface profile generated lazily outward (`surf_y(x)`,
  bigger hills beyond the playfield); sim arrays (`solid/under/walk/pher`) cover
  `sim_l()..sim_r()` and grow by `CHUNK` columns via `ensure_cols()` (the sim calls it once a
  second for every unit). All grid functions take world x (can be negative).
  `arena_l..arena_r` is the v0.9 playfield: food, raids, trees and the blueprint stay in it.
- Footing rule (`_walk_rule`): open cell touching solid, or the ground-level rim over a shaft
  mouth. Above the sky there is no wall. Ants with no foothold fall (`_on_arrive`).
- `content/colony/sky_layers.gd`: sky, sun, 5 parallax layers (factor f: moves f x the
  camera and zooms pow(z, 1-f)), clouds, bedrock fill.
- `content/colony/terrain_view.gd`: terrain streamed in chunks around the camera, two
  sprites per chunk: back wall shader (parallax, drop shadow, lit side walls) and front
  dirt shader (strata, roots, pebbles, fossils, bevel, ink outline). `world_view.inner`
  sits between them (rooms, eggs); `world_view.band` is the surface top face + ant hill.
- `ant_view.gd`: contact shadows on the surface, caste badges fade out when zoomed out.
- `colony_sim._footing_fix`: an ant or raider (not borers) without footing for 0.5 s is moved to the
  nearest cell that has some. Digging carves away the dirt an ant touches; without this a busy dig
  room left ants hanging up to 2.5 s.
- Measured: see PATHWAY.md, "M1 measured". Balance is unchanged (4/7 seeds collapse by raid 9-10, same as v0.9).

## Known weak spots
- Balance is only spot-tested: borer runs with a simple bot survived 26 sim-minutes on seed 11
  (106 ants) and collapsed at raid 12 on seed 22 (2 borers + elites). Only the 3 rule-benders
  above were exercised in play; the other 60 queens were never played, only loaded.
- Queen rules stack with Lab items and were not tuned against each other; expect some queens
  (Lich, Vampire, Apprentice, Vault) to be much stronger than others.
- Caste badges get busy above ~80 ants; press C to hide them.
- UI was only rendered at 1920x1080. Smaller windows (1280x720) were not tested; the left column,
  lineage panel and inspector may crowd each other.
- Animations were checked in still frames only, so easing and timing are unjudged.

## Art pipeline (new in the repo)
The owner draws creature parts (ChatGPT, one transparent PNG per part: body, near legs, far legs, wings, head, claws). `art_src/` keeps the originals. `tools/art/make_art.py` shrinks them, thickens the
outline so it still reads small, cuts the legs into separate pieces and the jaw or fangs out of the body, and writes `src/mods-unpacked/Judah-InfDNA/content/art/` with an `art_manifest.json` (where every
piece sits and where it hinges). The game will draw the pieces back together and move them (walk, ripple, bite, flap). Spider, void boss, bird and rocks are in; they are wired into the game in the next build.
