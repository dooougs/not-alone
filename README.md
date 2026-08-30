# Not Alone

A basic mod skeleton for Factorio 2.1.

## Structure

- `info.json` contains the mod metadata and dependencies.
- `data.lua` is the entry point for prototype definitions.
- `control.lua` is the entry point for runtime event handlers.
- `poc.lua` contains experimental proof-of-concept runtime behavior.
- `locale/en/not-alone.cfg` contains English localization.

## Current proof of concept

Each player starts with ten **Team mate** items and one **Habitat** item. Place the Habitat where
you want the initial logistic network and put Team mate items in its material slot. Open the
Habitat and choose a working role for a stored team mate to deploy it automatically. Team mate
items stack to 20. Deployed units are
native Factorio units, so they use the engine's pathfinder to navigate around obstacles. When
team mates have no route, role work, enemy, or logistics job, they return to the nearest Habitat and
enter it, becoming stored Team mate items in its roster. Team mates carrying ore, logistics cargo,
or building material remain outside until their cargo is handled. If the closest Habitat is full,
they use the next-nearest Habitat with room; they remain outside only when every Habitat is full.
While a route is active, they follow its destinations in order. Their built-in ranged attack uses
pistol-like physical damage.

Factorio units do not have character gun or ammunition inventories. The unit conversion therefore
replaces copied starter equipment and ammunition depletion with a built-in attack.

Each player receives a **Team mate command tool**. Drag with the tool to select a group of your own
team mates. A centered selected-team roster opens with one row per deployed team mate and iconized
dropdowns for reassigning them to Logistics, a resource-specific Miner role, Security, Builder, or
Scout. Its close button closes the roster and clears the selection; selecting an empty area does the
same. Right-drag over any destination, including fogged or uncharted terrain, to send the selected
group there. Shift-right-drag adds further destinations to the end of the route. Each team mate's
route is shown with connected ground lines and waypoint markers visible to its owner. A normal
right-drag replaces the existing route.

Open a Habitat to view its roster beside the normal roboport GUI. The roster contains exactly one
row for each Team mate item stored in that Habitat. Each role dropdown includes an identifying icon
and starts at Waiting. Choosing Logistics, a resource-specific Miner role, Security, Builder, or
Scout consumes that stored item and deploys the team mate with the selected role. Deployed team
mates are no longer stored and therefore do not appear in the Habitat inventory or roster.

The Team Mate Mining technology is researched automatically and unlocks Iron Miner, Copper Miner,
Coal Miner, and Stone Miner roles. Choose the resource when deploying a stored team mate from its
Habitat roster. No token needs to be crafted.

Assigned workers find the nearest matching resource covered by the logistic network they are
currently part of and mine one item at the normal player rate until they have a 50-item load or
exhaust the resource. If their network covers no matching resource, miners return to a Habitat and
keep looking; placing a roboport or Habitat immediately triggers a new search, so
extending their network over a patch puts them to work at once. Miners deliver only to covered
buildings that are actively requesting their resource; they no longer choose the closest furnace.
Manual routes take priority over role work while they are active. While mining, team mates display
the native player mining animation and play the vanilla mining strike sound for each item. Changing
a miner to another role drops its carried resource at its current position; reselecting the same
mining role preserves its cargo and current work.

Security team mates defend a 48-tile radius around their assigned Habitat and return to it when no
enemy is present. Builders find entity ghosts inside their current logistic network, collect the
required building item and quality from network storage, walk to the construction site, and revive
the ghost. They also follow normal force-specific deconstruction orders inside Habitat logistic
coverage or normal roboport construction coverage, including neutral resources, trees, and rocks.
They walk to each marked entity, mine it, and carry the entity and its contents to logistic storage
without losing item quality. If no storage can accept deconstruction cargo, every resulting loose
item is automatically marked for collection and left in full stacks until storage becomes
available. Builders also collect loose ground items marked manually within the same coverage when
network storage can accept them. They must stand over a loose stack before picking it up and move
adjacent to the collision box of marked resources, belts, trees, rocks, and buildings before mining
them.
Cancelled orders and jobs claimed by native robots are released. Idle Builders enter a Habitat
without losing their role, remain listed as Builders in its roster, automatically deploy when a
covered construction or deconstruction job is available, and redock after finishing. Unused material
and mined cargo are returned if an order disappears or their role changes. Scouts use
command-tool destinations and queued waypoints to travel into distant terrain, progressively
generating a path and charting the area with their native radar before returning to their Habitat.

Stone, steel, and electric furnaces are converted into recipe-selecting machines: open a furnace
and choose its smelting recipe like an assembler. The chosen recipe drives the furnace's automatic
ingredient and fuel requests, so miners and haulers deliver to it before any ore has ever been
inserted. Burner buildings request fuel that assigned miners are collecting as well as fuel already
stored in network chests.

Team mates deployed with the Logistics role work as ground-based logistic bots while inside a
logistic network.
They collect requested items from active or passive provider, storage, and buffer chests, then walk
them to covered buildings. Assemblers, furnaces, and rocket silos automatically request missing
item ingredients for their current recipe. Burner-powered buildings automatically request
compatible fuel through an attached logistic requester. These are normal network requests, so
vanilla logistic robots and team mates can both service them. Delivered items are transferred from
the requester into the building's input or fuel inventory. If a destination changes or fills while
a team mate delivery is in progress, the team mate returns the cargo to logistic storage. Fluid
ingredients are not carried. Each team mate has an invisible logistic interface that follows it,
making it an engine-recognized member of the current network without changing its player-shaped
unit movement.

Team mate actions use a fixed priority: manual routes, nearby enemy combat, assigned job roles,
and then default logistics. Higher-priority actions pause logistics. If a team mate is carrying
logistics cargo when a job role becomes active, it returns that cargo to logistic storage before
resuming the role.

The logistic-network GUI is enabled from the start. A Habitat consumes no power, stores no robots,
and cannot charge robots; it creates logistic-network coverage and has one material slot for a
single stack of 20 team mate items. Additional Habitats are available from the start and cost 5
wood. Habitats are never placed automatically.

Scouts progressively generate hidden chunks ahead for native pathfinding without revealing the
destination in advance. A route ends when a team mate reaches its final waypoint; team mates are
never teleported or automatically returned to the player. Each team mate has native radar coverage
that keeps a 5×5 chunk area centered on its current chunk visible to its force and gives it a
consistent friendly map marker.

## Install for development

Place this folder in Factorio's `mods` directory. On Windows, the default location is:

```text
%APPDATA%\Factorio\mods\not-alone
```

Enable **Not Alone** in Factorio's Mods menu, then restart the game when prompted.