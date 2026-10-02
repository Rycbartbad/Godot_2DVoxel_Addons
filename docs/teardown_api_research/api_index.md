# Teardown API 速查索引（609 函数）

> 生成自官方 api.xml（API 2.1.0 ／ 游戏 2.1.0.2）。
> `[S]` = server only，`[C]` = client only，`?` = 可选参数。
> 详细参数说明见 [teardown_api_full.md](teardown_api_full.md)。


## Parameters（5）

```
value = GetIntParam(name, default)
value = GetFloatParam(name, default)
value = GetBoolParam(name, default)
value = GetStringParam(name, default)
value = GetColorParam(name, default)
```

## Script control（22）

```
version = GetVersion()
match = HasVersion(version)
time = GetTime()
dt = GetTimeStep()
name = InputLastPressedKey(playerId?)
pressed = InputPressed(input, playerId?)
pressed = InputReleased(input, playerId?)
pressed = InputDown(input, playerId?)
value = InputValue(input, playerId?)
InputClear() [C]
InputResetOnTransition() [C]
value = LastInputDevice()
SetValue(variable, value, transition?, time?)
SetValueInTable(tableId, memberName, newValue, type, length)
clicked = PauseMenuButton(title, location?, disabled?)
exists = HasFile(path)
StartLevel(mission, path, layers?, passThrough?)
SetPaused(paused)
Restart()
Menu()
ClientCall(playerId, function, param1, param2, .., paramN?)
ServerCall(function, param1, param2, .., paramN?)
```

## Registry（17）

```
ClearKey(key)
children = ListKeys(parent)
exists = HasKey(key)
SetInt(key, value, sync?)
value = GetInt(key)
SetFloat(key, value, sync?)
value = GetFloat(key)
SetBool(key, value, sync?)
value = GetBool(key)
SetString(key, value, sync?)
value = GetString(key)
SetColor(key, r, g, b, a?)
r,g,b,a = GetColor(key)
value = GetTranslatedStringByKey(key, default?)
value = HasTranslationByKey(key)
LoadLanguageTable(id)
value = GetUserNickname(id?)
```

## Events（3）

```
value = GetEventCount(type)
PostEvent(eventName, param1, param2, .., paramN?)
returnValues = GetEvent(type, index)
```

## Vector math（38）

```
vec = Vec(x?, y?, z?)
new = VecCopy(org)
str = VecStr(vector)
length = VecLength(vec)
norm = VecNormalize(vec)
norm = VecScale(vec, scale)
c = VecAdd(a, b)
c = VecSub(a, b)
c = VecDot(a, b)
c = VecCross(a, b)
c = VecLerp(a, b, t)
quat = Quat(x?, y?, z?, w?)
new = QuatCopy(org)
quat = QuatAxisAngle(axis, angle)
quat = QuatDeltaNormals(normal0, normal1)
quat = QuatDeltaVectors(vector0, vector1)
quat = QuatEuler(x, y, z)
quat = QuatAlignXZ(xAxis, zAxis)
x,y,z = GetQuatEuler(quat)
quat = QuatLookAt(eye, target)
c = QuatSlerp(a, b, t)
str = QuatStr(quat)
c = QuatRotateQuat(a, b)
vec = QuatRotateVec(a, vec)
transform = Transform(pos?, rot?)
new = TransformCopy(org)
str = TransformStr(transform)
transform = TransformToParentTransform(parent, child)
transform = TransformToLocalTransform(parent, child)
r = TransformToParentVec(t, v)
r = TransformToLocalVec(t, v)
r = TransformToParentPoint(t, p)
r = TransformToLocalPoint(t, p)
SetRandomSeed(seed)
result = GetRandomBool()
result = GetRandomInt(min, max)
result = GetRandomFloat(min, max)
vector = GetRandomDirection(length?)
```

## Entity（16）

