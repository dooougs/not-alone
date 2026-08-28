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

The Iron Miner technology is researched automatically and unlocks the Iron Miner role. Select team mates by putting the
**Team mate command tool** in your cursor, dragging over the units, and releasing. The role panel
shows the selected count; click **Assign Iron Miner** to assign the role. No token needs to be crafted.
Assigned workers find the nearest iron ore within 128 tiles, simulate mining a 50-ore load,
walk to the nearest furnace that accepts iron ore, deliver it, and repeat. Manual routes take priority
over role work while they are active. While mining, they display the native player mining animation.

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