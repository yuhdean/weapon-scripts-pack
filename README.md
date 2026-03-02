# weapon-scripts-pack
A variety pack of multiple functions revolving around weapons.

## Functionality
- `/dropweapon` will drop the currently held weapon onto the floor
- `/placeweapon` will allow the user to manually place the dropped weapon
- When the player goes into a ragdoll state (falling, tripped, etc.), they will drop their weapon.
- Any weapon dropped or placed is able to be picked up by any players.
- Any dropped weapons will despawn if all players leave the area.

## Dependencies
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)

## Possible Functionality
- I've used this script to also trigger a dropped weapon when the player puts their hands up, however, this is done via your server's emote system. Personally, I used [dpemotes](https://github.com/andristum/dpemotes), if you want that functionality in your server that uses dpemotes, you can download my fork of it [here](https://github.com/yuhdean/dpemotes-handsup).
- You can use this script in any other scripts or events you might want, just code this in: `TriggerEvent('wsp:dropHeldGunToGround')`.
