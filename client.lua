local wasPlayerRagdoll = false
local wasPlayerFalling = false
local droppedWeapons = {}
local droppedWeaponTargetDistance = 1.5
local droppedWeaponTargetZoneRadius = 1.0
local pickupAnim = true
local pickupAnimName = 'e pickup'
local placementMaxDistance = 12.0
local placementMinDistance = 1.0
local placementStep = 0.1
local placementHeightStep = 0.02
local placementRotationStep = 2.5

local longarmGroups = {
  [GetHashKey('GROUP_RIFLE')] = true,
  [GetHashKey('GROUP_MG')] = true,
  [GetHashKey('GROUP_SHOTGUN')] = true,
  [GetHashKey('GROUP_SNIPER')] = true,
  [GetHashKey('GROUP_HEAVY')] = true,
}

local function loadModelHash(modelHash)
  RequestModel(modelHash)

  while not HasModelLoaded(modelHash) do
    Wait(10)
  end
end

local function rotationToDirection(rotation)
  local rotZ = math.rad(rotation.z)
  local rotX = math.rad(rotation.x)
  local cosX = math.abs(math.cos(rotX))

  return vec3(-math.sin(rotZ) * cosX, math.cos(rotZ) * cosX, math.sin(rotX))
end

local function getPlacementCoords(maxDistance)
  local gameplayCamCoord = GetGameplayCamCoord()
  local cameraRotation = GetGameplayCamRot(2)
  local direction = rotationToDirection(cameraRotation)
  local destination = gameplayCamCoord + (direction * (maxDistance or 5.0))
  local shapeTest = StartShapeTestRay(
    gameplayCamCoord.x,
    gameplayCamCoord.y,
    gameplayCamCoord.z,
    destination.x,
    destination.y,
    destination.z,
    511,
    PlayerPedId(),
    7
  )
  local _, hit, endCoords = GetShapeTestResult(shapeTest)

  if hit == 1 then
    return {
      x = endCoords.x,
      y = endCoords.y,
      z = endCoords.z
    }
  end

  return {
    x = destination.x,
    y = destination.y,
    z = destination.z
  }
end