```
handle = FindEntity(tag?, global?, type?)
list = FindEntities(tag?, global?, type?)
list = GetEntityChildren(handle, tag?, recursive?, type?)
handle = GetEntityParent(handle, tag?, type?)
SetTag(handle, tag, value?)
RemoveTag(handle, tag)
exists = HasTag(handle, tag)
value = GetTagValue(handle, tag)
tags = ListTags(handle)
description = GetDescription(handle)
SetDescription(handle, description)
Delete(handle)
exists = IsHandleValid(handle)
type = GetEntityType(handle)
value = GetProperty(handle, property)
SetProperty(handle, property, value)
```

## Body（33）

```
handle = FindBody(tag?, global?)
list = FindBodies(tag?, global?)
transform = GetBodyTransform(handle)
SetBodyTransform(handle, transform)
mass = GetBodyMass(handle)
dynamic = IsBodyDynamic(handle)
SetBodyDynamic(handle, dynamic)
SetBodyVelocity(handle, velocity)
velocity = GetBodyVelocity(handle)
velocity = GetBodyVelocityAtPos(handle, pos)
SetBodyAngularVelocity(handle, angVel)
angVel = GetBodyAngularVelocity(handle)
SetBodyGravityScale(handle, scale)
active = IsBodyActive(handle)
SetBodyActive(handle, active)
ApplyBodyImpulse(handle, position, impulse)
list = GetBodyShapes(handle)
handle = GetBodyVehicle(body)
handle = GetBodyAnimator(body)
playerId = GetBodyPlayer(body)
min,max = GetBodyBounds(handle)
point = GetBodyCenterOfMass(handle)
visible = IsBodyVisible(handle, maxDist, rejectTransparent?, playerId?)
broken = IsBodyBroken(handle)
result = IsBodyJointedToStatic(handle)
DrawBodyOutline(handle, r?, g?, b?, a?)
DrawBodyHighlight(handle, amount)
hit,point,normal,shape = GetBodyClosestPoint(body, origin)
ConstrainVelocity(bodyA, bodyB, point, dir, relVel, min?, max?)
ConstrainAngularVelocity(bodyA, bodyB, dir, relAngVel, min?, max?)
ConstrainPosition(bodyA, bodyB, pointA, pointB, maxVel?, maxImpulse?)
ConstrainOrientation(bodyA, bodyB, quatA, quatB, maxAngVel?, maxAngImpulse?)
body = GetWorldBody()
```

## Shape（40）

```
handle = FindShape(tag?, global?)
list = FindShapes(tag?, global?)
transform = GetShapeLocalTransform(handle)
SetShapeLocalTransform(handle, transform)
transform = GetShapeWorldTransform(handle)
handle = GetShapeBody(handle)
list = GetShapeJoints(shape)
list = GetShapeLights(shape)
min,max = GetShapeBounds(handle)
SetShapeEmissiveScale(handle, scale)
SetShapeDensity(handle, density)
type,r,g,b,a,entry = GetShapeMaterialAtPosition(handle, pos, includeUnphysical?)
type,r,g,b,a,entry = GetShapeMaterialAtIndex(handle, x, y, z)
xsize,ysize,zsize,scale = GetShapeSize(handle)
count = GetShapeVoxelCount(handle)
visible = IsShapeVisible(handle, maxDist, rejectTransparent?, playerId?)
broken = IsShapeBroken(handle)
DrawShapeOutline(handle, r?, g?, b?, a)
DrawShapeHighlight(handle, amount)
SetShapeCollisionFilter(handle, layer, mask)
layer,mask = GetShapeCollisionFilter(handle)
newShape = CreateShape(body, transform, refShape)
ClearShape(shape)
resized,offset = ResizeShape(shape, xmi, ymi, zmi, xma, yma, zma)
SetShapeBody(shape, body, transform?)
CopyShapeContent(src, dst)
CopyShapePalette(src, dst)
entries = GetShapePalette(shape)
type,red,green,blue,alpha,reflectivity,shininess,metallic,emissive = GetShapeMaterial(shape, entry)
SetBrush(type, size, index or path, object?)
DrawShapeLine(shape, x0, y0, z0, x1, y1, z1, paint?, noOverwrite?)
DrawShapeBox(shape, x0, y0, z0, x1, y1, z1)
ExtrudeShape(shape, x, y, z, dx, dy, dz, steps, mode)
offset = TrimShape(shape)
newShapes = SplitShape(shape, removeResidual)
shape = MergeShape(shape)
disconnected = IsShapeDisconnected(shape)
disconnected = IsStaticShapeDetached(shape)
hit,point,normal = GetShapeClosestPoint(shape, origin)
touching = IsShapeTouching(a, b)
```

