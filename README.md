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
you want the initial logistic network, open it, then use **Deploy team mate** in its roster to
consume one item and deploy a player-shaped team mate. Team mate items stack to 20. Deployed units are
native Factorio units, so they use the engine's pathfinder to navigate around obstacles. When
team mates have no route, role work, enemy, or logistics job, they return to the nearest Habitat and
wait there. While a route is active, they follow its destinations in order. Their built-in ranged
attack uses pistol-like physical damage.

Factorio units do not have character gun or ammunition inventories. The unit conversion therefore
replaces copied starter equipment and ammunition depletion with a built-in attack.

Each player receives a **Team mate command tool**. Drag with the tool to select a group of your own
team mates, then right-drag over any destination, including fogged or uncharted terrain, to send that
group there. Shift-right-drag adds further destinations to the end of the route. Each team mate's
route is shown with connected ground lines and waypoint markers visible to its owner. A normal
right-drag replaces the existing route.

Open a Habitat to view its roster beside the normal roboport GUI. Team mates deployed near a
Habitat become its residents. Select team mates with the command tool and use **Assign selected
here** to move them to another Habitat. Each roster row assigns Logistics, a resource-specific
Miner role, Security, Builder, or Scout.

The Team Mate Mining technology is researched automatically and unlocks Iron Miner, Copper Miner,
Coal Miner, and Stone Miner roles. Use each resident's role dropdown in its Habitat roster to choose
the resource. No token needs to be crafted.

Assigned workers find the nearest matching resource covered by the logistic network they are
currently part of and mine one item at the normal player rate until they have a 50-item load or
exhaust the resource. If their network covers no matching resource, miners return to a Habitat and
keep looking; placing a roboport or Habitat immediately triggers a new search, so
extending their network over a patch puts them to work at once. Miners deliver only to covered
buildings that are actively requesting their resource; they no longer choose the closest furnace.
Manual routes take priority over role work while they are active. While mining, team mates display
the native player mining animation and play the vanilla mining strike sound for each item.

Security team mates defend a 48-tile radius around their assigned Habitat and return to it when no
enemy is present. Builders find entity ghosts inside their current logistic network, collect the
required building item from network storage, and construct the ghost; unused material is returned
if the order disappears or their role changes. Scouts use command-tool destinations and queued
waypoints to travel into distant terrain, progressively generating a path and charting the area
with their native radar before returning to their Habitat.

Stone, steel, and electric furnaces are converted into recipe-selecting machines: open a furnace
and choose its smelting recipe like an assembler. The chosen recipe drives the furnace's automatic
ingredient and fuel requests, so miners and haulers deliver to it before any ore has ever been
inserted. Burner buildings request fuel that assigned miners are collecting as well as fuel already
stored in network chests.

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