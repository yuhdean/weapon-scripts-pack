local droppedWeapons = {}
local nextDroppedWeaponId = 0
local droppedWeaponLifetimeMs = 120000
local droppedWeaponDespawnRadius = 75.0

local function removeDroppedWeapon(dropId)
  if not droppedWeapons[dropId] then
    return
  end

  droppedWeapons[dropId] = nil
  TriggerClientEvent('wsp:removeDroppedWeapon', -1, dropId)
end

local function isAnyPlayerNearDrop(dropData)
  for _, playerId in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(playerId)

    if ped and ped ~= 0 then
      local coords = GetEntityCoords(ped)
      local dx = coords.x - dropData.coords.x
      local dy = coords.y - dropData.coords.y
      local dz = coords.z - dropData.coords.z
      local distance = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

      if distance <= droppedWeaponDespawnRadius then
        return true
      end
    end
  end

  return false
end

RegisterNetEvent('wsp:createDroppedWeapon')
AddEventHandler('wsp:createDroppedWeapon', function(dropData)
  if type(dropData) ~= 'table' then
    return
  end

  nextDroppedWeaponId = nextDroppedWeaponId + 1

  local dropId = nextDroppedWeaponId
  local storedDrop = {
    weaponHash = dropData.weaponHash,
    weaponModel = dropData.weaponModel,
    ammo = dropData.ammo or 0,
    clipAmmo = dropData.clipAmmo or 0,
    spawnCoords = dropData.spawnCoords,
    coords = dropData.coords,
    heading = dropData.heading or 0.0,
    force = dropData.force or { x = 0.0, y = 0.0, z = 0.0 },
    frozen = dropData.frozen == true,
  }

  if type(storedDrop.coords) ~= 'table' or type(storedDrop.spawnCoords) ~= 'table' then
    return
  end

  droppedWeapons[dropId] = storedDrop
  TriggerClientEvent('wsp:registerDroppedWeapon', -1, dropId, storedDrop)

  SetTimeout(droppedWeaponLifetimeMs, function()
    removeDroppedWeapon(dropId)
  end)
end)

RegisterNetEvent('wsp:pickupDroppedWeapon')
AddEventHandler('wsp:pickupDroppedWeapon', function(dropId)
  local src = source
  local dropData = droppedWeapons[dropId]

  if not dropData then
    return
  end

  removeDroppedWeapon(dropId)
  TriggerClientEvent('wsp:giveDroppedWeapon', src, dropData.weaponHash, dropData.ammo or 0, dropData.clipAmmo or 0)
end)

RegisterNetEvent('wsp:requestDroppedWeapons')
AddEventHandler('wsp:requestDroppedWeapons', function()
  local src = source

  if next(droppedWeapons) then
    TriggerClientEvent('wsp:syncDroppedWeapons', src, droppedWeapons)
  end
end)

CreateThread(function()
  while true do
    Wait(10000)

    for dropId, dropData in pairs(droppedWeapons) do
      if not isAnyPlayerNearDrop(dropData) then
        removeDroppedWeapon(dropId)
      end
    end
  end
end)
