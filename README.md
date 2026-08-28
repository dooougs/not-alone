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
units, so they use the engine's pathfinder to navigate around obstacles. Team mates hold their
position and engage nearby enemies until ordered elsewhere. Their built-in ranged attack uses
pistol-like physical damage.

Factorio units do not have character gun or ammunition inventories. The unit conversion therefore
replaces copied starter equipment and ammunition depletion with a built-in attack.

Each player receives a **Team mate command tool**. Drag with the tool to select a group of your own
team mates, then right-drag over a destination to send that group there. A destination order ends
when a team mate arrives; team mates are never teleported or automatically returned to the player.
As team mates travel, each map chunk they enter is revealed for their force, allowing commanded
groups to explore previously uncharted areas.

## Install for development

Place this folder in Factorio's `mods` directory. On Windows, the default location is:

```text
%APPDATA%\Factorio\mods\not-alone
```

Enable **Not Alone** in Factorio's Mods menu, then restart the game when prompted.