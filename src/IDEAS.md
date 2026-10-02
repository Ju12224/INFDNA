# InfDNA idea backlog

Direction from the owner (v0.27): *the game is boring just watching*. The player needs a **permanent directing role**: always something
to decide and to do, with consequences, not a fish tank. Items 1, 2 and 4 below are meant to become that role together, not stay
separate features. Item 5 is wanted. Item 6 must look super realistic and use real Brotato art.

## The directing role (items 1, 2, 4 together)
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

## Wanted
- **Legacy between runs (item 5):** your best run hands one trait (a body feature or a gene bias) to the next queen; show it on the queen
  card; the run summary offers the choice.
- **Fungus and aphid farming (item 6): super realistic, with Brotato resources.** Leaf-cutter fungus gardens that grow in visible stages
  (spore, hyphae, white mycelium, mature sponge), leaf pieces carried down by ants, mould outbreaks, a gardener caste, aphid herds
  milked for honeydew on roots, seed granaries, honeypot repletes. Needs Brotato's own textures and sounds: waiting for `Brotato.pck`
  (see `tools/list_brotato_pck.py`).

## Backlog
- **Seasons:** spring to winter. Winter cuts surface food and pushes the colony to its stores; ties into day/night and rain.
- **Sound and ambience:** wind, crickets at night, rain, footsteps; needs the Brotato sound list.
- **Throne room / royal upgrades, guard posts at outposts, food caravans** (from the underground city notes in PATHWAY).
- **Seeds and challenge runs:** share a seed, daily seed, fixed-queen challenges.
- **Accessibility:** UI scale, colour-blind palettes for the task and caste colours, a reduced-flash option.
- **Save and load a colony** (large: needs full sim serialisation; deferred).
- **Genealogy poster / timelapse export** of a colony's lineage.
