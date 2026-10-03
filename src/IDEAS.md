# InfDNA idea backlog

Direction from the owner (v0.27): *the game is boring just watching*. The player needs a **permanent directing role**: always something
to decide and to do, with consequences, not a fish tank. Items 1, 2 and 4 below are meant to become that role together, not stay
separate features. Item 5 is wanted. Item 6 must look super realistic and use real Brotato art.

## The direction (v0.30): the Wild, history as the world
Researched in v0.30: evolving ants + a roguelite shop is already SuperColony's ground (it even has DNA harvested from defeated foes), so gene theft is not the hook.
Not found anywhere: **your own past runs becoming the world**. Everything from here should serve one line: *every colony you lose is the enemy you meet next.*
Done: a fallen colony's most evolved strain escapes into the Wild (`core/wild.gd`); the strongest line is the next run's rival (evolved while you were away, drawn as your
old ants, fighting with your old organs); breaking it takes its best trait back and ends the line; leaving it makes it one run stronger.
Next, roughly in order of how much they would sell the idea:
- **Field Guide:** a screen (queen select + collapse) listing every line in the Wild: baked sprite, species name, plan, which run it came from, how it fell, how many runs it has
  evolved on; and a family tree. The Wild is invisible until it can be browsed.
- **Counter-evolution inside a run:** the rival picks its mutants against what actually beats it (your dominant strain's damage type, your traps, your organs).
- **Wild creatures:** unbroken lines that wander the meadow as fauna (an ecosystem made of your past) and fight the rival and the anteater too.
- **Spare or destroy:** after a break you may spare a line: it becomes a tributary (food each run, or allies in the next).
- **Prisoners and crosses:** take kin ants alive and cross their body plan into yours in the Lab.
- **Named queens and dynasties:** the Wild remembers who beat whom; share a line as a code so a friend meets your descendants.

## The directing role (items 1, 2, 4 together)
Status: v0.29 has the Will meter, six commands (Rally, Harvest, Recall, Surge, Breed, Strike), the caste order, two predators (a bird, an
anteater), a rival colony that raids you and can be broken, and eleven Lab items that feed the commands (Queen's Whisper, Deep Reserve,
Pheromone Choir, Frugal Orders, War Standard, Honey Trail, Scarecrow, Adrenal Glands, Stud Book, Hive Voice, Puppet Strings).
Not yet: pheromone paint and dig orders, antlion pits, frogs and lizards, a second rival, rival food theft.
The player is the colony's *voice*: a **Will** meter fills over time and is spent on **commands** that steer the colony. Commands matter
because the colony alone is only competent: it forages, digs and defends, but badly (scattered, slow to react). Threats and
opportunities keep appearing that a director can answer.
- **Commands (item 4), v1:** Rally flag (pull defenders and soldiers to a point, bonus bite), Harvest order (send foragers to a chosen
  pile with a boosted trail), Recall (everyone on the surface goes home), Surge (a short sprint), Mutagen surge (steer evolution),
  caste order for the brood (workers / mixed / soldiers). Later: pheromone paint, dig orders, strike party.
- **Predators (item 1):** a bird that hunts foragers far from the nest (Recall / Rally answer it), then an anteater boss that raids the
  hole, antlion pits near piles, frogs and lizards at night or in the rain.
- **Rival colonies (item 2):** a neighbouring colony with its own evolving ants and nest, east or west. You scout it, raid it, defend
  against its raids, and can take its food. Direct a strike party instead of waiting for the colony to do it.

## Done in v0.29
- **Legacy between runs (item 5):** the run summary offers the champion strain's traits (an organ, a form, an anatomy gene, legs, armour,
  spines, size, an instinct, or plain veteran stock); the choice is kept in `user://infdna_legacy.json`, every founder ant of the next
  colony is born with it, and the queen select screen shows it and can switch it off. (`core/legacy.gd`)
- **Seasons:** a twenty-minute year (`core/seasons.gd`): autumn glut, lean winter, scenery that changes with it (see README v0.29.0).
- **Sound and ambience:** procedural wind, birds, crickets, rain and underground murmur (`content/colony/ambience.gd`). Brotato's own
  sounds can replace or join it once the sound list is known.

## Wanted
- **Fungus and aphid farming (item 6): super realistic, with Brotato resources.** v0.29 draws the gardens procedurally (a leafcutter
  comb that matures over ~2.5 minutes, mould outbreaks the nurses weed out, an antibiotic-gland item). Still wanted: leaf pieces carried
  down by ants, a gardener caste, aphid herds milked for honeydew on roots, seed granaries, honeypot repletes, and Brotato's own
  textures and sounds: waiting for `Brotato.pck` (see `tools/list_brotato_pck.py`).

## Backlog
- **More seasonal play:** frost nights that stiffen ants outside (Recall at dusk), a spring flood that fills the low tunnels, drought in summer.
- **Footsteps and fight sounds** from Brotato's sound list.
- **Throne room / royal upgrades, guard posts at outposts, food caravans** (from the underground city notes in PATHWAY).
- **Seeds and challenge runs:** share a seed, daily seed, fixed-queen challenges.
- **Accessibility:** UI scale, colour-blind palettes for the task and caste colours, a reduced-flash option.
- **Save and load a colony** (large: needs full sim serialisation; deferred).
- **Genealogy poster / timelapse export** of a colony's lineage.
