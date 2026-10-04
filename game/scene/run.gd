extends RefCounted
# What carries from one screen to the next within a play session: the queen picked on the title screen, what the last colony
# passed on, and the colony that just ended (for the end-of-run screen). Static, so every screen reads the same values.

static var queen_id := "well_rounded"
static var heirloom := {}     # legacy trait carried into the next colony (core/legacy.gd)
static var kin := {}          # the lost colony that comes back as a rival (core/wild.gd)
static var last_sim = null    # the colony that just collapsed or finished
