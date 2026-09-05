-- Functional area extracted from not-alone.lua.

function get_ghost_item(ghost)
  if not ghost or not ghost.valid or ghost.type ~= "entity-ghost" then
    return nil
  end
  for key, item in pairs(ghost.ghost_prototype.items_to_place_this or {}) do
    return {
      name = item.name or key,
      quality = ghost.quality.name
    }
  end
  return nil
end

function find_builder_source(network, item, position)
  if not network then
    return nil
  end
  local item_name = type(item) == "table" and item.name or item
  local pickup_point = network.select_pickup_point({
    name = item_name,
    position = position,
    include_buffers = true
  })
  local source = pickup_point and pickup_point.owner
  local inventory = get_logistics_source_inventory(source)
  if inventory and inventory.get_item_count(item_name) > 0 then
    return source
  end
  local nearest_source
  local nearest_distance
  local function consider(candidate)
    local candidate_inventory = get_logistics_source_inventory(candidate)
    if candidate_inventory and candidate_inventory.get_item_count(item_name) > 0 then
      local distance = distance_squared(position, candidate.position)
      if not nearest_distance or distance < nearest_distance then
        nearest_source = candidate
        nearest_distance = distance
      end
    end
  end
  for _, furnace in pairs(get_network_furnaces(network)) do
    consider(furnace)
  end
  -- The engine's pickup-point selection can miss stock that is only sitting
  -- in other providers/storages; fall back to the same broad scan used to
  -- validate the plan so execution never fails on stock the plan counted.
  if not nearest_source then
    for _, provider in pairs(network.providers) do
      consider(provider)
    end
  end
  if not nearest_source then
    for _, storage_entity in pairs(network.storages) do
      consider(storage_entity)
    end
  end
  return nearest_source
end

function get_recipe_product(recipe, item_name)
  for _, product in pairs(recipe.products or {}) do
    if (not product.type or product.type == "item") and product.name == item_name then
      return product
    end
  end
  return nil
end

function get_product_amount(product)
  return math.max(1, math.floor(product.amount or product.minimum or 1))
end

-- Prototypes never change mid-session; index hand-craftable recipes by
-- product once instead of scanning every recipe per planner lookup.
recipes_by_product = nil

function get_recipes_by_product()
  if recipes_by_product then
    return recipes_by_product
  end
  recipes_by_product = {}
  for _, recipe in pairs(prototypes.recipe) do
    if not recipe.hidden_from_player_crafting
      and recipe.allow_as_intermediate ~= false then
      for _, product in pairs(recipe.products or {}) do
        if not product.type or product.type == "item" then
          local list = recipes_by_product[product.name] or {}
          list[#list + 1] = recipe
          recipes_by_product[product.name] = list
        end
      end
    end
  end
  for _, list in pairs(recipes_by_product) do
    table.sort(list, function(left, right)
      return left.energy < right.energy
    end)
  end
  return recipes_by_product
end

function find_hand_crafting_recipe(item_name, force)
  local recipes = {}
  for _, recipe in ipairs(get_recipes_by_product()[item_name] or {}) do
    local force_recipe = force.recipes[recipe.name]
    if force_recipe and force_recipe.enabled then
      recipes[#recipes + 1] = recipe
    end
  end
  return recipes
end

function plan_builder_item(network, item, force, available, visiting, actions)
  local item_name = item.name
  local needed = item.count or 1
  local in_network = available[item_name] or 0
  if in_network > 0 then
    local fetched = math.min(in_network, needed)
    available[item_name] = in_network - fetched
    actions[#actions + 1] = {type = "fetch", item = {
      name = item_name,
      quality = item.quality or "normal"
    }, count = fetched}
    needed = needed - fetched
    if needed == 0 then
      return true
    end
  end

  if visiting[item_name] then
    return false
  end
  visiting[item_name] = true
  local recipes = find_hand_crafting_recipe(item_name, force)
  for _, recipe in ipairs(recipes) do
    local recipe_available = {}
    for name, count in pairs(available) do
      recipe_available[name] = count
    end
    local product = get_recipe_product(recipe, item_name)
    local output_count = get_product_amount(product)
    local batches = math.ceil(needed / output_count)
    local recipe_actions = {}
    local possible = true
    for _, ingredient in pairs(recipe.ingredients or {}) do
      if ingredient.type and ingredient.type ~= "item" then
        possible = false
        break
      end
      local ingredient_count = math.ceil((ingredient.amount or 1) * batches)
      if not plan_builder_item(
        network,
        {name = ingredient.name, count = ingredient_count},
        force,
        recipe_available,
        visiting,
        recipe_actions
      ) then
        possible = false
        break
      end
    end
    if possible then
      for name, count in pairs(recipe_available) do
        available[name] = count
      end
      for _, action in pairs(recipe_actions) do
        actions[#actions + 1] = action
      end
      actions[#actions + 1] = {
        type = "craft",
        recipe = recipe,
        ingredients = recipe.ingredients,
        batches = batches,
        product = {name = item_name, quality = item.quality or "normal"},
        count = output_count * batches,
        craft_ticks = math.max(1, math.ceil(recipe.energy * 60 * batches))
      }
      visiting[item_name] = nil
      return true
    end
  end
  visiting[item_name] = nil
  return false
end

function find_builder_plan(network, item, force, contents)
  local available = {}
  for _, stack in pairs(contents or get_logistics_contents(network)) do
    local stack_quality = stack.quality
    if type(stack_quality) ~= "string" then
      stack_quality = stack_quality.name
    end
    if stack_quality == (item.quality or "normal") then
      available[stack.name] = (available[stack.name] or 0) + stack.count
    end
  end
  local actions = {}
  if plan_builder_item(network, item, force, available, {}, actions) then
    return actions
  end
  return nil
end

function builder_plan_has_valid_sources(network, plan)
  if not network or not plan then
    return false
  end
  -- Sum what is actually withdrawable; no single chest needs to hold an
  -- action's full count on its own.
  local available = {}
  local seen = {}
  local function add_source(source)
    if source and source.valid and source.unit_number and not seen[source.unit_number] then
      seen[source.unit_number] = true
      local inventory = get_logistics_source_inventory(source)
      for _, item in pairs(inventory and inventory.get_contents() or {}) do
        available[item.name] = (available[item.name] or 0) + item.count
      end
    end
  end
  for _, source in pairs(network.providers) do
    add_source(source)
  end
  for _, source in pairs(network.storages) do
    add_source(source)
  end
  for _, furnace in pairs(get_network_furnaces(network)) do
    add_source(furnace)
  end
  for _, action in ipairs(plan) do
    if action.type == "fetch" then
      local name = action.item.name
      if (available[name] or 0) < action.count then
        return false
      end
      available[name] = available[name] - action.count
    end
  end
  return true
end