## Location（3）

```
handle = FindLocation(tag?, global?)
list = FindLocations(tag?, global?)
transform = GetLocationTransform(handle)
```

## Joint（16）

```
handle = FindJoint(tag?, global?)
list = FindJoints(tag?, global?)
broken = IsJointBroken(joint)
type = GetJointType(joint)
other = GetJointOtherShape(joint, shape)
shapes = GetJointShapes(joint)
SetJointMotor(joint, velocity, strength?)
SetJointMotorTarget(joint, target, maxVel?, strength?)
min,max = GetJointLimits(joint)
movement = GetJointMovement(joint)
bodies = GetJointedBodies(body)
DetachJointFromShape(joint, shape)
amount = GetRopeNumberOfPoints(joint)
pos = GetRopePointPosition(joint, index)
min,max = GetRopeBounds(joint)
BreakRope(joint, point)
```

## Animation（33）

```
SetAnimatorPositionIK(handle, begname, endname, target, weight?, history?, flag?)
SetAnimatorTransformIK(handle, begname, endname, transform, weight?, history?, locktarget?, useconstraints?)
length = GetBoneChainLength(handle, begname, endname)
handle = FindAnimator(tag?, global?)
list = FindAnimators(tag?, global?)
transform = GetAnimatorTransform(handle)
transform = GetAnimatorAdjustTransformIK(handle, name)
SetAnimatorTransform(handle, transform)
MakeRagdoll(handle)
UnRagdoll(handle, time?)
handle = PlayAnimation(handle, name, weight?, filter?)
PlayAnimationLoop(handle, name, weight?, filter?)
handle = PlayAnimationInstance(handle, instance, weight?, speed?)
StopAnimationInstance(handle, instance)
PlayAnimationFrame(handle, name, time, weight?, filter?)
BeginAnimationGroup(handle, weight?, filter?)
EndAnimationGroup(handle)
PlayAnimationInstances(handle)
list = GetAnimationClipNames(handle)
time = GetAnimationClipDuration(handle, name)
SetAnimationClipFade(handle, name, fadein, fadeout)
SetAnimationClipSpeed(handle, name, speed)
TrimAnimationClip(handle, name, begoffset, endoffset?)
time = GetAnimationClipLoopPosition(handle, name)
time = GetAnimationInstancePosition(handle, instance)
SetAnimationClipLoopPosition(handle, name, time)
SetBoneRotation(handle, name, quat, weight?)
SetBoneLookAt(handle, name, point, weight?)
RotateBone(handle, name, quat, weight?)
list = GetBoneNames(handle)
handle = GetBoneBody(handle, name)
transform = GetBoneWorldTransform(handle, name)
transform = GetBoneBindPoseTransform(handle, name)
```

## Light（11）

```
handle = FindLight(tag?, global?)
list = FindLights(tag?, global?)
SetLightEnabled(handle, enabled)
SetLightColor(handle, r, g, b)
SetLightIntensity(handle, intensity)
transform = GetLightTransform(handle)
handle = GetLightShape(handle)
active = IsLightActive(handle)
affected = IsPointAffectedByLight(handle, point)
handle = GetFlashlight(playerId?)
SetFlashlight(handle, playerId?)
```

## Trigger（13）

```
handle = FindTrigger(tag?, global?)
list = FindTriggers(tag?, global?)
transform = GetTriggerTransform(handle)
SetTriggerTransform(handle, transform)
min,max = GetTriggerBounds(handle)
inside = IsBodyInTrigger(trigger, body)
inside = IsVehicleInTrigger(trigger, vehicle)
inside = IsShapeInTrigger(trigger, shape)
inside = IsPointInTrigger(trigger, point)
value,dist = IsPointInBoundaries(point)
empty,maxpoint = IsTriggerEmpty(handle, demolision?)
distance = GetTriggerDistance(trigger, point)
closest = GetTriggerClosestPoint(trigger, point)
```