local function getPlacementPoint(distance)
  local ped = PlayerPedId()
  local pedCoords = GetEntityCoords(ped)
  local rawCoords = getPlacementCoords(distance)
  local target = vec3(rawCoords.x, rawCoords.y, rawCoords.z)
  local offset = target - pedCoords

  if #offset > placementMaxDistance then
    target = pedCoords + (offset / #offset) * placementMaxDistance
  end

  return {
    x = target.x,
    y = target.y,
    z = target.z
  }
end

local function getPlacementDistanceFromLook()
  local pedCoords = GetEntityCoords(PlayerPedId())
  local lookCoords = getPlacementPoint(placementMaxDistance)
  local target = vec3(lookCoords.x, lookCoords.y, lookCoords.z)
  local distance = #(target - pedCoords)

  return math.min(placementMaxDistance, math.max(placementMinDistance, distance))
end

local function getSelectedWeapon()
  local weaponHash = GetSelectedPedWeapon(PlayerPedId())

  if not weaponHash or weaponHash == GetHashKey('WEAPON_UNARMED') then
    return nil
  end

  return weaponHash
end

local function notifyNoWeapon()
  lib.notify({
    title = 'No Weapon',
    description = 'You are not holding a weapon.',
    type = 'error',
    position = 'center-right'
  })
end

local function isLongarmWeapon(weaponHash)
  if not weaponHash then
    return false
  end

  return longarmGroups[GetWeapontypeGroup(weaponHash)] == true
end

local function getDroppedWeaponClipAmmo(playerPed, weaponHash, ammoCount)
  if not ammoCount or ammoCount <= 0 then
    return 0
  end

  local _, maxClipAmmo = GetMaxAmmoInClip(playerPed, weaponHash, true)

  if maxClipAmmo and maxClipAmmo > 0 then
    return math.min(ammoCount, maxClipAmmo)
  end

  return ammoCount
end

local function removeDroppedWeaponTarget(dropData)
  if not dropData then
    return
  end

  if dropData.entity and dropData.targetName then
    exports.ox_target:removeLocalEntity(dropData.entity, dropData.targetName)
  end

  if dropData.zoneId then
    exports.ox_target:removeZone(dropData.zoneId, true)
    dropData.zoneId = nil
  end
end

local function removeDroppedWeaponEntry(dropId, shouldDeleteEntity)
  local dropData = droppedWeapons[dropId]

  if not dropData then
    return
  end

  removeDroppedWeaponTarget(dropData)

  if shouldDeleteEntity and dropData.entity and DoesEntityExist(dropData.entity) then
    DeleteEntity(dropData.entity)
  end

  droppedWeapons[dropId] = nil
end

local function registerDroppedWeaponPickup(dropId, dropData)
  dropData.targetName = ('weaponscriptpack_pickup_%s'):format(dropId)

  if dropData.entity and DoesEntityExist(dropData.entity) then
    exports.ox_target:addLocalEntity(dropData.entity, {
      {
        name = dropData.targetName,
        icon = 'fa-solid fa-gun',
        label = 'Pick Up Weapon',
        distance = droppedWeaponTargetDistance,
        onSelect = function()
          TriggerServerEvent('wsp:pickupDroppedWeapon', dropId)
        end
      }
    })
  end

  local targetCoords = dropData.coords

  if dropData.entity and DoesEntityExist(dropData.entity) then
    local entityCoords = GetEntityCoords(dropData.entity)
    targetCoords = {
      x = entityCoords.x,
      y = entityCoords.y,
      z = entityCoords.z
    }
    dropData.coords = targetCoords
  end

  if dropData.zoneId then
    exports.ox_target:removeZone(dropData.zoneId, true)
  end

  dropData.zoneId = exports.ox_target:addSphereZone({
    coords = vec3(targetCoords.x, targetCoords.y, targetCoords.z),
    radius = droppedWeaponTargetZoneRadius,
    debug = false,
    options = {
      {
        name = ('%s_zone'):format(dropData.targetName),
        icon = 'fa-solid fa-gun',
        label = 'Pick Up Weapon',
        distance = droppedWeaponTargetDistance,
        onSelect = function()
          TriggerServerEvent('wsp:pickupDroppedWeapon', dropId)
        end
      }
    }
  })
end

local function trackDroppedWeaponTarget(dropId, dropData)
  if dropData.trackingTarget then
    return
  end

  dropData.trackingTarget = true

  CreateThread(function()
    local lastCoords

    while droppedWeapons[dropId] == dropData do
      if not dropData.entity or not DoesEntityExist(dropData.entity) then
        break
      end

      local entityCoords = GetEntityCoords(dropData.entity)

      if not lastCoords or #(vec3(entityCoords.x, entityCoords.y, entityCoords.z) - vec3(lastCoords.x, lastCoords.y, lastCoords.z)) > 0.1 then
        dropData.coords = {
          x = entityCoords.x,
          y = entityCoords.y,
          z = entityCoords.z
        }
        registerDroppedWeaponPickup(dropId, dropData)
        lastCoords = dropData.coords
      end

      Wait(150)
    end

    dropData.trackingTarget = nil
  end)
end

local function spawnDroppedWeaponObject(dropId, dropData)
  if not dropData.weaponModel or dropData.weaponModel == 0 then
    registerDroppedWeaponPickup(dropId, dropData)
    return
  end

  loadModelHash(dropData.weaponModel)

  local weaponObject = CreateObjectNoOffset(
    dropData.weaponModel,
    dropData.spawnCoords.x,
    dropData.spawnCoords.y,
    dropData.spawnCoords.z,
    false,
    false,
    false
  )

  if weaponObject and weaponObject ~= 0 then
    dropData.entity = weaponObject
    SetEntityHeading(weaponObject, dropData.heading + 90.0)
    SetEntityCollision(weaponObject, true, true)
    SetEntityDynamic(weaponObject, not dropData.frozen)
    SetEntityHasGravity(weaponObject, not dropData.frozen)

    if dropData.frozen then
      FreezeEntityPosition(weaponObject, true)
    else
      ActivatePhysics(weaponObject)
      ApplyForceToEntity(
        weaponObject,
        1,
        dropData.force.x,
        dropData.force.y,
        dropData.force.z,
        0.0,
        0.0,
        0.0,
        0,
        false,
        true,
        true,
        false,
        true
      )
    end
    SetModelAsNoLongerNeeded(dropData.weaponModel)
    registerDroppedWeaponPickup(dropId, dropData)

    if not dropData.frozen then
      trackDroppedWeaponTarget(dropId, dropData)

      CreateThread(function()
        Wait(1500)

        if not droppedWeapons[dropId] or not DoesEntityExist(weaponObject) then
          return
        end

        local landedCoords = GetEntityCoords(weaponObject)
        dropData.coords = {
          x = landedCoords.x,
          y = landedCoords.y,
          z = landedCoords.z
        }

        registerDroppedWeaponPickup(dropId, dropData)
      end)
    end
  else
    registerDroppedWeaponPickup(dropId, dropData)
  end
end

local function dropWeaponWithOptions(options)
  local playerPed = PlayerPedId()
  local weaponHash = getSelectedWeapon()

  if not weaponHash then
    notifyNoWeapon()
    return false
  end

  local ammoCount = GetAmmoInPedWeapon(playerPed, weaponHash)
  local clipAmmo = getDroppedWeaponClipAmmo(playerPed, weaponHash, ammoCount)
  local weaponModel = GetWeapontypeModel(weaponHash)
  local placeMode = options and options.placeMode
  local spawnCoords

  if placeMode then
    spawnCoords = options.coords
  else
    local handCoords = GetPedBoneCoords(playerPed, 57005, 0.16, 0.03, 0.02)
    spawnCoords = {
      x = handCoords.x,
      y = handCoords.y,
      z = handCoords.z
    }
  end

  local coords = {
    x = spawnCoords.x,
    y = spawnCoords.y,
    z = spawnCoords.z
  }
  local force = { x = 0.0, y = 0.0, z = 0.0 }

  if not placeMode then
    local forwardVector = GetEntityForwardVector(playerPed)
    force = {
      x = forwardVector.x * 0.55,
      y = forwardVector.y * 0.55,
      z = -0.15
    }
  end

  SetCurrentPedWeapon(playerPed, GetHashKey('WEAPON_UNARMED'), true)
  RemoveWeaponFromPed(playerPed, weaponHash)

  TriggerServerEvent('wsp:createDroppedWeapon', {
    weaponHash = weaponHash,
    weaponModel = weaponModel,
    ammo = ammoCount,
    clipAmmo = clipAmmo,
    spawnCoords = spawnCoords,
    coords = coords,
    heading = (options and options.heading) or GetEntityHeading(playerPed),
    force = force,
    frozen = options and options.frozen or false
  })

  lib.notify({
    title = placeMode and 'Placed Gun' or 'Dropped Gun',
    description = placeMode and 'You placed your weapon down.' or 'You dropped your weapon on the ground.',
    type = 'inform',
    position = 'center-right'
  })

  return true
end

local function startWeaponPlacement()
  local playerPed = PlayerPedId()
  local weaponHash = getSelectedWeapon()

  if not weaponHash then
    return false
  end

  local weaponModel = GetWeapontypeModel(weaponHash)

  if not weaponModel or weaponModel == 0 then
    return false
  end

  loadModelHash(weaponModel)

  local previewObject = CreateObjectNoOffset(weaponModel, 0.0, 0.0, 0.0, false, false, false)

  if not previewObject or previewObject == 0 then
    SetModelAsNoLongerNeeded(weaponModel)
    return false
  end

  local distance = 2.0
  distance = getPlacementDistanceFromLook()
  local heightOffset = 0.0
  local heading = GetEntityHeading(playerPed) + 90.0
  local frozen = false
  local placing = true

  SetEntityCollision(previewObject, false, false)
  FreezeEntityPosition(previewObject, true)
  SetEntityAlpha(previewObject, 180, false)
  SetEntityAsMissionEntity(previewObject, true, true)
  lib.showTextUI('[E] Place  [Backspace] Cancel  [Mouse Wheel] Distance  [Left/Right] Rotate  [Up/Down] Height  [F] Freeze')

  while placing do
    local previewCoords = getPlacementPoint(distance)

    SetEntityCoordsNoOffset(previewObject, previewCoords.x, previewCoords.y, previewCoords.z + heightOffset, false, false, false)
    SetEntityHeading(previewObject, heading)

    if frozen then
      FreezeEntityPosition(previewObject, true)
    else
      FreezeEntityPosition(previewObject, false)
    end

    DrawMarker(2, previewCoords.x, previewCoords.y, previewCoords.z + heightOffset + 0.04, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.08, 0.08, 0.08, frozen and 0 or 255, frozen and 200 or 180, 255, 180, false, true, false, nil, nil, false)

    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 37, true)
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 141, true)
    DisableControlAction(0, 142, true)

    if IsControlJustPressed(0, 15) then
      distance = math.min(placementMaxDistance, distance + placementStep)
    elseif IsControlJustPressed(0, 14) then
      distance = math.max(placementMinDistance, distance - placementStep)
    end

    if IsControlPressed(0, 174) then
      heading = heading + placementRotationStep
    elseif IsControlPressed(0, 175) then
      heading = heading - placementRotationStep
    end

    if IsControlPressed(0, 172) then
      heightOffset = math.min(2.0, heightOffset + placementHeightStep)
    elseif IsControlPressed(0, 173) then
      heightOffset = math.max(-1.0, heightOffset - placementHeightStep)
    end

    if IsControlJustPressed(0, 23) then
      frozen = not frozen
      lib.hideTextUI()
      lib.showTextUI(('[E] Place  [Backspace] Cancel  [Mouse Wheel] Distance  [Left/Right] Rotate  [Up/Down] Height  [F] Freeze: %s'):format(frozen and 'On' or 'Off'))
    end

    if IsControlJustPressed(0, 38) then
      local finalCoords = GetEntityCoords(previewObject)

      DeleteEntity(previewObject)
      lib.hideTextUI()
      SetModelAsNoLongerNeeded(weaponModel)

      return dropWeaponWithOptions({
        placeMode = true,
        coords = {
          x = finalCoords.x,
          y = finalCoords.y,
          z = finalCoords.z
        },
        heading = heading,
        frozen = frozen
      })
    end

    if IsControlJustPressed(0, 177) then
      placing = false
    end

    Wait(0)
  end

  DeleteEntity(previewObject)
  lib.hideTextUI()
  SetModelAsNoLongerNeeded(weaponModel)
  return false
