local utils = {}

function utils.distance_squared(first, second)
  local delta_x = first.x - second.x
  local delta_y = first.y - second.y
  return delta_x * delta_x + delta_y * delta_y
end

function utils.distance_squared_to_box(position, box)
  local delta_x = math.max(box.left_top.x - position.x, 0, position.x - box.right_bottom.x)
  local delta_y = math.max(box.left_top.y - position.y, 0, position.y - box.right_bottom.y)
  return delta_x * delta_x + delta_y * delta_y
end

function utils.position_table(position)
  return {x = position.x, y = position.y}
end

return utils