## Screen（6）

```
handle = FindScreen(tag?, global?)
list = FindScreens(tag?, global?)
SetScreenEnabled(screen, enabled)
enabled = IsScreenEnabled(screen)
shape = GetScreenShape(screen)
GetScreenPlayer(screen, playerId?)
```

## Vehicle（18）

```
handle = FindVehicle(tag?, global?)
list = FindVehicles(tag?, global?)
transform = GetVehicleTransform(vehicle)
transforms = GetVehicleExhaustTransforms(vehicle)
transforms = GetVehicleVitalTransforms(vehicle)
transforms = GetVehicleBodies(vehicle)
body = GetVehicleBody(vehicle)
health = GetVehicleHealth(vehicle)
params = GetVehicleParams(vehicle)
SetVehicleParam(handle, param, value) [S]
pos = GetVehicleDriverPos(vehicle)
pos = GetVehicleAvailableSeatPos(vehicle)
steering = GetVehicleSteering(vehicle)
drive = GetVehicleDrive(vehicle)
DriveVehicle(vehicle, drive, steering, handbrake) [S]
transform = GetVehicleLocationWorldTransform(vehicle, name)
count,seats,hasDriver = GetVehiclePassengerCount(vehicle)
SetVehicleHealth(vehicle, health) [S]
```

## Rig（7）

```
handle = FindRig(tag?, global?)
transform = GetRigWorldTransform(rig)
SetRigWorldTransform(rig, transform)
transform = GetRigLocationWorldTransform(rig, name)
SetRigLocationWorldTransform(rig, name, transform)
transform = GetRigLocationLocalTransform(rig, name)
SetRigLocationLocalTransform(rig, name, transform)
```

## Player（105）

