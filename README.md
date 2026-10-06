# Not Alone

A Factorio 2.1 mod. You didn't crash-land alone: Miners mine, Builders build, Carriers haul and
Soldiers defend, turning a handful of survivors into a working part of the factory.

## Getting started

Crash-landed ships are scattered across the map, with one guaranteed near the spawn. Each wreck holds
a few stranded team mates as items. Craft a **Habitat** (5 wood), place it, and put team mate items
in it. Every player also gets the **Soldier command tool**, which can be recreated from the shortcut
bar.

Team mates are native Factorio units that use the engine's pathfinder. Each one has a small radar
footprint that keeps the area around it charted, and a map marker.

## Bases

**Habitat.** An unpowered roboport that projects logistic-network coverage, stores no robots and
charges nothing. Its single material slot holds docked team mates as real items, so they count in
network totals. Idle team mates walk to the nearest Habitat with room and dock. Docked team mates
deploy automatically whenever there is work for their role inside the network.

**Outpost** (50 steel plate). A Soldier-only base. Set how many Soldiers it should have and Soldiers
travel from other bases to fill the request, then stand guard and wander nearby.

Opening a Habitat or Outpost shows its stationed team mates, per-role request counts that pull team
mates from other bases, and your inventory so you can move team mate items in and out.

**Cloner.** Crafts new team mates. Each recipe takes a Miner plus iron ore, copper ore, coal and
uranium ore and returns the Miner along with a new Miner, Builder, Carrier or Soldier.

## Roles

**Miner** (orange). Mines resources you mark with a deconstruction planner inside its network, at
normal hand-mining speed, in loads of up to 50, and delivers the ore to buildings that are requesting
it. Alt-deconstruct unmarks resources.

**Carrier** (blue). A walking logistic robot. Picks up from provider, storage and buffer chests and
delivers to any requester in the network, including the hidden requesters described below.

**Builder** (gold). Builds ghosts using items from network storage, hand-crafting simple items when
needed, fills the ammo, fuel, modules and equipment those ghosts request, and handles deconstruction
orders, including trees, rocks and marked ground items. Cargo goes to storage chests, so the network
needs at least one. Builders also repair damaged buildings and fish from the shore. A Builder that
can't reach a target releases it for others and retries later.

**Soldier** (red). Defends its network and follows orders. See the next section.

## Soldiers

**Weapons and armor.** Soldiers collect guns, ammo and armor from network storage. Every gun and ammo
type is read from the game's prototypes, so vanilla, Space Age (tesla gun, railgun) and modded weapons
all work. A Soldier fights with the best gun it has ammo for, falls back gun by gun as ammo runs out,
and punches only as a last resort. Soldiers never fire atomic bombs or capture rockets.

**Armor equipment.** In modular, power, MK2 or mech armor, a Soldier fills the equipment grid the way
a player would. It plans a power-balanced loadout from what it carries and what the network stocks
(generators, solar, batteries, shields, exoskeletons, personal lasers, discharge defense, personal
roboports, night vision and more, including modded equipment), then fetches the missing pieces.
Shields absorb damage, exoskeletons add speed, lasers and discharge defense fire on their own.
Personal roboports carry construction bots and repair packs that repair the Soldier, its squad and
nearby buildings.

**Capsules.** Soldiers keep a stock of combat robot capsules (destroyer, distractor, defender and
modded equivalents) and throw them at packs of enemies and at nests.

**Retreat.** A Soldier below 30% health, or one whose guns are all empty while the network still has
ammo, pulls back to the nearest Habitat or Outpost. It heals faster there and restocks, then returns to
its route or post once it is back above 90%. It still fights anything that attacks the base.

**Outpost defenses.** Idle Soldiers stationed at an Outpost build turret, wall, gate and land mine
ghosts within 32 tiles of it, using items from network storage, and refill any ammo turret there that
drops below 10 rounds.

**Orders.** With the Soldier command tool:

- Drag to select your Soldiers. Left-click a waypoint marker to select the Soldiers on that route.
- Right-drag to send them to a spot. Shift-right-drag adds waypoints; closing a route back on its
  first waypoint makes a looping patrol.
- Right-click a team mate directly to pick it up into your inventory.

Soldiers attack enemies they meet on the way and then resume their route. They also engage hostile
players and other forces' team mates, respecting cease-fire settings.

**Vehicles.** Soldiers use cars, tanks and spidertrons from network storage for long trips and
patrols, refuelling and rearming them as needed. Other roles can use cars.

## Logistics changes

- Assemblers, furnaces, labs, rocket silos and burner buildings inside a network get a hidden
  requester that asks for their missing ingredients and fuel. Vanilla logistic robots and Carriers
  both serve these requests.
- Stone, steel and electric furnaces let you pick a recipe like an assembler, so they can request ore
  before any has arrived.
- The logistic-network GUI is available from the start. Logistic chests are unlocked by Electronics
  and cost one iron chest.
- Opening a logistic network shows a Team mates panel with deployed and docked counts per role.

## Settings

- **Car minimum distance** (runtime, default 60 tiles): trips shorter than this are walked.

## Install for development

Place this folder in Factorio's `mods` directory. On Windows, the default location is:

```text
%APPDATA%\Factorio\mods\not-alone
```

Enable **Not Alone** in Factorio's Mods menu, then restart the game when prompted.
`build-release.ps1` builds a release zip from `info.json`'s version.