end

local function dropHeldGunToGround()
  return dropWeaponWithOptions()
end

RegisterNetEvent('wsp:dropHeldGunToGround')
AddEventHandler('wsp:dropHeldGunToGround', function()
  dropHeldGunToGround()
end)

RegisterCommand('dropweapon', function()
  TriggerEvent('wsp:dropHeldGunToGround')
end, false)

RegisterCommand('placeweapon', function()
  startWeaponPlacement()
end, false)

RegisterNetEvent('wsp:registerDroppedWeapon')
AddEventHandler('wsp:registerDroppedWeapon', function(dropId, dropData)
  removeDroppedWeaponEntry(dropId, true)
  droppedWeapons[dropId] = dropData
  spawnDroppedWeaponObject(dropId, dropData)
end)

RegisterNetEvent('wsp:removeDroppedWeapon')
AddEventHandler('wsp:removeDroppedWeapon', function(dropId)
  removeDroppedWeaponEntry(dropId, true)
end)

RegisterNetEvent('wsp:syncDroppedWeapons')
AddEventHandler('wsp:syncDroppedWeapons', function(drops)
  for dropId, dropData in pairs(drops) do
    if not droppedWeapons[dropId] then
      droppedWeapons[dropId] = dropData
      spawnDroppedWeaponObject(dropId, dropData)
    end
  end
end)