```
name = GetAllPlayers()
count = GetMaxPlayers()
count = GetPlayerCount()
playerIds = GetAddedPlayers()
playerIds = GetRemovedPlayers()
name = GetPlayerName(playerId?)
GetLocalPlayer = GetLocalPlayer()
IsPlayerLocal = IsPlayerLocal(playerId?)
SetPlayerCharacter(character, playerId?) [C]
character = GetPlayerCharacter(playerId?)
IsPlayerHost = IsPlayerHost(playerId?)
IsPlayerValid = IsPlayerValid(playerId?)
position = GetPlayerPos(playerId?)
hit,startpos,endpos,direction,hitnormal,hitdist,hitentity,hitmaterial = GetPlayerAimInfo(position, maxdist?, playerId?)
pitch = GetPlayerPitch(playerId?)
yaw = GetPlayerYaw(playerId?)
SetPlayerPitch(pitch, playerId?)
recoil = GetPlayerCrouch(playerId?)
transform = GetPlayerTransform(playerId?)
transform = GetPlayerTransformWithPitch(playerId?)
SetPlayerTransform(transform, playerId?) [S]
SetPlayerTransformWithPitch(transform, playerId?) [S]
SetPlayerGroundVelocity(vel, playerId?) [S]
transform = GetPlayerEyeTransform(playerId?)
transform = GetPlayerCameraTransform(playerId?)
SetPlayerCameraOffsetTransform(transform, stackable?, playerId?) [C]
SetPlayerSpawnTransform(transform, playerId?) [S]
SetPlayerSpawnHealth(health, playerId?) [S]
SetPlayerSpawnTool(id, playerId?) [S]
velocity = GetPlayerVelocity(playerId?)
SetPlayerVehicle(vehicle, playerId?) [S]
SetPlayerAnimator(animator, playerId?)
animator = GetPlayerAnimator(playerId?)
bodies = GetPlayerBodies(playerId?)
SetPlayerVelocity(velocity, playerId?) [S]
handle = GetPlayerVehicle(playerId?)
isGrounded = IsPlayerGrounded(playerId?)
isDriver = IsPlayerVehicleDriver(handle, playerId?)
isPassenger = IsPlayerVehiclePassenger(handle, playerId?)
isGrounded = IsPlayerJumping(playerId?)
contact,shape,point,normal = GetPlayerGroundContact(playerId?)
handle = GetPlayerGrabShape(playerId?)
handle = GetPlayerGrabBody(playerId?)
ReleasePlayerGrab(playerId?) [S]
pos = GetPlayerGrabPoint(playerId?)
handle = GetPlayerPickShape(playerId?)
handle = GetPlayerPickBody(playerId?)
handle = GetPlayerInteractShape(playerId?)
handle = GetPlayerInteractBody(playerId?)
SetPlayerScreen(handle, playerId?) [S]
handle = GetPlayerScreen(playerId?)
SetPlayerHealth(health, playerId?) [S]
health = GetPlayerHealth(playerId?)
canusetool = GetPlayerCanUseTool(playerId?)
SetPlayerRegenerationState(state, player?) [S]
SetPlayerTool(toolId, playerId?) [S]
toolId = GetPlayerTool(playerId?)
RespawnPlayer(playerId?) [S]
RespawnPlayerAtTransform(transform, playerId?) [S]
speed = GetPlayerWalkingSpeed(playerId?)
SetPlayerWalkingSpeed(speed, playerId?) [S]
speed = GetPlayerCrouchSpeedScale(playerId?)
SetPlayerCrouchSpeedScale(speed, playerId?) [S]
speed = GetPlayerHurtSpeedScale(playerId?)
SetPlayerHurtSpeedScale(speed, playerId?) [S]
value = GetPlayerParam(parameter, player?)
SetPlayerParam(parameter, value, player?) [S]
SetPlayerHidden(playerId?)
RegisterTool(id, name, file, group?) [S]
SetToolAmmoPickupAmount(toolId, ammo) [S]
ammo = GetToolAmmoPickupAmount(toolId)
handle = GetToolBody(playerId?)
right,left = GetToolHandPoseLocalTransform(playerId?)
right,left = GetToolHandPoseWorldTransform(playerId?)
SetToolHandPoseLocalTransform(right, left, playerId?) [C]
location = GetToolLocationLocalTransform(name, playerId?)
location = GetToolLocationWorldTransform(name, playerId?)
SetToolTransform(transform, sway?, playerId?) [C]
SetToolAllowedZoom(zoom, zoom sensitivity?) [C]
SetToolTransformOverride(transform, playerId?) [C]
SetToolOffset(offset, playerId?) [C]
SetToolAmmo(toolId, ammo, playerId?) [S]
ammo = GetToolAmmo(toolId, playerId?)
SetToolEnabled(toolId, enabled, playerId?) [S]
enabled = IsToolEnabled(toolId, playerId?)
SetPlayerOrientation(orientation, playerId?)
GetPlayerOrientation(playerId?)
up = GetPlayerUp(playerId?)
SetPlayerRig(rig, playerId?)
rig = GetPlayerRig(playerId?)
transform = GetPlayerRigWorldTransform(playerId?)
ClearPlayerRig(rig-id, playerId?)
SetPlayerRigLocationLocalTransform(rig-id, name, location, playerId?)
SetPlayerRigTransform(rig-id, location, playerId?)
location = GetPlayerRigLocationWorldTransform(name, playerId?)
SetPlayerRigTags(rig-id, tag, playerId?) [C]
exists = GetPlayerRigHasTag(tag, playerId?)
value = GetPlayerRigTagValue(tag, playerId?)
inuse,r,g,b = GetPlayerColor(playerId?)
SetPlayerColor(r, g, b, playerId?)
ApplyPlayerDamage(targetPlayerId, damage, cause?, instigatingPlayerId?) [S]
DisablePlayerInput(player) [S]
DisablePlayer(playerId) [S]
IsPlayerDisabled(playerId)
DisablePlayerDamage(playerId) [S]
```

## Sound（22）

