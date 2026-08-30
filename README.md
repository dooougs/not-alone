# Not Alone

A basic mod skeleton for Factorio 2.1.

## Structure

- `info.json` contains the mod metadata and dependencies.
- `data.lua` is the entry point for prototype definitions.
- `control.lua` is the entry point for runtime event handlers.
- `poc.lua` contains experimental proof-of-concept runtime behavior.
- `locale/en/not-alone.cfg` contains English localization.

## Current proof of concept

When a player is created, ten player-shaped **team mates** spawn nearby. They are native Factorio
units, so they use the engine's pathfinder to navigate around obstacles. When team mates have no
destination or queued waypoint remaining, they wander freely and engage nearby enemies. While a
route is active, they follow its destinations in order without wandering. Their built-in ranged
attack uses pistol-like physical damage.

Factorio units do not have character gun or ammunition inventories. The unit conversion therefore
replaces copied starter equipment and ammunition depletion with a built-in attack.

Each player receives a **Team mate command tool**. Drag with the tool to select a group of your own
team mates, then right-drag over any destination, including fogged or uncharted terrain, to send that
group there. Shift-right-drag adds further destinations to the end of the route. Each team mate's
route is shown with connected ground lines and waypoint markers visible to its owner. A normal
right-drag replaces the existing route.

Use **Add Team Mate** in the role panel to spawn additional teammates near your character, one per
click.

The Team Mate Mining technology is researched automatically and unlocks Iron Miner, Copper Miner,
Coal Miner, and Stone Miner roles. Select team mates by putting the **Team mate command tool** in
your cursor, dragging over the units, and releasing. The role panel shows the selected count; use
one of the **Assign Miner** controls to choose the resource. No token needs to be crafted.

Assigned workers find the nearest matching resource covered by the logistic network they are
currently part of and mine one item at the normal player rate until they have a 50-item load or
exhaust the resource. If their network covers no matching resource, miners wander and keep
looking; placing a roboport or Logistics coverage hub immediately triggers a new search, so
extending their network over a patch puts them to work at once. Miners deliver only to covered
buildings that are actively requesting their resource; they no longer choose the closest furnace.
Manual routes take priority over role work while they are active. While mining, team mates display
the native player mining animation and play the vanilla mining strike sound for each item.

Unassigned team mates also work as ground-based logistic bots while inside a logistic network.
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

Each force starts with one **Logistics coverage hub** just south of its spawn. The initial team
mates spawn inside its 25-tile logistic radius, and the logistic-network GUI is enabled from the
start. The hub consumes no power, stores no robots or materials, and cannot charge robots; it only
creates logistic-network coverage. Additional hubs are available from the start and cost 5 wood.

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