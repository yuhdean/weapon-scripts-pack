local droppedWeapons = {}
local nextDroppedWeaponId = 0
local droppedWeaponLifetimeMs = 1800000

local function removeDroppedWeapon(dropId)
  if not droppedWeapons[dropId] then
    return
  end

  droppedWeapons[dropId] = nil
  TriggerClientEvent('wsp:removeDroppedWeapon', -1, dropId)
end

local function clearAllDroppedWeapons()
  for dropId in pairs(droppedWeapons) do
    removeDroppedWeapon(dropId)
  end
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

RegisterCommand('cleargundrops', function(source)
  clearAllDroppedWeapons()

  if source == 0 then
    print('[weapon-script-pack] Cleared all dropped guns.')
  else
    TriggerClientEvent('ox_lib:notify', source, {
      title = 'Gun Drops Cleared',
      description = 'All dropped guns have been removed.',
      type = 'success',
      position = 'center-right'
    })
  end
end, true)