```
handle = LoadSound(path, nominalDistance?)
UnloadSound(handle)
handle = LoadLoop(path, nominalDistance?)
UnloadLoop(handle)
flag = SetSoundLoopUser(handle, nominalDistance) [C]
handle = PlaySound(handle, pos?, volume?, registerVolume?, pitch?)
handle = PlaySoundForUser(handle, user, pos?, volume?, registerVolume?, pitch?) [C]
StopSound(handle)
playing = IsSoundPlaying(handle)
progress = GetSoundProgress(handle)
SetSoundProgress(handle, progress)
PlayLoop(handle, pos?, volume?, registerVolume?, pitch?)
progress = GetSoundLoopProgress(handle)
SetSoundLoopProgress(handle, progress?)
PlayMusic(path)
StopMusic()
playing = IsMusicPlaying()
SetMusicPaused(paused)
progress = GetMusicProgress()
SetMusicProgress(progress?)
SetMusicVolume(volume)
SetMusicLowPass(wet)
```

## Sprite（2）

```
handle = LoadSprite(path)
DrawSprite(handle, transform, width, height, r?, g?, b?, a?, depthTest?, additive?, fogAffected?)
```

## Scene queries（28）

```
QueryRequire(layers)
QueryInclude(layers)
QueryCollisionMask(mask)
QueryRejectAnimator(handle)
QueryRejectVehicle(vehicle)
QueryRejectBody(body)
QueryRejectBodies(bodies)
QueryRejectShape(shape)
QueryRejectShapes(shapes)
QueryRejectPlayer(playerId?)
hit,dist,normal,shape = QueryRaycast(origin, direction, maxDist, radius?, rejectTransparent?)
hit,dist,joint = QueryRaycastRope(origin, direction, maxDist, radius?)
hit,dist,hitPos = QueryRaycastWater(origin, direction, maxDist)
didHit,dist,shape,playerId,playerDamageFactor,normal = QueryShot(origin, direction, maxDist, radius?, playerId?)
hit,point,normal,shape = QueryClosestPoint(origin, maxDist)
list = QueryAabbShapes(min, max)
list = QueryAabbBodies(min, max)
QueryPath(start, end, maxDist?, targetRadius?, type?)
id = CreatePathPlanner()
DeletePathPlanner(id)
PathPlannerQuery(id, start, end, maxDist?, targetRadius?, type?)
AbortPath(id?)
state = GetPathState(id?)
length = GetPathLength(id?)
point = GetPathPoint(dist, id?)
volume,position = GetLastSound()
inWater,depth = IsPointInWater(point)
vel = GetWindVelocity(point)
```

## Particles（15）

```
ParticleReset()
ParticleType(type)
ParticleTile(type)
ParticleColor(r0, g0, b0, r1?, g1?, b1?)
ParticleRadius(r0, r1?, interpolation?, fadein?, fadeout?)
ParticleAlpha(a0, a1?, interpolation?, fadein?, fadeout?)
ParticleGravity(g0, g1?, interpolation?, fadein?, fadeout?)
ParticleDrag(d0, d1?, interpolation?, fadein?, fadeout?)
ParticleEmissive(d0, d1?, interpolation?, fadein?, fadeout?)
ParticleRotation(r0, r1?, interpolation?, fadein?, fadeout?)
ParticleStretch(s0, s1?, interpolation?, fadein?, fadeout?)
ParticleSticky(s0, s1?, interpolation?, fadein?, fadeout?)
ParticleCollide(c0, c1?, interpolation?, fadein?, fadeout?)
ParticleFlags(bitmask)
SpawnParticle(pos, velocity, lifetime)
```

## Spawn（3）

```
entities = Spawn(xml, transform, allowStatic?, jointExisting?)
entities = SpawnLayer(xml, layer, transform, allowStatic?, jointExisting?)
entities = SpawnTool(id, transform, allowStatic?, voxScale?)
```

## Miscellaneous（54）