RegisterNetEvent('wsp:giveDroppedWeapon')
AddEventHandler('wsp:giveDroppedWeapon', function(weaponHash, ammo, clipAmmo)
  if pickupAnim and pickupAnimName and pickupAnimName ~= '' then
    ExecuteCommand(pickupAnimName)
  end

  CreateThread(function()
    Wait(1000)

    local playerPed = PlayerPedId()
    GiveWeaponToPed(playerPed, weaponHash, ammo or 0, false, true)
    SetPedAmmo(playerPed, weaponHash, ammo or 0)

    if clipAmmo and clipAmmo > 0 then
      SetAmmoInClip(playerPed, weaponHash, clipAmmo)
    end

    lib.notify({
      title = 'Picked Up Gun',
      description = 'You picked the weapon up.',
      type = 'success',
      position = 'center-right'
    })
  end)
end)

CreateThread(function()
  Wait(1000)
  TriggerServerEvent('wsp:requestDroppedWeapons')
end)

CreateThread(function()
  while true do
    local playerPed = PlayerPedId()
    local isRagdoll = IsPedRagdoll(playerPed)
    local isFalling = IsPedFalling(playerPed)
    local selectedWeapon = getSelectedWeapon()

    if isRagdoll and not wasPlayerRagdoll and not IsPedVaulting(playerPed) and isLongarmWeapon(selectedWeapon) then
      dropHeldGunToGround()
    elseif isFalling and not wasPlayerFalling and not isRagdoll and not IsPedVaulting(playerPed) and isLongarmWeapon(selectedWeapon) then
      dropHeldGunToGround()
    end

    wasPlayerRagdoll = isRagdoll
    wasPlayerFalling = isFalling
    Wait(0)
  end
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then
    return
  end

  for dropId in pairs(droppedWeapons) do
    removeDroppedWeaponEntry(dropId, true)
  end
end)