```
AddMapMarker(id, tag, name, category, showLabelOnMap, info, pos, color, infoImage?, dotIcon?) [C]
id,tag = SelectedMapMarker() [C]
Shoot(origin, direction, type?, strength?, maxDist?, playerId?) [S]
Paint(origin, radius, type?, probability?) [S]
PaintRGBA(origin, radius, red, green, blue, alpha?, probability?) [S]
count = MakeHole(position, r0, r1?, r2?, silent?) [S]
Explosion(pos, size, instigatingPlayerId?) [S]
SpawnFire(pos) [S]
count = GetFireCount()
hit,pos = QueryClosestFire(origin, maxDist)
count = QueryAabbFireCount(min, max)
count = RemoveAabbFires(min, max) [S]
transform = GetCameraTransform() [C]
SetCameraTransform(transform, fov?) [C]
RequestFirstPerson(transition) [C]
RequestThirdPerson(transition) [C]
SetCameraOffsetTransform(transform, stackable?) [C]
AttachCameraTo(handle, ignoreRotation?) [C]
SetPivotClipBody(bodyHandle, mainShapeIdx) [C]
ShakeCamera(strength) [C]
SetCameraFov(degrees) [C]
SetCameraDof(distance, amount?) [C]
DisableMotionBlur() [C]
SetLowHealthBlurThreshold(health) [C]
PointLight(pos, r, g, b, intensity?)
SetTimeScale(scale) [S]
SetEnvironmentDefault() [S]
SetEnvironmentProperty(name, value0, value1?, value2?, value3?) [S]
value0,value1,value2,value3,value4 = GetEnvironmentProperty(name)
SetPostProcessingDefault()
SetPostProcessingProperty(name, value0, value1?, value2?)
value0,value1,value2 = GetPostProcessingProperty(name)
DrawLine(p0, p1, r?, g?, b?, a?)
DebugLine(p0, p1, r?, g?, b?, a?)
DebugCross(p0, r?, g?, b?, a?)
DebugTransform(transform, scale?)
DebugWatch(name, value, lineWrapping?)
DebugPrint(message, lineWrapping?)
RegisterListenerTo(eventName, listenerFunction)
UnregisterListener(eventName, listenerFunction)
TriggerEvent(eventName, args?)
handle = LoadHaptic(filepath) [C]
handle = CreateHaptic(leftMotorRumble, rightMotorRumble, leftTriggerRumble, rightTriggerRumble) [C]
PlayHaptic(handle, amplitude) [C]
PlayHapticDirectional(handle, direction, amplitude) [C]
flag = HapticIsPlaying(handle) [C]
SetToolHaptic(id, handle, amplitude?) [C]
StopHaptic(handle) [C]
AddHeat(shape, pos, amount) [S]
area = GetBoundaryArea()
min,max = GetBoundaryBounds()
vector = GetGravity()
SetGravity(vec) [S]
fps = GetFps()
```

## User Interface（99）

```
UiMakeInteractive()
UiPush()
UiPop()
width = UiWidth()
height = UiHeight()
center = UiCenter()
middle = UiMiddle()
UiColor(r, g, b, a?)
UiColorFilter(r, g, b, a?)
UiResetColor()
UiTranslate(x, y)
UiRotate(angle)
UiScale(x, y?)
x,y = UiGetScale()
UiClipRect(width, height, inherit?)
UiWindow(width, height, clip?, inherit?)
tl_x,tl_y,br_x,br_y = UiGetCurrentWindow()
val = UiIsInCurrentWindow(x, y)
value = UiIsRectFullyClipped(w, h)
value = UiIsInClipRegion(x, y)
value = UiIsFullyClipped(w, h)
x0,y0,x1,y1 = UiSafeMargins()
value = UiCanvasSize()
UiAlign(alignment)
UiTextAlignment(alignment)
UiModalBegin(force?)
UiModalEnd()
UiDisableInput()
UiEnableInput()
receives = UiReceivesInput()
x,y = UiGetMousePos()
x,y = UiGetCanvasMousePos()
inside = UiIsMouseInRect(w, h)
x,y,distance = UiWorldToPixel(point)
direction = UiPixelToWorld(x, y)
UiGetCursorPos()
UiBlur(amount)
UiFont(path, size)
size = UiFontHeight()
w,h,x,y,linkId = UiText(text, move?, maxChars?)
UiTextDisableWildcards(disable)
UiTextUniformHeight(uniform)
w,h,x,y = UiGetTextSize(text)
w,h = UiMeasureText(space, text/locale)
count = UiGetSymbolsCount(text)
substring = UiTextSymbolsSub(text, from, to)
UiWordWrap(width)
UiTextLineSpacing(value)
UiTextOutline(r, g, b, a, thickness?)
UiTextShadow(r, g, b, a, distance?, blur?)
UiRect(w, h)
UiRectOutline(width, height, thickness)
UiRoundedRect(width, height, roundingRadius)
UiRoundedRectOutline(width, height, roundingRadius, thickness)
UiCircle(radius)
UiCircleOutline(radius, thickness)
UiFillImage(path)
UiBackgroundBlur(amount)
w,h = UiImage(path, x0?, y0?, x1?, y1?)
UiUnloadImage(path)
exists = UiHasImage(path)
w,h = UiGetImageSize(path)
UiImageBox(path, width, height, borderWidth?, borderHeight?)
UiSound(path, volume?, pitch?, panAzimuth?, panDepth?)
UiSoundLoop(path, volume?, pitch?)
UiMute(amount, music?)
UiButtonImageBox(path, borderWidth, borderHeight, r?, g?, b?, a?)
UiButtonHoverColor(r, g, b, a?)
UiButtonPressColor(r, g, b, a?)
UiButtonPressDist(distX, distY)
UiButtonTextHandling(type)
pressed = UiTextButton(text, w?, h?)
pressed = UiImageButton(path)
pressed = UiBlankButton(w, h)
value,done = UiSlider(path, axis, current, min, max)
UiSliderHoverColorFilter(r, g, b, a)
UiSliderThumbSize(width, height)
handle = UiGetScreen()
id = UiNavComponent(w, h)
UiIgnoreNavigation(ignore?)
UiResetNavigation()
UiNavSkipUpdate()
focus = UiIsComponentInFocus(id)
id = UiNavGroupBegin(id?)
UiNavGroupEnd()
UiNavGroupSize(w, h)
UiForceFocus(id)
id = UiFocusedComponentId()
rect = UiFocusedComponentRect(n?)
x,y = UiGetItemSize()
UiAutoTranslate(value)
UiBeginFrame()
UiResetFrame()
UiFrameOccupy(width, height)
width,height = UiEndFrame()
UiFrameSkipItem(skip)
frameNo = UiGetFrameNo()
index = UiGetLanguage()
UiSetCursorState(state)
```

---

## 附录：GetProperty/SetProperty 可读写属性表

| Entity type | Available params |
| --- | --- |
| Body | desc (string), dynamic (boolean), mass (number), transform, velocity (vector(x, y, z)), angVelocity (vector(x, y, z)), active (boolean), friction (number), restitution (number), frictionMode (average\|minimum\|multiply\|maximum), restitutionMode (average\|minimum\|multiply\|maximum) |
| Shape | density (number), strength (number), size (number), emissiveScale (number), localTransform, worldTransform |
| Light | enabled (boolean), color (vector(r, g, b)), intensity (number), transform, active (boolean), type (string), size (number), reach (number), unshadowed (number), fogscale (number), fogiter (number), glare (number) |
| Location | transform |
| Water | depth (number), wave (number), ripple (number), motion (number), foam (number), color (vector(r, g, b)) |
| Joint | type (string), size (number), rotstrength (number), rotspring (number); only for ropes: slack (number), strength (number), maxstretch (number), ropecolor (vector(r, g, b)) |
| Vehicle | spring (number), damping (number), topspeed (number), acceleration (number), strength (number), antispin (number), antiroll (number), difflock (number), steerassist (number), friction (number), smokeintensity (number), transform, brokenthreshold (number) |
| Wheel | drive (number), steer (number), travel (vector(x, y)) |
| Screen | enabled (boolean), bulge (number), resolution (number, number), script (string), interactive (boolean), emissive (number), fxraster (number), fxca (number), fxnoise (number), fxglitch (number), size (vector(x, y)) |
| Trigger | transform, type (string), size (vector(x, y, z)/number) |

