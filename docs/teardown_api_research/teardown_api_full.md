# Teardown 脚本 API 完整清单（官方 API 2.1.0）

> 数据来源：官方 [api.xml](https://teardowngame.com/modding/api.xml) 与 [api.html](https://teardowngame.com/modding/api.html)
> 抓取时间：2026-02 ｜ 全量 **609 函数 / 24 分类** ｜ 其中 42 个 server-only、33 个 client-only
> 签名格式：`返回值 = 函数名( 参数 )`，`[参数]` 表示可选参数。
> 生成方式：解析官方 api.xml 得到参数/返回值/描述，配合 api.html 补齐示例与属性表（属性表为引擎 `GetProperty/SetProperty` 可读写的动态字段）。

## 目录
| 分类 | 函数 | 分类 | 函数 |
|---|---|---|---|
| [Parameters](#parameters) | 5 | [Trigger](#trigger) | 13 |
| [Script control](#script-control) | 22 | [Screen](#screen) | 6 |
| [Registry](#registry) | 17 | [Vehicle](#vehicle) | 18 |
| [Events](#events) | 3 | [Rig](#rig) | 7 |
| [Vector math](#vector-math) | 38 | [Player](#player) | 105 |
| [Entity](#entity) | 16 | [Sound](#sound) | 22 |
| [Body](#body) | 33 | [Sprite](#sprite) | 2 |
| [Shape](#shape) | 40 | [Scene queries](#scene-queries) | 28 |
| [Location](#location) | 3 | [Particles](#particles) | 15 |
| [Joint](#joint) | 16 | [Spawn](#spawn) | 3 |
| [Animation](#animation) | 33 | [Miscellaneous](#miscellaneous) | 54 |
| [Light](#light) | 11 | [User Interface](#user-interface) | 99 |


---

## Parameters

<b>5 个函数</b>

### GetIntParam

```lua
value = GetIntParam( name, default )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Parameter name |
| `default` | `number` | 否 | Default parameter value |

**返回**：`value`: number（Parameter value）

示例：

```lua
--Retrieve blinkcount parameter, or set to 5 if omitted
parameterBlinkCount = GetIntParam("blinkcount", 5)

function init()
	DebugPrint(parameterBlinkCount)
end
```


### GetFloatParam

```lua
value = GetFloatParam( name, default )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Parameter name |
| `default` | `number` | 否 | Default parameter value |

**返回**：`value`: number（Parameter value）

示例：

```lua
--Retrieve speed parameter, or set to 10.0 if omitted
parameterSpeed = GetFloatParam("speed", 10.0)

function init()
	DebugPrint(parameterSpeed)
end
```


### GetBoolParam

```lua
value = GetBoolParam( name, default )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Parameter name |
| `default` | `boolean` | 否 | Default parameter value |

**返回**：`value`: boolean（Parameter value）

示例：

```lua
--Retrieve playsound parameter, or false if omitted
parameterPlaySound = GetBoolParam("playsound", false)


function init()
	DebugPrint(parameterPlaySound)
end
```


### GetStringParam

```lua
value = GetStringParam( name, default )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Parameter name |
| `default` | `string` | 否 | Default parameter value |

**返回**：`value`: string（Parameter value）

示例：

```lua
--Retrieve mode parameter, or "idle" if omitted
parameterMode = GetStringParam("mode", "idle")

function init()
	DebugPrint(parameterMode)
end
```


### GetColorParam

```lua
value = GetColorParam( name, default )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Parameter name |
| `default` | `number` | 否 | Default parameter value |

**返回**：`value`: number（Parameter value）

示例：

```lua
--Retrieve color parameter, or set to 0.39, 0.39, 0.39 if omitted
color_r, color_g, color_b = GetColorParam("color", 0.39, 0.39, 0.39)

function init()
	DebugPrint(color_r .. " " .. color_g .. " " .. color_b)
end
```



---

## Script control

| Physical input | Description |
| --- | --- |
| esc | Escape key |
| tab | Tab key |
| lmb | Left mouse button |
| rmb | Right mouse button |
| mmb | Middle mouse button |
| uparrow | Up arrow key |
| downarrow | Down arrow key |
| leftarrow | Left arrow key |
| rightarrow | Right arrow key |
| f1-f12 | Function keys |
| backspace | Backspace key |
| alt | Alt key |
| delete | Delete key |
| home | Home key |
| end | End key |
| pgup | Pgup key |
| pgdown | Pgdown key |
| insert | Insert key |
| space | Space bar |
| shift | Shift key |
| ctrl | Ctrl key |
| return | Return key |
| any | Any key or button |
| a,b,c,... | Latin, alphabetical keys a through z |
| 0-9 | Digits, zero to nine |
| mousedx | Mouse horizontal diff. Only valid in InputValue. |
| mousedy | Mouse vertical diff. Only valid in InputValue. |
| mousewheel | Mouse wheel. Only valid in InputValue. |

| Logical input | Description |
| --- | --- |
| up | Move forward / Accelerate |
| down | Move backward / Brake |
| left | Move left |
| right | Move right |
| interact | Interact |
| flashlight | Flashlight |
| jump | Jump |
| crouch | Crouch |
| usetool | Use tool |
| grab | Grab |
| handbrake | Handbrake |
| map | Map |
| pause | Pause game (escape) |
| vehicleraise | Raise vehicle parts |
| vehiclelower | Lower vehicle parts |
| vehicleaction | Vehicle action |
| camerax | Camera x movement, scaled by sensitivity. Only valid in InputValue. |
| cameray | Camera y movement, scaled by sensitivity. Only valid in InputValue. |
| tool_group_prev | Switch to previous tool group |
| tool_group_next | Switch to next tool group |
| extra0 | Extra action 0 |
| extra1 | Extra action 1 |
| extra2 | Extra action 2 |
| extra3 | Extra action 3 |
| extra4 | Extra action 4 |
| extra5 | Extra action 5 |
| extra6 | Extra action 6 |
| photomode | Photomode |
| zoom | Zoom |
| menu_left | Menu left |
| menu_right | Menu right |
| menu_up | Menu up |
| menu_down | Menu down |
| menu_next | Menu next |
| menu_prev | Menu prev |
| menu_accept | Menu accept |
| menu_cancel | Menu cancel |

<b>22 个函数</b>

### GetVersion

```lua
version = GetVersion(  )
```

**返回**：`version`: string（Dot separated string of current version of the game）

示例：

```lua
function init()
	local v = GetVersion()
	--v is "0.5.0"
	DebugPrint(v)
end
```


### HasVersion

```lua
match = HasVersion( version )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `version` | `string` | 否 | Reference version |

**返回**：`match`: boolean（True if current version is at least provided one）

示例：

```lua
function init()
	if HasVersion("1.5.0") then
		--conditional code that only works on 0.6.0 or above
		DebugPrint("New version")
	else
		--legacy code that works on earlier versions
		DebugPrint("Earlier version")
	end
end
```


### GetTime

```lua
time = GetTime(  )
```

**返回**：`time`: number（The time in seconds since level was started）

示例：

```lua
function client.update()
	local t = GetTime()
	DebugPrint(t)
end
```


### GetTimeStep

```lua
dt = GetTimeStep(  )
```

**返回**：`dt`: number（The timestep in seconds）

示例：

```lua
function client.tick()
	local dt = GetTimeStep()
	DebugPrint("tick dt: " .. dt)
end

function client.update()
	local dt = GetTimeStep()
	DebugPrint("update dt: " .. dt)
end
```


### InputLastPressedKey

```lua
name = InputLastPressedKey( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`name`: string（Name of last pressed key, empty if no key is pressed）

示例：

```lua
function client.tick()
	local name = InputLastPressedKey()
	if string.len(name) > 0 then
		DebugPrint(name)
	end
end
```


### InputPressed

```lua
pressed = InputPressed( input, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `input` | `string` | 否 | The input identifier |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`pressed`: boolean（True if input was pressed during last frame）

示例：

```lua
function client.tick()
	if InputPressed("interact") then
		DebugPrint("interact")
	end
end
```


### InputReleased

```lua
pressed = InputReleased( input, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `input` | `string` | 否 | The input identifier |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`pressed`: boolean（True if input was released during last frame）

示例：

```lua
function client.tick()
	if InputReleased("interact") then
		DebugPrint("interact")
	end
end
```


### InputDown

```lua
pressed = InputDown( input, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `input` | `string` | 否 | The input identifier |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`pressed`: boolean（True if input is currently held down）

示例：

```lua
function client.tick()
	if InputDown("interact") then
		DebugPrint("interact")
	end
end
```


### InputValue

```lua
value = InputValue( input, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `input` | `string` | 否 | The input identifier |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`value`: number（Depends on input type）

示例：

```lua
local scrollPos = 0
function client.tick()
	scrollPos = scrollPos + InputValue("mousewheel")
	DebugPrint(scrollPos)
end
```


### InputClear

```lua
InputClear(  )  -- client only
```

示例：

```lua
function client.update()
    -- Prints '2' because InputClear() allows the game to "forget" the player's input
	if InputDown("interact") then
        InputClear()
		if InputDown("interact") then
			DebugPrint(1)
		else
			DebugPrint(2)
		end
	end
end
```


### InputResetOnTransition

```lua
InputResetOnTransition(  )  -- client only
```

示例：

```lua
function update()
	if InputDown("interact") then
        -- In this form, you won't be able to notice the result of the function; you need a specific context
		InputResetOnTransition()
	end
end
```


### LastInputDevice

```lua
value = LastInputDevice(  )
```

**返回**：`value`: number（Last device id）

示例：

```lua
#include "ui/ui_helpers.lua"

function client.update()
	if LastInputDevice() == UI_DEVICE_GAMEPAD then
		DebugPrint("Last input was from gamepad")
	elseif LastInputDevice() == UI_DEVICE_MOUSE then
		DebugPrint("Last input was mouse & keyboard")
	elseif LastInputDevice() == UI_DEVICE_TOUCHSCREEN then
		DebugPrint("Last input was touchscreen")
	end
end
```


### SetValue

```lua
SetValue( variable, value, [transition], [time] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `variable` | `string` | 否 | Name of number variable in the global context |
| `value` | `number` | 否 | The new value |
| `transition` | `string` | 是 | Transition type. See description. |
| `time` | `number` | 是 | Transition time (seconds) |

| Transition | Description |
| --- | --- |
| linear | Linear transition |
| cosine | Slow at beginning and end |
| easein | Slow at beginning |
| easeout | Slow at end |
| bounce | Bounce and overshoot new value |

示例：

```lua
myValue = 0
function client.tick()
	--This will change the value of myValue from 0 to 1 in a linear fasion over 0.5 seconds
	SetValue("myValue", 1, "linear", 0.5)
	DebugPrint(myValue)
end
```


### SetValueInTable

```lua
SetValueInTable( tableId, memberName, newValue, type, length )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tableId` | `table` | 否 | Id of the table |
| `memberName` | `string` | 否 | Name of the member |
| `newValue` | `number` | 否 | New value |
| `type` | `string` | 否 | Transition type |
| `length` | `number` | 否 | Transition length |

示例：

```lua
local t = {}
function init()
	SetValueInTable(t, "score", 1, "number", 1)
end
function update()
	if InputPressed("interact") then
		SetValueInTable(t, "score", t.score + 1, "number", 1)
        DebugPrint(t.score)
	end
end
```


### PauseMenuButton

```lua
clicked = PauseMenuButton( title, [location], [disabled] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `title` | `string` | 否 | Text on button |
| `location` | `string` | 是 | Button location. If 'bottom_bar' - bottom bar, if 'main_bottom' - below 'Main menu' button, if 'main_top' - above 'Main menu' button. Default 'bottom_bar'. |
| `disabled` | `bool` | 是 | Disable button. Button will be rendered as grayed out. Default is false. Only available when used with 'bottom_bar'. |

**返回**：`clicked`: boolean（True if clicked, false otherwise）

示例：

```lua
function server.startLevel(mission, path)
	StartLevel(mission, path)
end

function server.respawnPlayer(player)
	-- Respawn player
end

function client.tick()


	for p in Players() do
		if IsPlayerHost(p) then
			-- Primary button which will be placed in the main pause menu below "Main menu" button
			if PauseMenuButton("Back to Hub", "main_bottom") then
				ServerCall("server.startLevel", "hub", "level/hub.xml")	
			end

			-- Primary button which will be placed in the main pause menu above "Main menu" button
			if PauseMenuButton("Back to Hub", "main_top") then
				ServerCall("server.startLevel", "hub", "level/hub.xml")
			end

			-- Button will be placed in the bottom bar of the pause menu
			if PauseMenuButton("MyMod Settings") then
				visible = true
			end
		else
			if PauseMenuButton("Respawn (wait 8s)", "bottom_bar", true) then
				ServerCall("server.respawnPlayer", p)
			end
		end
	end
end

function draw()
	if visible then
		UiMakeInteractive()
	end
end
```


### HasFile

```lua
exists = HasFile( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to file |

**返回**：`exists`: boolean（True if file exists）

示例：

```lua
local file = "gfx/circle.png"

function draw()
	if HasFile(image) then
		DebugPrint("file " .. file .. " exists")
	end
end
```


### StartLevel

```lua
StartLevel( mission, path, [layers], [passThrough] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `mission` | `string` | 否 | An identifier of your choice |
| `path` | `string` | 否 | Path to level XML file |
| `layers` | `string` | 是 | Active layers. Default is no layers. |
| `passThrough` | `boolean` | 是 | If set, loading screen will have no text and music will keep playing |

示例：

```lua
function server.init()
	--Start level with no active layers
	StartLevel("level1", "MOD/level1.xml")

	--Start level with two layers
	StartLevel("level1", "MOD/level1.xml", "vehicles targets")
end
```


### SetPaused

```lua
SetPaused( paused )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `paused` | `boolean` | 否 | True if game should be paused |

示例：

```lua
function client.tick()
	if InputPressed("interact") then
		--Pause game and bring up pause menu on HUD
		SetPaused(true)
	end
end
```


### Restart

```lua
Restart(  )
```

示例：

```lua
function server.tick()
	if InputPressed("interact") then
		Restart()
	end
end
```


### Menu

```lua
Menu(  )
```

示例：

```lua
function client.tick()
	if InputPressed("interact") then
		Menu()
	end
end
```


### ClientCall

```lua
ClientCall( playerId, function, [param1, param2, .., paramN] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 否 | Player ID of the recipient. Use 0 to broadcast to every player. |
| `function` | `string` | 否 | Name of the function to be invoked. This function must exist within issuing script. |
| `param1, param2, .., paramN` | `any` | 是 | Optional parameters to send to the recipent(s). Arguments should match the signature of the specified function. |

示例：

```lua
function server.tick()
	for p in Players() do
		if GetPlayerHealth(p) == 0) then
			ClientCall(p, "client.showRespawnBtn")
		end
	end
	
	if matchEnded then
		ClientCall(0, "client.displayParticles", "confetti", 200, 0.3, Vec(0, 30, 0))
	end
end

function client.showRespawnBtn()
	-- show respawn ui..
end

function client.displayParticles(particleName, amount, life, pos)
	-- spawn particles..
end
```


### ServerCall

```lua
ServerCall( function, [param1, param2, .., paramN] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `function` | `string` | 否 | Name of the function to be invoked. This function must exist within issuing script. |
| `param1, param2, .., paramN` | `any` | 是 | Optional parameters to send to the server. Arguments should match the signature of the specified function. |

示例：

```lua
function client.tick()
	if UiTextButton("I am Ready") then
		ServerCall("server.setPlayerReady", GetLocalPlayer()) 
	end
end

function server.setPlayerReady(playerId)
	shared.playersReady[playerId] = true
end
```



---

## Registry

| Key | Description |
| --- | --- |
| options | reserved for game settings (write protected from mods) |
| game | reserved for the game engine internals (see documentation) |
| savegame | used for persistent game data (write protected for mods) |
| savegame.mod | used for persistent mod data. Use only alphanumeric character for key name. |
| level | not reserved, but recommended for level specific entries and script communication |

<b>17 个函数</b>

### ClearKey

```lua
ClearKey( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key to clear |

示例：

```lua
function init()
	--If the registry looks like this:
	--	score
	--		levels
	--			level1 = 5
	--			level2 = 4

	ClearKey("score.levels")

	--Afterwards, the registry will look like this:
	--	score
end
```


### ListKeys

```lua
children = ListKeys( parent )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `parent` | `string` | 否 | The parent registry key |

**返回**：`children`: table（Indexed table of strings with child keys）

示例：

```lua
--If the registry looks like this:
--	game
--		tool
--			steroid
--			rifle
--			...

function init()
	local list = ListKeys("game.tool")
	for i=1, #list do
		DebugPrint(list[i])
	end
end

--This will output:
--steroid
--rifle
-- ...
```


### HasKey

```lua
exists = HasKey( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |

**返回**：`exists`: boolean（True if key exists）

示例：

```lua
function init()
	DebugPrint(HasKey("score.levels"))
	DebugPrint(HasKey("game.tool.rifle"))
end
```


### SetInt

```lua
SetInt( key, value, [sync] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |
| `value` | `number` | 否 | Desired value |
| `sync` | `boolean` | 是 | Synchronize to clients |

示例：

```lua
function init()
	SetInt("score.levels.level1", 4)
	DebugPrint(GetInt("score.levels.level1"))
end
```


### GetInt

```lua
value = GetInt( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |

**返回**：`value`: number（Integer value of registry node or zero if not found）

示例：

```lua
function init()
	SetInt("score.levels.level1", 4)
	DebugPrint(GetInt("score.levels.level1"))
end
```


### SetFloat

```lua
SetFloat( key, value, [sync] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |
| `value` | `number` | 否 | Desired value |
| `sync` | `boolean` | 是 | Synchronize to clients |

示例：

```lua
function init()
	SetFloat("level.time", 22.3)
	DebugPrint(GetFloat("level.time"))
end
```


### GetFloat

```lua
value = GetFloat( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |

**返回**：`value`: number（Float value of registry node or zero if not found）

示例：

```lua
function init()
	SetFloat("level.time", 22.3)
	DebugPrint(GetFloat("level.time"))
end
```


### SetBool

```lua
SetBool( key, value, [sync] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |
| `value` | `boolean` | 否 | Desired value |
| `sync` | `boolean` | 是 | Synchronize to clients |

示例：

```lua
function init()
	SetBool("level.robots.enabled", true)
	DebugPrint(GetBool("level.robots.enabled"))
end
```


### GetBool

```lua
value = GetBool( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |

**返回**：`value`: boolean（Boolean value of registry node or false if not found）

示例：

```lua
function init()
	SetBool("level.robots.enabled", true)
	DebugPrint(GetBool("level.robots.enabled"))
end
```


### SetString

```lua
SetString( key, value, [sync] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |
| `value` | `string` | 否 | Desired value |
| `sync` | `boolean` | 是 | Synchronize to clients |

示例：

```lua
function init()
	SetString("level.name", "foo")
	DebugPrint(GetString("level.name"))
end
```


### GetString

```lua
value = GetString( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |

**返回**：`value`: string（String value of registry node or '' if not found）

示例：

```lua
function init()
	SetString("level.name", "foo")
	DebugPrint(GetString("level.name"))
end
```


### SetColor

```lua
SetColor( key, r, g, b, [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |
| `r` | `number` | 否 | Desired red channel value |
| `g` | `number` | 否 | Desired green channel value |
| `b` | `number` | 否 | Desired blue channel value |
| `a` | `number` | 是 | Desired alpha channel value |

示例：

```lua
function init()
	SetColor("game.tool.wire.color", 1.0, 0.5, 0.3)
end
```


### GetColor

```lua
r, g, b, a = GetColor( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Registry key |

**返回**：`r`: number（Desired red channel value）；`g`: number（Desired green channel value）；`b`: number（Desired blue channel value）；`a`: number（Desired alpha channel value）

示例：

```lua
function init()
	SetColor("red", 1.0, 0.1, 0.1)
	color = GetColor("red")
	DebugPrint("RGBA: " .. color[1] .. " " .. color[2] .. " " .. color[3] .. " " .. color[4])
end
```


### GetTranslatedStringByKey

```lua
value = GetTranslatedStringByKey( key, [default] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Translation key |
| `default` | `string` | 是 | Default value |

**返回**：`value`: string（Translation）

示例：

```lua
function init()
	DebugPrint(GetTranslatedStringByKey("TOOL_CAMERA"))
end
```


### HasTranslationByKey

```lua
value = HasTranslationByKey( key )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `key` | `string` | 否 | Translation key |

**返回**：`value`: boolean（True if translation exists）

示例：

```lua
function init()
	DebugPrint(HasTranslationByKey("TOOL_CAMERA"))
end
```


### LoadLanguageTable

```lua
LoadLanguageTable( id )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 否 | Language id (enum) |

| Id | Language |
| --- | --- |
| 0 | English |
| 1 | French |
| 2 | Spanish |
| 3 | Italian |
| 4 | German |
| 5 | Simplified Chinese |
| 6 | Japanese |
| 7 | Russian |
| 8 | Polish |

示例：

```lua
function init()
	-- loads the english localization table
	LoadLanguageTable(0)
end
```


### GetUserNickname

```lua
value = GetUserNickname( [id] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 是 | User id |

**返回**：`value`: string（User nickname）

示例：

```lua
function init()
	DebugPrint(GetUserNickname(0))
end
```



---

## Events

| Event | Description | Parameters | Availability |
| --- | --- | --- | --- |
| playerhurt | Triggered when a player is hurt. | playerId (number), healthBefore (number), healthAfter (number), attackerId (number), point (TVec), impulse (TVec) | Server and Client |
| playerdied | Triggered when a player dies. | playerId (number), attackerId (number), damage (number), healthBefore (number), cause (string), point (TVec), impulse (TVec) | Server and Client |
| explosion | Triggered when an explosion occurs. | point (TVec), strength (number) | Server only |
| projectilehit | Triggered when a projectile hits an object. | shape (number), point (TVec), direction (TVec) | Server only |

<b>3 个函数</b>

### GetEventCount

```lua
value = GetEventCount( type )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `type` | `string` | 否 | Event type |

**返回**：`value`: number（Number of event available）

示例：

```lua
local count = GetEventCount("matchended")
for i=1, count do
	local name1, name2, score1, score2 = GetEvent("matchended", i)
end
```


### PostEvent

```lua
PostEvent( eventName, [param1, param2, .., paramN] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `eventName` | `string` | 否 | Event name |
| `param1, param2, .., paramN` | `any` | 是 | Optional parameters to send with the event. |

示例：

```lua
PostEvent("matchended", "team1", "team2", 5, 10)
```


### GetEvent

```lua
returnValues = GetEvent( type, index )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `type` | `string` | 否 | Event type |
| `index` | `number` | 否 | Event index (starting with one) |

**返回**：`returnValues`: varying（Return values depending on event type）

示例：

```lua
local count = GetEventCount("matchended")
for i=1, count do
	local name1, name2, score1, score2 = GetEvent("matchended", i)
end
```



---

## Vector math

<b>38 个函数</b>

### Vec

```lua
vec = Vec( [x], [y], [z] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 是 | X value |
| `y` | `number` | 是 | Y value |
| `z` | `number` | 是 | Z value |

**返回**：`vec`: TVec（New vector）

示例：

```lua
function init()
	--These are equivalent
	local a1 = Vec()
	local a2 = {0, 0, 0}
	DebugPrint("a1 == a2: " .. tostring(VecStr(a1) == VecStr(a2)))

	--These are equivalent
	local b1 = Vec(0, 1, 0)
	local b2 = {0, 1, 0}
	DebugPrint("b1 == b2: " .. tostring(VecStr(b1) == VecStr(b2)))
end
```


### VecCopy

```lua
new = VecCopy( org )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `org` | `TVec` | 否 | A vector |

**返回**：`new`: TVec（Copy of org vector）

示例：

```lua
function init()
	--Do this to assign a vector
	local right1 = Vec(1, 2, 3)
	local right2 = VecCopy(right1)

	--Never do this unless you REALLY know what you're doing
	local wrong1 = Vec(1, 2, 3)
	local wrong2 = wrong1
end
```


### VecStr

```lua
str = VecStr( vector )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vector` | `TVec` | 否 | Vector |

**返回**：`str`: string（String representation）

示例：

```lua
function init()
	local v = Vec(0, 10, 0)
	DebugPrint(VecStr(v))
end
```


### VecLength

```lua
length = VecLength( vec )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vec` | `TVec` | 否 | A vector |

**返回**：`length`: number（Length (magnitude) of the vector）

示例：

```lua
function init()
	local v = Vec(1,1,0)
	local l = VecLength(v)
	--l now equals 1.4142
	DebugPrint(l)
end
```


### VecNormalize

```lua
norm = VecNormalize( vec )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vec` | `TVec` | 否 | A vector |

**返回**：`norm`: TVec（A vector of length 1.0）

示例：

```lua
function init()
	local v = Vec(0,3,0)
	local n = VecNormalize(v)
	--n now equals {0,1,0}
	DebugPrint(VecStr(n))
end
```


### VecScale

```lua
norm = VecScale( vec, scale )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vec` | `TVec` | 否 | A vector |
| `scale` | `number` | 否 | A scale factor |

**返回**：`norm`: TVec（A scaled version of input vector）

示例：

```lua
function init()
	local v = Vec(1,2,3)
	local n = VecScale(v, 2)
	--n now equals {2,4,6}
	DebugPrint(VecStr(n))
end
```


### VecAdd

```lua
c = VecAdd( a, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TVec` | 否 | Vector |
| `b` | `TVec` | 否 | Vector |

**返回**：`c`: TVec（New vector with sum of a and b）

示例：

```lua
function init()
	local a = Vec(1,2,3)
	local b = Vec(3,0,0)
	local c = VecAdd(a, b)
	--c now equals {4,2,3}
	DebugPrint(VecStr(c))
end
```


### VecSub

```lua
c = VecSub( a, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TVec` | 否 | Vector |
| `b` | `TVec` | 否 | Vector |

**返回**：`c`: TVec（New vector representing a-b）

示例：

```lua
function init()
	local a = Vec(1,2,3)
	local b = Vec(3,0,0)
	local c = VecSub(a, b)
	--c now equals {-2,2,3}
	DebugPrint(VecStr(c))
end
```


### VecDot

```lua
c = VecDot( a, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TVec` | 否 | Vector |
| `b` | `TVec` | 否 | Vector |

**返回**：`c`: number（Dot product of a and b）

示例：

```lua
function init()
	local a = Vec(1,2,3)
	local b = Vec(3,1,0)
	local c = VecDot(a, b)
	--c now equals 5
	DebugPrint(c)
end
```


### VecCross

```lua
c = VecCross( a, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TVec` | 否 | Vector |
| `b` | `TVec` | 否 | Vector |

**返回**：`c`: TVec（Cross product of a and b (also called vector product)）

示例：

```lua
function init()
	local a = Vec(1,0,0)
	local b = Vec(0,1,0)
	local c = VecCross(a, b)
	--c now equals {0,0,1}
	DebugPrint(VecStr(c))
end
```


### VecLerp

```lua
c = VecLerp( a, b, t )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TVec` | 否 | Vector |
| `b` | `TVec` | 否 | Vector |
| `t` | `number` | 否 | fraction (usually between 0.0 and 1.0) |

**返回**：`c`: TVec（Linearly interpolated vector between a and b, using t）

示例：

```lua
function init()
	local a = Vec(2,0,0)
	local b = Vec(0,4,2)
	local t = 0.5
	
	--These two are equivalent
	local c1 = VecLerp(a, b, t)
	local c2 = VecAdd(VecScale(a, 1-t), VecScale(b, t))
	
	--c1 and c2 now equals {1, 2, 1}
	DebugPrint("c1" .. VecStr(c1) .. " == c2" .. VecStr(c2))
end
```


### Quat

```lua
quat = Quat( [x], [y], [z], [w] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 是 | X value |
| `y` | `number` | 是 | Y value |
| `z` | `number` | 是 | Z value |
| `w` | `number` | 是 | W value |

**返回**：`quat`: TQuat（New quaternion）

示例：

```lua
function init()
	--These are equivalent
	local a1 = Quat()
	local a2 = {0, 0, 0, 1}

	DebugPrint(QuatStr(a1) == QuatStr(a2))
end
```


### QuatCopy

```lua
new = QuatCopy( org )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `org` | `TQuat` | 否 | Quaternion |

**返回**：`new`: TQuat（Copy of org quaternion）

示例：

```lua
function init()
	--Do this to assign a quaternion
	local right1 = QuatEuler(0, 90, 0)
	local right2 = QuatCopy(right1)

	--Never do this unless you REALLY know what you're doing
	local wrong1 = QuatEuler(0, 90, 0)
	local wrong2 = wrong1
end
```


### QuatAxisAngle

```lua
quat = QuatAxisAngle( axis, angle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `axis` | `TVec` | 否 | Rotation axis, unit vector |
| `angle` | `number` | 否 | Rotation angle in degrees |

**返回**：`quat`: TQuat（New quaternion）

示例：

```lua
function init()
	--Create quaternion representing rotation 30 degrees around Y axis
	local q = QuatAxisAngle(Vec(0,1,0), 30)
	DebugPrint(QuatStr(q))
end
```


### QuatDeltaNormals

```lua
quat = QuatDeltaNormals( normal0, normal1 )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `normal0` | `TVec` | 否 | Unit vector |
| `normal1` | `TVec` | 否 | Unit vector |

**返回**：`quat`: TQuat（New quaternion）

示例：

```lua
function init()
	--Create quaternion representing a rotation between x-axis and y-axis
	local q = QuatDeltaNormals(Vec(1,0,0), Vec(0,1,0))
end
```


### QuatDeltaVectors

```lua
quat = QuatDeltaVectors( vector0, vector1 )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vector0` | `TVec` | 否 | Vector |
| `vector1` | `TVec` | 否 | Vector |

**返回**：`quat`: TQuat（New quaternion）

示例：

```lua
function init()
	--Create quaternion representing a rotation between two non-unit vectors aligned along x-axis and y-axis
	local q = QuatDeltaVectors(Vec(10,0,0), Vec(0,5,0))
end
```


### QuatEuler

```lua
quat = QuatEuler( x, y, z )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 否 | Angle around X axis in degrees, sometimes also called roll or bank |
| `y` | `number` | 否 | Angle around Y axis in degrees, sometimes also called yaw or heading |
| `z` | `number` | 否 | Angle around Z axis in degrees, sometimes also called pitch or attitude |

**返回**：`quat`: TQuat（New quaternion）

示例：

```lua
function init()
	--Create quaternion representing rotation 30 degrees around Y axis and 25 degrees around Z axis
	local q = QuatEuler(0, 30, 25)
end
```


### QuatAlignXZ

```lua
quat = QuatAlignXZ( xAxis, zAxis )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `xAxis` | `TVec` | 否 | X axis |
| `zAxis` | `TVec` | 否 | Z axis |

**返回**：`quat`: TQuat（Quaternion）

示例：

```lua
function update()
	local laserSprite = LoadSprite("gfx/laser.png")
	local origin = Vec(0, 0, 0)
	local dir = Vec(1, 0, 0)
	local length = 10
	local hitPoint = VecAdd(origin, VecScale(dir, length))
	local t = Transform(VecLerp(origin, hitPoint, 0.5))
	local xAxis = VecNormalize(VecSub(hitPoint, origin))
	local zAxis = VecNormalize(VecSub(origin, GetCameraTransform().pos))
	t.rot = QuatAlignXZ(xAxis, zAxis)
	DrawSprite(laserSprite, t, length, 0.05+math.random()*0.01, 8, 4, 4, 1, true, true)
	DrawSprite(laserSprite, t, length, 0.5, 1.0, 0.3, 0.3, 1, true, true)
end
```


### GetQuatEuler

```lua
x, y, z = GetQuatEuler( quat )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `quat` | `TQuat` | 否 | Quaternion |

**返回**：`x`: number（Angle around X axis in degrees, sometimes also called roll or bank）；`y`: number（Angle around Y axis in degrees, sometimes also called yaw or heading）；`z`: number（Angle around Z axis in degrees, sometimes also called pitch or attitude）

示例：

```lua
function init()
	--Return euler angles from quaternion q
	q = QuatEuler(30, 45, 0)
	rx, ry, rz = GetQuatEuler(q)
	DebugPrint(rx .. " " .. ry .. " " .. rz)
end
```


### QuatLookAt

```lua
quat = QuatLookAt( eye, target )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `eye` | `TVec` | 否 | Vector representing the camera location |
| `target` | `TVec` | 否 | Vector representing the point to look at |

**返回**：`quat`: TQuat（New quaternion）

示例：

```lua
function init()
	local eye = Vec(0, 10, 0)
	local target = Vec(0, 1, 5)
	local rot = QuatLookAt(eye, target)
	SetCameraTransform(Transform(eye, rot))
end
```


### QuatSlerp

```lua
c = QuatSlerp( a, b, t )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TQuat` | 否 | Quaternion |
| `b` | `TQuat` | 否 | Quaternion |
| `t` | `number` | 否 | fraction (usually between 0.0 and 1.0) |

**返回**：`c`: TQuat（New quaternion）

示例：

```lua
function init()
	local a = QuatEuler(0, 10, 0)
	local b = QuatEuler(0, 0, 45)

	--Create quaternion half way between a and b
	local q = QuatSlerp(a, b, 0.5)
	DebugPrint(QuatStr(q))
end
```


### QuatStr

```lua
str = QuatStr( quat )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `quat` | `TQuat` | 否 | Quaternion |

**返回**：`str`: string（String representation）

示例：

```lua
function init()
	local q = QuatEuler(0, 10, 0)
	DebugPrint(QuatStr(q))
end
```


### QuatRotateQuat

```lua
c = QuatRotateQuat( a, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TQuat` | 否 | Quaternion |
| `b` | `TQuat` | 否 | Quaternion |

**返回**：`c`: TQuat（New quaternion）

示例：

```lua
function init()
	local a = QuatEuler(0, 10, 0)
	local b = QuatEuler(0, 0, 45)
	local q = QuatRotateQuat(a, b)

	--q now represents a rotation first 10 degrees around
	--the Y axis and then 45 degrees around the Z axis.
	local x, y, z = GetQuatEuler(q)
	DebugPrint(x .. " " .. y .. " " .. z)
end
```


### QuatRotateVec

```lua
vec = QuatRotateVec( a, vec )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `TQuat` | 否 | Quaternion |
| `vec` | `TVec` | 否 | Vector |

**返回**：`vec`: TVec（Rotated vector）

示例：

```lua
function init()
	local q = QuatEuler(0, 10, 0)
	local v = Vec(1, 0, 0)
	local r = QuatRotateVec(q, v)
	
	--r is now vector a rotated 10 degrees around the Y axis
	DebugPrint(VecStr(r))
end
```


### Transform

```lua
transform = Transform( [pos], [rot] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `pos` | `TVec` | 是 | Vector representing transform position |
| `rot` | `TQuat` | 是 | Quaternion representing transform rotation |

**返回**：`transform`: TTransform（New transform）

示例：

```lua
function init()
	--Create transform located at {0, 0, 0} with no rotation
	local t1 = Transform()

	--Create transform located at {10, 0, 0} with no rotation
	local t2 = Transform(Vec(10, 0,0))

	--Create transform located at {10, 0, 0}, rotated 45 degrees around Y axis
	local t3 = Transform(Vec(10, 0,0), QuatEuler(0, 45, 0))

	DebugPrint(TransformStr(t1))
	DebugPrint(TransformStr(t2))
	DebugPrint(TransformStr(t3))
end
```


### TransformCopy

```lua
new = TransformCopy( org )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `org` | `TTransform` | 否 | Transform |

**返回**：`new`: TTransform（Copy of org transform）

示例：

```lua
function init()
	--Do this to assign a quaternion
	local right1 = Transform(Vec(1,0,0), QuatEuler(0, 90, 0))
	local right2 = TransformCopy(right1)

	--Never do this unless you REALLY know what you're doing
	local wrong1 = Transform(Vec(1,0,0), QuatEuler(0, 90, 0))
	local wrong2 = wrong1
end
```


### TransformStr

```lua
str = TransformStr( transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Transform |

**返回**：`str`: string（String representation）

示例：

```lua
function init()
	local eye = Vec(0, 10, 0)
	local target = Vec(0, 1, 5)
	local rot = QuatLookAt(eye, target)
	local t = Transform(eye, rot)
	DebugPrint(TransformStr(t))
end
```


### TransformToParentTransform

```lua
transform = TransformToParentTransform( parent, child )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `parent` | `TTransform` | 否 | Transform |
| `child` | `TTransform` | 否 | Transform |

**返回**：`transform`: TTransform（New transform）

示例：

```lua
function init()
	local b = GetBodyTransform(body)
	local s = GetShapeLocalTransform(shape)

	--b represents the location of body in world space
	--s represents the location of shape in body space

	local w = TransformToParentTransform(b, s)

	--w now represents the location of shape in world space
	DebugPrint(TransformStr(w))
end
```


### TransformToLocalTransform

```lua
transform = TransformToLocalTransform( parent, child )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `parent` | `TTransform` | 否 | Transform |
| `child` | `TTransform` | 否 | Transform |

**返回**：`transform`: TTransform（New transform）

示例：

```lua
function init()
	local b = GetBodyTransform(body)
	local w = GetShapeWorldTransform(shape)

	--b represents the location of body in world space
	--w represents the location of shape in world space
	
	local s = TransformToLocalTransform(b, w)

	--s now represents the location of shape in body space.
	DebugPrint(TransformStr(s))
end
```


### TransformToParentVec

```lua
r = TransformToParentVec( t, v )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `t` | `TTransform` | 否 | Transform |
| `v` | `TVec` | 否 | Vector |

**返回**：`r`: TVec（Transformed vector）

示例：

```lua
function init()
	local t = GetBodyTransform(body)
	local localUp = Vec(0, 1, 0)
	local up = TransformToParentVec(t, localUp)

	--up now represents the local body up direction in world space
	DebugPrint(VecStr(up))
end
```


### TransformToLocalVec

```lua
r = TransformToLocalVec( t, v )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `t` | `TTransform` | 否 | Transform |
| `v` | `TVec` | 否 | Vector |

**返回**：`r`: TVec（Transformed vector）

示例：

```lua
function init()
	local t = GetBodyTransform(body)
	local localUp = Vec(0, 1, 0)
	local up = TransformToParentVec(t, localUp)

	--up now represents the local body up direction in world space
	DebugPrint(VecStr(up))
end
```


### TransformToParentPoint

```lua
r = TransformToParentPoint( t, p )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `t` | `TTransform` | 否 | Transform |
| `p` | `TVec` | 否 | Vector representing position |

**返回**：`r`: TVec（Transformed position）

示例：

```lua
function init()
	local t = GetBodyTransform(body)
	local bodyPoint = Vec(0, 0, -1)
	local p = TransformToParentPoint(t, bodyPoint)

	--p now represents the local body point {0, 0, -1 } in world space
	DebugPrint(VecStr(p))
end
```


### TransformToLocalPoint

```lua
r = TransformToLocalPoint( t, p )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `t` | `TTransform` | 否 | Transform |
| `p` | `TVec` | 否 | Vector representing position |

**返回**：`r`: TVec（Transformed position）

示例：

```lua
function init()
	local t = GetBodyTransform(body)
	local worldOrigo = Vec(0, 0, 0)
	local p = TransformToLocalPoint(t, worldOrigo)

	--p now represents the position of world origo in local body space
	DebugPrint(VecStr(p))
end
```


### SetRandomSeed

```lua
SetRandomSeed( seed )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `seed` | `number` | 否 | Random seed |

示例：

```lua
function init()
	SetRandomSeed(42)
	result = RollDie()
end
```


### GetRandomBool

```lua
result = GetRandomBool(  )
```

**返回**：`result`: boolean（Random true/false）

示例：

```lua
function init()
	isHeads = GetRandomBool()

	if isHeads then
		win = true
	end
end
```


### GetRandomInt

```lua
result = GetRandomInt( min, max )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `min` | `number` | 否 | Lower number |
| `max` | `number` | 否 | Upper number |

**返回**：`result`: number（Random number in given range, including max.）

示例：

```lua
function init()
	dieRoll = GetRandomInt(1,6)
	-- dieRoll is 1,2,3,4,5 or 6
end
```


### GetRandomFloat

```lua
result = GetRandomFloat( min, max )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `min` | `number` | 否 | Lower number |
| `max` | `number` | 否 | Upper number |

**返回**：`result`: number（Random number in given range, including max.）

示例：

```lua
function init()
	-- Generate a random angle in range [0, 360]
	randomAngleDeg = GetRandomFloat(0.0f, 360.0f)
end
```


### GetRandomDirection

```lua
vector = GetRandomDirection( [length] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `length` | `number` | 是 | Optional length use to scale the generated direction. |

**返回**：`vector`: Vec3（Random direction with unit length）

示例：

```lua
function init()
	-- Generate a random direction.
	ricochetDirection = GetRandomDirection()
end
```



---

## Entity

<b>16 个函数</b>

### FindEntity

```lua
handle = FindEntity( [tag], [global], [type] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |
| `type` | `string` | 是 | Entity type ('body', 'shape', 'light', 'location' etc.) |

**返回**：`handle`: number（Handle to first entity with specified tag or zero if not found）

示例：

```lua
function client.tick()
	--You may use this function in a similar way to other "Find functions" like FindBody, FindShape, FindVehicle, etc.
	local myCar = FindEntity("myCar", false, "vehicle")

	--If you do not specify the tag, the first element found will be returned
	local joint = FindEntity("", true, "joint")

	--If the type is not specified, the search will be performed for all types of entity
	local target = FindEntity("target", true)
end
```


### FindEntities

```lua
list = FindEntities( [tag], [global], [type] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |
| `type` | `string` | 是 | Entity type ('body', 'shape', 'light', 'location' etc.) |

**返回**：`list`: table（Indexed table with handles to all entities with specified tag）

示例：

```lua
function client.tick()
	-- You may use this function in a similar way to other "Find functions" like FindBody, FindShape, FindVehicle, etc.
	local cars = FindEntities("car", false, "vehicle")

	-- You can get all the entities of the specified type by passing an empty string to the tag
	local allJoints = FindEntities("", true, "joint")

	-- If the type is not specified, the search will be performed for all types
	local allUnbreakables = FindEntities("unbreakable", true)
end
```


### GetEntityChildren

```lua
list = GetEntityChildren( handle, [tag], [recursive], [type] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `tag` | `string` | 是 | Tag name |
| `recursive` | `boolean` | 是 | Search recursively |
| `type` | `string` | 是 | Entity type ('body', 'shape', 'light', 'location' etc.) |

**返回**：`list`: table（Indexed table with child elements of the entity）

示例：

```lua
function client.tick()
	local car = FindEntity("car", true, "vehicle")
	DebugWatch("car", car)

	local children = GetEntityChildren(entity, "", true, "wheel")
	for i = 1, #children do
		DebugWatch("wheel " .. tostring(i), children[i])
	end
end
```


### GetEntityParent

```lua
handle = GetEntityParent( handle, [tag], [type] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `tag` | `string` | 是 | Tag name |
| `type` | `string` | 是 | Entity type ('body', 'shape', 'light', 'location' etc.) |

**返回**：`handle`: number

示例：

```lua
function client.tick()
	local wheel = FindEntity("", true, "wheel")
	local vehicle = GetEntityParent(wheel,  "", "vehicle")
	DebugWatch("Wheel vehicle", GetEntityType(vehicle) .. " " .. tostring(vehicle))
end
```


### SetTag

```lua
SetTag( handle, tag, [value] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `tag` | `string` | 否 | Tag name |
| `value` | `string` | 是 | Tag value |

示例：

```lua
function init()
	local handle = FindBody("body", true)
	--Add "special" tag to an entity
	SetTag(handle, "special")
	DebugPrint(HasTag(handle, "special"))

	--Add "team" tag to an entity and give it value "red"
	SetTag(handle, "team", "red")
	DebugPrint(HasTag(handle, "team"))
end
```


### RemoveTag

```lua
RemoveTag( handle, tag )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `tag` | `string` | 否 | Tag name |

示例：

```lua
function init()
	local handle = FindBody("body", true)
	--Add "special" tag to an entity
	SetTag(handle, "special")
	RemoveTag(handle, "special")
	DebugPrint(HasTag(handle, "special"))

	--Add "team" tag to an entity and give it value "red"
	SetTag(handle, "team", "red")
	DebugPrint(HasTag(handle, "team"))
end
```


### HasTag

```lua
exists = HasTag( handle, tag )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `tag` | `string` | 否 | Tag name |

**返回**：`exists`: boolean（Returns true if entity has tag）

示例：

```lua
function init()
	local handle = FindBody("body", true)
	--Add "special" tag to an entity
	SetTag(handle, "special")
	DebugPrint(HasTag(handle, "special"))

	--Add "team" tag to an entity and give it value "red"
	SetTag(handle, "team", "red")
	DebugPrint(HasTag(handle, "team"))
end
```


### GetTagValue

```lua
value = GetTagValue( handle, tag )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `tag` | `string` | 否 | Tag name |

**返回**：`value`: string（Returns the tag value, if any. Empty string otherwise.）

示例：

```lua
function init()
	local handle = FindBody("body", true)

	--Add "team" tag to an entity and give it value "red"
	SetTag(handle, "team", "red")
	DebugPrint(GetTagValue(handle, "team"))
end
```


### ListTags

```lua
tags = ListTags( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |

**返回**：`tags`: table（Indexed table of tags on entity）

示例：

```lua
function init()
	local handle = FindBody("body", true)

	--Add "team" tag to an entity and give it value "red"
	SetTag(handle, "team", "red")

	--List all tags and their tag values for a particular entity
	local tags = ListTags(handle)
	for i=1, #tags do
		DebugPrint(tags[i] .. " " .. GetTagValue(handle, tags[i]))
	end
end
```


### GetDescription

```lua
description = GetDescription( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |

**返回**：`description`: string（The description string）

示例：

```lua
function init()
	local body = FindBody("body", true)
	DebugPrint(GetDescription(body))
end
```


### SetDescription

```lua
SetDescription( handle, description )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `description` | `string` | 否 | The description string |

示例：

```lua
function init()
	local body = FindBody("body", true)
	SetDescription(body, "Target object")
	DebugPrint(GetDescription(body))
end
```


### Delete

```lua
Delete( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |

示例：

```lua
function init()
	local body = FindBody("body", true)
	--All shapes associated with body will also be removed
	Delete(body)
end
```


### IsHandleValid

```lua
exists = IsHandleValid( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |

**返回**：`exists`: boolean（Returns true if the entity pointed to by handle still exists）

示例：

```lua
function init()
	local body = FindBody("body", true)

	--valid is true if body still exists
	DebugPrint(IsHandleValid(body))
	Delete(body)

	--valid will now be false
	DebugPrint(IsHandleValid(body))
end
```


### GetEntityType

```lua
type = GetEntityType( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |

**返回**：`type`: string（Type name of the provided entity）

示例：

```lua
function init()
	local body = FindBody("body", true)
	DebugPrint(GetEntityType(body))
end
```


### GetProperty

```lua
value = GetProperty( handle, property )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `property` | `string` | 否 | Property name |

**返回**：`value`: any（Property value）

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

示例：

```lua
function client.tick()
	local body = FindBody("testbody", true)
	local isDynamic = GetProperty(body, "dynamic")
	DebugWatch("isDynamic", isDynamic)
end
```


### SetProperty

```lua
SetProperty( handle, property, value )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Entity handle |
| `property` | `string` | 否 | Property name |
| `value` | `any` | 否 | Property value |

| Entity type | Available params |
| --- | --- |
| Body | desc (string), dynamic (boolean), transform, velocity (vector(x, y, z)), angVelocity (vector(x,y,z)), active (boolean), friction (number), restitution (number), frictionMode (average\|minimum\|multiply\|maximum), restitutionMode (average\|minimum\|multiply\|maximum) |
| Shape | density (number), strength (number), emissiveScale (number), localTransform |
| Light | enabled (boolean), color (vector(r, g, b)), intensity (number), transform, size (number/vector(x,y)), reach (number), unshadowed (number), fogscale (number), fogiter (number), glare (number) |
| Location | transform |
| Water | type (string), depth (number), wave (number), ripple (number), motion (number), foam (number), color (vector(r, g, b)) |
| Joint | size (number), rotstrength (number), rotspring (number); only for ropes: slack (number), strength (number), maxstretch (number), color (vector(r, g, b)) |
| Vehicle | spring (number), damping (number), topspeed (number), acceleration (number), strength (number), antispin (number), antiroll (number), difflock (number), steerassist (number), friction (number), smokeintensity (number), transform, brokenthreshold (number) |
| Wheel | drive (number), steer (number), travel (vector(x, y)) |
| Screen | enabled (boolean), interactive (boolean), emissive (number), fxraster (number), fxca (number), fxnoise (number), fxglitch (number) |
| Trigger | transform, size (vector(x, y, z)/number) |

示例：

```lua
function tick()
	local light = FindLight("mylight", true)
	SetProperty(light, "intensity", math.abs(math.sin(GetTime())))
end
```



---

## Body

<b>33 个函数</b>

### FindBody

```lua
handle = FindBody( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first body with specified tag or zero if not found）

示例：

```lua
function init()
	--Search for a body tagged "target" in script scope
	local target = FindBody("body")
	DebugPrint(target)

	--Search for a body tagged "escape" in entire scene
	local escape = FindBody("body", true)
	DebugPrint(escape)
end
```


### FindBodies

```lua
list = FindBodies( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all bodies with specified tag）

示例：

```lua
function init()
	--Search for bodies tagged "target" in script scope
	local targets = FindBodies("target", true)
	for i=1, #targets do
		local target = targets[i]
		DebugPrint(target)
	end
end
```


### GetBodyTransform

```lua
transform = GetBodyTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`transform`: TTransform（Transform of the body）

示例：

```lua
function init()
	local handle = FindBody("target", true)
	local t = GetBodyTransform(handle)
	DebugPrint(TransformStr(t))
end
```


### SetBodyTransform

```lua
SetBodyTransform( handle, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |
| `transform` | `TTransform` | 否 | Desired transform |

示例：

```lua
function init()
	local handle = FindBody("body", true)

	--Move a body 1 meter upwards
	local t = GetBodyTransform(handle)
	t.pos = VecAdd(t.pos, Vec(0, 3, 0))
	SetBodyTransform(handle, t)
end
```


### GetBodyMass

```lua
mass = GetBodyMass( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`mass`: number（Body mass. Static bodies always return zero mass.）

示例：

```lua
function init()
	local handle = FindBody("body", true)

	--Move a body 1 meter upwards
	local mass = GetBodyMass(handle)
	DebugPrint(mass)
end
```


### IsBodyDynamic

```lua
dynamic = IsBodyDynamic( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`dynamic`: boolean（Return true if body is dynamic）

示例：

```lua
function init()
	local handle = FindBody("body", true)
	DebugPrint(IsBodyDynamic(handle))
end
```


### SetBodyDynamic

```lua
SetBodyDynamic( handle, dynamic )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |
| `dynamic` | `boolean` | 否 | True for dynamic. False for static. |

示例：

```lua
function init()
	local handle = FindBody("body", true)
	SetBodyDynamic(handle, false)
	DebugPrint(IsBodyDynamic(handle))
end
```


### SetBodyVelocity

```lua
SetBodyVelocity( handle, velocity )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |
| `velocity` | `TVec` | 否 | Vector with linear velocity |

示例：

```lua
function init()
	local handle = FindBody("body", true)
	local vel = Vec(0,10,0)
	SetBodyVelocity(handle, vel)
end
```


### GetBodyVelocity

```lua
velocity = GetBodyVelocity( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |

**返回**：`velocity`: TVec（Linear velocity as vector）

示例：

```lua
handle = 0
function server.init()
	handle = FindBody("body", true)
	local vel = Vec(0,10,0)
	SetBodyVelocity(handle, vel)
end

function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	DebugPrint(VecStr(GetBodyVelocity(handle)))
end
```


### GetBodyVelocityAtPos

```lua
velocity = GetBodyVelocityAtPos( handle, pos )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |
| `pos` | `TVec` | 否 | World space point as vector |

**返回**：`velocity`: TVec（Linear velocity on body at pos as vector）

示例：

```lua
handle = 0
function server.init()
	handle = FindBody("body", true)
	local vel = Vec(0,10,0)
	SetBodyVelocity(handle, vel)
end

function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	DebugPrint(VecStr(GetBodyVelocityAtPos(handle, Vec(0, 0, 0))))
end
```


### SetBodyAngularVelocity

```lua
SetBodyAngularVelocity( handle, angVel )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |
| `angVel` | `TVec` | 否 | Vector with angular velocity |

示例：

```lua
function server.init()
	handle = FindBody("body", true)
	local angVel = Vec(0,100,0)
	SetBodyAngularVelocity(handle, angVel)
end
```


### GetBodyAngularVelocity

```lua
angVel = GetBodyAngularVelocity( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |

**返回**：`angVel`: TVec（Angular velocity as vector）

示例：

```lua
handle = 0
function server.init()
	handle = FindBody("body", true)
	local angVel = Vec(0,100,0)
	SetBodyAngularVelocity(handle, angVel)
end

function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	DebugPrint(VecStr(GetBodyAngularVelocity(handle)))
end
```


### SetBodyGravityScale

```lua
SetBodyGravityScale( handle, scale )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |
| `scale` | `number` | 否 | Gravity scale |

示例：

```lua
function server.init()
	balloonBody = FindBody("ballon", true)
	SetBodyGravityScale(balloonBody, -0.3)
end
```


### IsBodyActive

```lua
active = IsBodyActive( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`active`: boolean（Return true if body is active）

示例：

```lua
-- try to break the body to see the logs
function client.tick()
	handle = FindBody("body", true)
	if IsBodyActive(handle) then
		DebugPrint("Body is active")
	end
end
```


### SetBodyActive

```lua
SetBodyActive( handle, active )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |
| `active` | `boolean` | 否 | Set to tru if body should be active (simulated) |

示例：

```lua
handle = 0
function server.tick()
	handle = FindBody("body", true)

	-- Forces body to "sleep"
	SetBodyActive(handle, false)
end

function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	handle = FindBody("body", true)

	if IsBodyActive(handle) then
		DebugPrint("Body is active")
	end
end
```


### ApplyBodyImpulse

```lua
ApplyBodyImpulse( handle, position, impulse )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle (should be a dynamic body) |
| `position` | `TVec` | 否 | World space position as vector |
| `impulse` | `TVec` | 否 | World space impulse as vector |

示例：

```lua
function applyImpulse()
	handle = FindBody("body", true)

	local pos = Vec(0,1,0)
	local imp = Vec(0,0,10)
	ApplyBodyImpulse(handle, pos, imp)
end
```


### GetBodyShapes

```lua
list = GetBodyShapes( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`list`: table（Indexed table of shape handles）

示例：

```lua
function client.init()
	handle = FindBody("body", true)

	local shapes = GetBodyShapes(handle)
	for i=1,#shapes do
		local shape = shapes[i]
		DebugPrint(shape)
	end
end
```


### GetBodyVehicle

```lua
handle = GetBodyVehicle( body )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle |

**返回**：`handle`: number（Get parent vehicle for body, or zero if not part of vehicle）

示例：

```lua
function client.init()
	handle = FindBody("body", true)

	local vehicle = GetBodyVehicle(handle)
	DebugPrint(vehicle)
end
```


### GetBodyAnimator

```lua
handle = GetBodyAnimator( body )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle |

**返回**：`handle`: number（Get parent animator for body, or zero if not part of an animator hierarchy）

示例：

```lua
local animator = GetBodyAnimator(body)
```


### GetBodyPlayer

```lua
playerId = GetBodyPlayer( body )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle |

**返回**：`playerId`: number（Get parent player for body, or zero if not part of a player animator hierarchy）

示例：

```lua
local player = GetBodyPlayer(body)
```


### GetBodyBounds

```lua
min, max = GetBodyBounds( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`min`: TVec（Vector representing the AABB lower bound）；`max`: TVec（Vector representing the AABB upper bound）

示例：

```lua
function client.init()
	handle = FindBody("body", true)

	local min, max = GetBodyBounds(handle)
	local boundsSize = VecSub(max, min)
	local center = VecLerp(min, max, 0.5)
	DebugPrint(VecStr(boundsSize) .. " " .. VecStr(center))
end
```


### GetBodyCenterOfMass

```lua
point = GetBodyCenterOfMass( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`point`: TVec（Vector representing local center of mass in body space）

示例：

```lua
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	--Visualize center of mass on for body
	local com = GetBodyCenterOfMass(handle)
	local worldPoint = TransformToParentPoint(GetBodyTransform(handle), com)
	DebugCross(worldPoint)
end
```


### IsBodyVisible

```lua
visible = IsBodyVisible( handle, maxDist, [rejectTransparent], [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |
| `maxDist` | `number` | 否 | Maximum visible distance |
| `rejectTransparent` | `boolean` | 是 | See through transparent materials. Default false. |
| `playerId` | `number` | 是 | Player ID. On player, zero means local player. |

**返回**：`visible`: boolean（Return true if body is visible）

示例：

```lua
local handle = 0
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	if IsBodyVisible(handle, 25) then
		--Body is within 25 meters visible to the camera
		DebugPrint("visible")
	else
		DebugPrint("not visible")
	end
end
```


### IsBodyBroken

```lua
broken = IsBodyBroken( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`broken`: boolean（Return true if body is broken）

示例：

```lua
local handle = 0
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	DebugPrint(IsBodyBroken(handle))
end
```


### IsBodyJointedToStatic

```lua
result = IsBodyJointedToStatic( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |

**返回**：`result`: boolean（Return true if body is in any way connected to a static body）

示例：

```lua
local handle = 0
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	DebugPrint(IsBodyJointedToStatic(handle))
end
```


### DrawBodyOutline

```lua
DrawBodyOutline( handle, [r], [g], [b], [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |
| `r` | `number` | 是 | Red |
| `g` | `number` | 是 | Green |
| `b` | `number` | 是 | Blue |
| `a` | `number` | 是 | Alpha |

示例：

```lua
local handle = 0
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	if InputDown("interact") then
		--Draw white outline at 50% transparency
		DrawBodyOutline(handle, 0.5)
	else
		--Draw green outline, fully opaque
		DrawBodyOutline(handle, 0, 1, 0, 1)
	end
end
```


### DrawBodyHighlight

```lua
DrawBodyHighlight( handle, amount )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body handle |
| `amount` | `number` | 否 | Amount |

示例：

```lua
local handle = 0
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	if InputDown("interact") then
		DrawBodyHighlight(handle, 0.5)
	end
end
```


### GetBodyClosestPoint

```lua
hit, point, normal, shape = GetBodyClosestPoint( body, origin )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle |
| `origin` | `TVec` | 否 | World space point |

**返回**：`hit`: boolean（True if a point was found）；`point`: TVec（World space closest point）；`normal`: TVec（World space normal at closest point）；`shape`: number（Handle to closest shape）

示例：

```lua
local handle = 0
function client.init()
	handle = FindBody("body", true)
end

function client.tick()
	DebugCross(Vec(1, 0, 0))
	local hit, p, n, s = GetBodyClosestPoint(handle, Vec(1, 0, 0))
	if hit then
		DebugCross(p)
	end
end
```


### ConstrainVelocity

```lua
ConstrainVelocity( bodyA, bodyB, point, dir, relVel, [min], [max] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bodyA` | `number` | 否 | First body handle (zero for static) |
| `bodyB` | `number` | 否 | Second body handle (zero for static) |
| `point` | `TVec` | 否 | World space point |
| `dir` | `TVec` | 否 | World space direction |
| `relVel` | `number` | 否 | Desired relative velocity along the provided direction |
| `min` | `number` | 是 | Minimum impulse (default: -infinity) |
| `max` | `number` | 是 | Maximum impulse (default: infinity) |

示例：

```lua
local handleA = 0
local handleB = 0
function server.init()
	handleA = FindBody("body", true)
	handleB = FindBody("target", true)
end

function server.update()
	--Constrain the velocity between bodies A and B so that the relative velocity
	--along the X axis at point (0, 5, 0) is always 3 m/s
	ConstrainVelocity(handleA, handleB, Vec(0, 5, 0), Vec(1, 0, 0), 3)
end
```


### ConstrainAngularVelocity

```lua
ConstrainAngularVelocity( bodyA, bodyB, dir, relAngVel, [min], [max] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bodyA` | `number` | 否 | First body handle (zero for static) |
| `bodyB` | `number` | 否 | Second body handle (zero for static) |
| `dir` | `TVec` | 否 | World space direction |
| `relAngVel` | `number` | 否 | Desired relative angular velocity along the provided direction |
| `min` | `number` | 是 | Minimum angular impulse (default: -infinity) |
| `max` | `number` | 是 | Maximum angular impulse (default: infinity) |

示例：

```lua
local handleA = 0
local handleB = 0
function server.init()
	handleA = FindBody("body", true)
	handleB = FindBody("target", true)
end

function server.update()
	--Constrain the angular velocity between bodies A and B so that the relative angular velocity
	--along the Y axis is always 3 rad/s
	ConstrainAngularVelocity(handleA, handleB, Vec(1, 0, 0), 3)
end
```


### ConstrainPosition

```lua
ConstrainPosition( bodyA, bodyB, pointA, pointB, [maxVel], [maxImpulse] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bodyA` | `number` | 否 | First body handle (zero for static) |
| `bodyB` | `number` | 否 | Second body handle (zero for static) |
| `pointA` | `TVec` | 否 | World space point for first body |
| `pointB` | `TVec` | 否 | World space point for second body |
| `maxVel` | `number` | 是 | Maximum relative velocity (default: infinite) |
| `maxImpulse` | `number` | 是 | Maximum impulse (default: infinite) |

示例：

```lua
local handleA = 0
local handleB = 0
function server.init()
	handleA = FindBody("body", true)
	handleB = FindBody("target", true)
end

function server.update()
	--Constrain the origo of body a to an animated point in the world
	local worldPos = Vec(0, 3+math.sin(GetTime()), 0)
	ConstrainPosition(handleA, 0, GetBodyTransform(handleA).pos, worldPos)

	--Constrain the origo of body a to the origo of body b (like a ball joint)
	ConstrainPosition(handleA, handleA, GetBodyTransform(handleA).pos, GetBodyTransform(handleB).pos)
end
```


### ConstrainOrientation

```lua
ConstrainOrientation( bodyA, bodyB, quatA, quatB, [maxAngVel], [maxAngImpulse] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bodyA` | `number` | 否 | First body handle (zero for static) |
| `bodyB` | `number` | 否 | Second body handle (zero for static) |
| `quatA` | `TQuat` | 否 | World space orientation for first body |
| `quatB` | `TQuat` | 否 | World space orientation for second body |
| `maxAngVel` | `number` | 是 | Maximum relative angular velocity (default: infinite) |
| `maxAngImpulse` | `number` | 是 | Maximum angular impulse (default: infinite) |

示例：

```lua
local handleA = 0
local handleB = 0
function server.init()
	handleA = FindBody("body", true)
	handleB = FindBody("target", true)
end

function server.update()
	--Constrain the orietation of body a to an upright orientation in the world
	ConstrainOrientation(handleA, 0, GetBodyTransform(handleA).rot, Quat())

	--Constrain the orientation of body a to the orientation of body b
	ConstrainOrientation(handleA, handleB, GetBodyTransform(handleA).rot, GetBodyTransform(handleB).rot)
end
```


### GetWorldBody

```lua
body = GetWorldBody(  )
```

**返回**：`body`: number（Handle to the static world body）

示例：

```lua
local handle
function client.init()
	handle = GetWorldBody()
end

function client.tick()
	DebugCross(GetBodyTransform(handle).pos)
end
```



---

## Shape

<b>40 个函数</b>

### FindShape

```lua
handle = FindShape( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first shape with specified tag or zero if not found）

示例：

```lua
local target = 0
local escape = 0
function client.init()
	--Search for a shape tagged "mybox" in script scope
	target = FindShape("mybox")

	--Search for a shape tagged "laserturret" in entire scene
	escape = FindShape("laserturret", true)
end

function client.tick()
	DebugCross(GetShapeWorldTransform(target).pos)
	DebugCross(GetShapeWorldTransform(escape).pos)
end
```


### FindShapes

```lua
list = FindShapes( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all shapes with specified tag）

示例：

```lua
local shapes = {}
function client.init()
	--Search for shapes tagged "body"
	shapes = FindShapes("body", true)
end

function client.tick()
	for i=1, #shapes do
		local shape = shapes[i]
		DebugCross(GetShapeWorldTransform(shape).pos)
	end
end
```


### GetShapeLocalTransform

```lua
transform = GetShapeLocalTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`transform`: TTransform（Return shape transform in body space）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape")
end

function client.tick()
	--Shape transform in body local space
	local shapeTransform = GetShapeLocalTransform(shape)

	--Body transform in world space
	local bodyTransform = GetBodyTransform(GetShapeBody(shape))

	--Shape transform in world space
	local worldTranform = TransformToParentTransform(bodyTransform, shapeTransform)

	DebugCross(worldTranform)
end
```


### SetShapeLocalTransform

```lua
SetShapeLocalTransform( handle, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `transform` | `TTransform` | 否 | Shape transform in body space |

示例：

```lua
local shape = 0
function server.init()
	shape = FindShape("shape")
	local transform = Transform(Vec(0, 1, 0), QuatEuler(0, 90, 0))
	SetShapeLocalTransform(shape, transform)
end

function client.init()
	shape = FindShape("shape")
end

function client.tick()
	--Shape transform in body local space
	local shapeTransform = GetShapeLocalTransform(shape)

	--Body transform in world space
	local bodyTransform = GetBodyTransform(GetShapeBody(shape))

	--Shape transform in world space
	local worldTranform = TransformToParentTransform(bodyTransform, shapeTransform)

	DebugCross(worldTranform)
end
```


### GetShapeWorldTransform

```lua
transform = GetShapeWorldTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`transform`: TTransform（Return shape transform in world space）

示例：

```lua
--GetShapeWorldTransform is equivalent to
--local shapeTransform = GetShapeLocalTransform(shape)
--local bodyTransform = GetBodyTransform(GetShapeBody(shape))
--worldTranform = TransformToParentTransform(bodyTransform, shapeTransform)

local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	DebugCross(GetShapeWorldTransform(shape).pos)
end
```


### GetShapeBody

```lua
handle = GetShapeBody( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`handle`: number（Body handle）

示例：

```lua
local body = 0
function client.init()
	body = GetShapeBody(FindShape("shape", true))
end

function client.tick()
	DebugCross(GetBodyCenterOfMass(body))
end
```


### GetShapeJoints

```lua
list = GetShapeJoints( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |

**返回**：`list`: table（Indexed table with joints connected to shape）

示例：

```lua
function printJoints()
	local shape = FindShape("shape", true)

	local hinges = GetShapeJoints(shape)
	for i=1, #hinges do
		local joint = hinges[i]
		DebugPrint(joint)
	end
end
```


### GetShapeLights

```lua
list = GetShapeLights( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |

**返回**：`list`: table（Indexed table of lights owned by shape）

示例：

```lua
function printLights()
	--Print all lights owned by a shape
	local shape = FindShape("shape", true)

	local light = GetShapeLights(shape)
	for i=1, #light do
		DebugPrint(light[i])
	end
end
```


### GetShapeBounds

```lua
min, max = GetShapeBounds( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`min`: TVec（Vector representing the AABB lower bound）；`max`: TVec（Vector representing the AABB upper bound）

示例：

```lua
function printShapeBounds()
	local shape = FindShape("shape", true)

	local min, max = GetShapeBounds(shape)
	local boundsSize = VecSub(max, min)
	local center = VecLerp(min, max, 0.5)

	DebugPrint(VecStr(boundsSize) .. " " .. VecStr(center))
end
```


### SetShapeEmissiveScale

```lua
SetShapeEmissiveScale( handle, scale )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `scale` | `number` | 否 | Scale factor for emissiveness |

示例：

```lua
local shape = 0
function server.init()
	shape = FindShape("shape", true)

	--Pulsate emissiveness and light intensity for shape
	local scale = math.sin(GetTime())*0.5 + 0.5
	SetShapeEmissiveScale(shape, scale)
end
```


### SetShapeDensity

```lua
SetShapeDensity( handle, density )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `density` | `number` | 否 | New density for the shape |

示例：

```lua
local shape = 0
function server.init()
	shape = FindShape("shape", true)

	local density = 10.0
	SetShapeDensity(shape, density)
end
```


### GetShapeMaterialAtPosition

```lua
type, r, g, b, a, entry = GetShapeMaterialAtPosition( handle, pos, [includeUnphysical] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `pos` | `TVec` | 否 | Position in world space |
| `includeUnphysical` | `boolean` | 是 | Include unphysical voxels in the search. Default false. |

**返回**：`type`: string（Material type）；`r`: number（Red）；`g`: number（Green）；`b`: number（Blue）；`a`: number（Alpha）；`entry`: number（Palette entry for voxel (zero if empty)）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	local pos = GetCameraTransform().pos
	local dir = Vec(0, 0, 1)
	local hit, dist, normal, shape = QueryRaycast(pos, dir, 10)
	if hit then
		local hitPoint = VecAdd(pos, VecScale(dir, dist))
		local mat = GetShapeMaterialAtPosition(shape, hitPoint)
		DebugPrint("Raycast hit voxel made out of " .. mat)
	end
	DebugLine(pos, VecAdd(pos, VecScale(dir, 10)))
end
```


### GetShapeMaterialAtIndex

```lua
type, r, g, b, a, entry = GetShapeMaterialAtIndex( handle, x, y, z )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `x` | `number` | 否 | X integer coordinate |
| `y` | `number` | 否 | Y integer coordinate |
| `z` | `number` | 否 | Z integer coordinate |

**返回**：`type`: string（Material type）；`r`: number（Red）；`g`: number（Green）；`b`: number（Blue）；`a`: number（Alpha）；`entry`: number（Palette entry for voxel (zero if empty)）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
	local mat = GetShapeMaterialAtIndex(shape, 0, 0, 0)
	DebugPrint("The voxel is of material: " .. mat)
end
```


### GetShapeSize

```lua
xsize, ysize, zsize, scale = GetShapeSize( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`xsize`: number（Size in voxels along x axis）；`ysize`: number（Size in voxels along y axis）；`zsize`: number（Size in voxels along z axis）；`scale`: number（The size of one voxel in meters (with default scale it is 0.1)）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
	local x, y, z = GetShapeSize(shape)
	DebugPrint("Shape size: " .. x .. ";" .. y .. ";" .. z)
end
```


### GetShapeVoxelCount

```lua
count = GetShapeVoxelCount( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`count`: number（Number of voxels in shape）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
	local voxelCount = GetShapeVoxelCount(shape)
	DebugPrint(voxelCount)
end
```


### IsShapeVisible

```lua
visible = IsShapeVisible( handle, maxDist, [rejectTransparent], [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `maxDist` | `number` | 否 | Maximum visible distance |
| `rejectTransparent` | `boolean` | 是 | See through transparent materials. Default false. |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server(host) player. |

**返回**：`visible`: boolean（Return true if shape is visible）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	if IsShapeVisible(shape, 25) then
		DebugPrint("Shape is visible")
	else
		DebugPrint("Shape is not visible")
	end
end
```


### IsShapeBroken

```lua
broken = IsShapeBroken( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`broken`: boolean（Return true if shape is broken）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	DebugPrint("Is shape broken: " .. tostring(IsShapeBroken(shape)))
end
```


### DrawShapeOutline

```lua
DrawShapeOutline( handle, [r], [g], [b], a )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `r` | `number` | 是 | Red |
| `g` | `number` | 是 | Green |
| `b` | `number` | 是 | Blue |
| `a` | `number` | 否 | Alpha |

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	if InputDown("interact") then
		--Draw white outline at 50% transparency
		DrawShapeOutline(shape, 0.5)
	else
		--Draw green outline, fully opaque
		DrawShapeOutline(shape, 0, 1, 0, 1)
	end
end
```


### DrawShapeHighlight

```lua
DrawShapeHighlight( handle, amount )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `amount` | `number` | 否 | Amount |

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	if InputDown("interact") then
		DrawShapeHighlight(shape, 0.5)
	end
end
```


### SetShapeCollisionFilter

```lua
SetShapeCollisionFilter( handle, layer, mask )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |
| `layer` | `number` | 否 | Layer bits (0-255) |
| `mask` | `number` | 否 | Mask bits (0-255) |

示例：

```lua
local shapeA = 0
local shapeB = 0
local shapeC = 0
local shapeD = 0
function server.init()
	shapeA = FindShape("shapeA")
	shapeB = FindShape("shapeB")
	shapeC = FindShape("shapeC")
	shapeD = FindShape("shapeD")
	--This will put shapes a and b in layer 2 and disable collisions with
	--object shapes in layers 2, preventing any collisions between the two.
	SetShapeCollisionFilter(shapeA, 2, 255-2)
	SetShapeCollisionFilter(shapeB, 2, 255-2)

	--This will put shapes c and d in layer 4 and allow collisions with other
	--shapes in layer 4, but ignore all other collisions with the rest of the world.
	SetShapeCollisionFilter(shapeC, 4, 4)
	SetShapeCollisionFilter(shapeD, 4, 4)
end
```


### GetShapeCollisionFilter

```lua
layer, mask = GetShapeCollisionFilter( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Shape handle |

**返回**：`layer`: number（Layer bits (0-255)）；`mask`: number（Mask bits (0-255)）

示例：

```lua
function server.init()
	local shape = FindShape("some_shape")
	local layer, mask = GetShapeCollisionFilter(shape)
end
```


### CreateShape

```lua
newShape = CreateShape( body, transform, refShape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle |
| `transform` | `TTransform` | 否 | Shape transform in body space |
| `refShape` | `number or string` | 否 | Handle to reference shape or path to vox file |

**返回**：`newShape`: number（Handle of new shape）

示例：

```lua
server.tick()
	local players = GetAllPlayers()
	for i=1, #players do
		tickPlayer(players[i])
	end
end

function tickPlayer(playerId)
	if InputPressed("interact", playerId) then
		local t = Transform(Vec(0, 5, 0), QuatEuler(0, 0, 0))
		local handle = CreateShape(FindBody("shape", true), t, FindShape("shape", true))
		DebugPrint(handle)
	end
end
```


### ClearShape

```lua
ClearShape( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |

示例：

```lua
function server.init()
	ClearShape(FindShape("shape", true))
end
```


### ResizeShape

```lua
resized, offset = ResizeShape( shape, xmi, ymi, zmi, xma, yma, zma )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |
| `xmi` | `number` | 否 | Lower X coordinate |
| `ymi` | `number` | 否 | Lower Y coordinate |
| `zmi` | `number` | 否 | Lower Z coordinate |
| `xma` | `number` | 否 | Upper X coordinate |
| `yma` | `number` | 否 | Upper Y coordinate |
| `zma` | `number` | 否 | Upper Z coordinate |

**返回**：`resized`: boolean（Resized successfully）；`offset`: TVec（Offset vector in shape local space）

示例：

```lua
function server.init()
	ResizeShape(FindShape("shape", true), -5, 0, -5, 5, 5, 5)
end
```


### SetShapeBody

```lua
SetShapeBody( shape, body, [transform] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |
| `body` | `number` | 否 | Body handle |
| `transform` | `TTransform` | 是 | New local shape transform. Default is existing local transform. |

示例：

```lua
function server.init()
	SetShapeBody(FindShape("shape", true), FindBody("custombody", true), true)
end
```


### CopyShapeContent

```lua
CopyShapeContent( src, dst )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `src` | `number` | 否 | Source shape handle |
| `dst` | `number` | 否 | Destination shape handle |

示例：

```lua
function server.init()
	CopyShapeContent(FindShape("shape", true), FindShape("shape2", true))
end
```


### CopyShapePalette

```lua
CopyShapePalette( src, dst )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `src` | `number` | 否 | Source shape handle |
| `dst` | `number` | 否 | Destination shape handle |

示例：

```lua
function server.init()
	CopyShapePalette(FindShape("shape", true), FindShape("shape2", true))
end
```


### GetShapePalette

```lua
entries = GetShapePalette( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |

**返回**：`entries`: table（Palette material entries）

示例：

```lua
function server.init()
	local palette = GetShapePalette(FindShape("shape2", true))
	for i = 1, #palette do
		DebugPrint(palette[i])
	end
end
```


### GetShapeMaterial

```lua
type, red, green, blue, alpha, reflectivity, shininess, metallic, emissive = GetShapeMaterial( shape, entry )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |
| `entry` | `number` | 否 | Material entry |

**返回**：`type`: string（Type）；`red`: number（Red value）；`green`: number（Green value）；`blue`: number（Blue value）；`alpha`: number（Alpha value）；`reflectivity`: number（Range 0 to 1）；`shininess`: number（Range 0 to 1）；`metallic`: number（Range 0 to 1）；`emissive`: number（Range 0 to 32）

示例：

```lua
function client.init()
	local type, r, g, b, a, reflectivity, shininess, metallic, emissive = GetShapeMaterial(FindShape("shape2", true), 1)
	DebugPrint(type)
end
```


### SetBrush

```lua
SetBrush( type, size, index or path, [object] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `type` | `string` | 否 | One of 'sphere', 'cube' or 'noise' |
| `size` | `number` | 否 | Size of brush in voxels (must be in range 1 to 16) |
| `index or path` | `number or string` | 否 | Material index or path to brush vox file |
| `object` | `string` | 是 | Optional object in brush vox file if brush vox file is used |

示例：

```lua
function server.init()
	SetBrush("sphere", 3, 3)
end
```


### DrawShapeLine

```lua
DrawShapeLine( shape, x0, y0, z0, x1, y1, z1, [paint], [noOverwrite] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Handle to shape |
| `x0` | `number` | 否 | Start X coordinate |
| `y0` | `number` | 否 | Start Y coordinate |
| `z0` | `number` | 否 | Start Z coordinate |
| `x1` | `number` | 否 | End X coordinate |
| `y1` | `number` | 否 | End Y coordinate |
| `z1` | `number` | 否 | End Z coordinate |
| `paint` | `boolean` | 是 | Paint mode. Default is false. |
| `noOverwrite` | `boolean` | 是 | Only fill in voxels if space isn't already occupied. Default is false. |

示例：

```lua
function server.init()
	SetBrush("sphere", 3, 1)
	DrawShapeLine(FindShape("shape"), 0, 0, 0, 10, 50, 5, false, true)
end
```


### DrawShapeBox

```lua
DrawShapeBox( shape, x0, y0, z0, x1, y1, z1 )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Handle to shape |
| `x0` | `number` | 否 | Start X coordinate |
| `y0` | `number` | 否 | Start Y coordinate |
| `z0` | `number` | 否 | Start Z coordinate |
| `x1` | `number` | 否 | End X coordinate |
| `y1` | `number` | 否 | End Y coordinate |
| `z1` | `number` | 否 | End Z coordinate |

示例：

```lua
function server.init()
	SetBrush("sphere", 3, 4)
	DrawShapeBox(FindShape("shape", true), 0, 0, 0, 10, 50, 5)
end
```


### ExtrudeShape

```lua
ExtrudeShape( shape, x, y, z, dx, dy, dz, steps, mode )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Handle to shape |
| `x` | `number` | 否 | X coordinate to extrude |
| `y` | `number` | 否 | Y coordinate to extrude |
| `z` | `number` | 否 | Z coordinate to extrude |
| `dx` | `number` | 否 | X component of extrude direction, should be -1, 0 or 1 |
| `dy` | `number` | 否 | Y component of extrude direction, should be -1, 0 or 1 |
| `dz` | `number` | 否 | Z component of extrude direction, should be -1, 0 or 1 |
| `steps` | `number` | 否 | Length of extrusion in voxels |
| `mode` | `string` | 否 | Extrusion mode, one of 'exact', 'material', 'geometry'. Default is 'exact' |

示例：

```lua
local shape = 0
function server.init()
	SetBrush("sphere", 3, 4)
	shape = FindShape("shape")
	ExtrudeShape(shape, 0, 5, 0, -1, 0, 0, 50, "exact")
end
```


### TrimShape

```lua
offset = TrimShape( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Source handle |

**返回**：`offset`: TVec（Offset vector in shape local space）

示例：

```lua
local shape = 0
function server.init()
	shape = FindShape("shape", true)
	TrimShape(shape)
end
```


### SplitShape

```lua
newShapes = SplitShape( shape, removeResidual )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Source handle |
| `removeResidual` | `boolean` | 否 | Remove residual shapes (default false) |

**返回**：`newShapes`: table（List of shape handles created）

示例：

```lua
local shape = 0
function server.init()
	shape = FindShape("shape", true)
	SplitShape(shape, true)
end
```


### MergeShape

```lua
shape = MergeShape( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Input shape |

**返回**：`shape`: number（Shape handle after merge）

示例：

```lua
local shape = 0
function server.init()
	shape = FindShape("shape", true)
	DebugPrint(shape)
	shape = MergeShape(shape)
	DebugPrint(shape)
end
```


### IsShapeDisconnected

```lua
disconnected = IsShapeDisconnected( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Input shape |

**返回**：`disconnected`: boolean（True if shape disconnected (has detached parts)）

示例：

```lua
function client.tick()
	DebugWatch("IsShapeDisconnected", IsShapeDisconnected(FindShape("shape", true)))
end
```


### IsStaticShapeDetached

```lua
disconnected = IsStaticShapeDetached( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Input shape |

**返回**：`disconnected`: boolean（True if static shape has detached parts）

示例：

```lua
function client.tick()
	DebugWatch("IsStaticShapeDetached", IsStaticShapeDetached(FindShape("shape_glass", true)))
end
```


### GetShapeClosestPoint

```lua
hit, point, normal = GetShapeClosestPoint( shape, origin )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |
| `origin` | `TVec` | 否 | World space point |

**返回**：`hit`: boolean（True if a point was found）；`point`: TVec（World space closest point）；`normal`: TVec（World space normal at closest point）

示例：

```lua
local shape = 0
function client.init()
	shape = FindShape("shape", true)
end

function client.tick()
	DebugCross(Vec(1, 0, 0))
	local hit, p, n, s = GetShapeClosestPoint(shape, Vec(1, 0, 0))
	if hit then
		DebugCross(p)
	end
end
```


### IsShapeTouching

```lua
touching = IsShapeTouching( a, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a` | `number` | 否 | Handle to first shape |
| `b` | `number` | 否 | Handle to second shape |

**返回**：`touching`: boolean（True is shapes a and b are touching each other）

示例：

```lua
local shapeA = 0
local shapeB = 0
function client.init()
	shapeA = FindShape("shape")
	shapeB = FindShape("shape2")
end

function client.tick()
	DebugPrint(IsShapeTouching(shapeA, shapeB))
end
```



---

## Location

<b>3 个函数</b>

### FindLocation

```lua
handle = FindLocation( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first location with specified tag or zero if not found）

示例：

```lua
local loc = 0
function client.init()
	loc = FindLocation("loc1")
end

function client.tick()
	DebugCross(GetLocationTransform(loc).pos)
end
```


### FindLocations

```lua
list = FindLocations( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all locations with specified tag）

示例：

```lua
local locations
function client.init()
	locations = FindLocations("loc1")

	for i=1, #locations do
		local loc = locations[i]
		DebugPrint(DebugPrint(loc))
	end
end
```


### GetLocationTransform

```lua
transform = GetLocationTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Location handle |

**返回**：`transform`: TTransform（Transform of the location）

示例：

```lua
local location = 0
function client.init()
	location = FindLocation("loc1")
	DebugPrint(VecStr(GetLocationTransform(location).pos))
end
```



---

## Joint

<b>16 个函数</b>

### FindJoint

```lua
handle = FindJoint( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first joint with specified tag or zero if not found）

示例：

```lua
function client.init()
	local joint = FindJoint("doorhinge")
	DebugPrint(joint)
end
```


### FindJoints

```lua
list = FindJoints( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all joints with specified tag）

示例：

```lua
--Search for locations tagged "doorhinge" in script scope
function client.init()
	local hinges = FindJoints("doorhinge")
	for i=1, #hinges do
		local joint = hinges[i]
		DebugPrint(joint)
	end
end
```


### IsJointBroken

```lua
broken = IsJointBroken( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`broken`: boolean（True if joint is broken）

示例：

```lua
function client.init()
	local broken = IsJointBroken(FindJoint("joint"))
	DebugPrint(broken)
end
```


### GetJointType

```lua
type = GetJointType( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`type`: string（Joint type）

示例：

```lua
function client.init()
	local joint = FindJoint("joint")
	if GetJointType(joint) == "rope" then
		DebugPrint("Joint is rope")
	end
end
```


### GetJointOtherShape

```lua
other = GetJointOtherShape( joint, shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |
| `shape` | `number` | 否 | Shape handle |

**返回**：`other`: number（Other shape handle）

示例：

```lua
function client.init()
	local joint = FindJoint("joint")
	--joint is connected to A and B

	otherShape = GetJointOtherShape(joint, FindShape("shapeA"))
	--otherShape is now B

	otherShape = GetJointOtherShape(joint, FindShape("shapeB"))
	--otherShape is now A
end
```


### GetJointShapes

```lua
shapes = GetJointShapes( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`shapes`: number（Shape handles）

示例：

```lua
local mainBody
local shapes
local joint
function server.init()
	joint = FindJoint("joint")
	mainBody = GetVehicleBody(FindVehicle("vehicle"))
	shapes = GetJointShapes(joint)
end

function server.tick()
	-- Check to see if joint chain is still connected to vehicle main body
	-- If not then disable motors

	local connected = false
	for i=1,#shapes do

		local body = GetShapeBody(shapes[i])

		if body == mainBody then
			connected = true
		end

	end

	if connected then
		SetJointMotor(joint, 0.5)
	else
		SetJointMotor(joint, 0.0)
	end
end
```


### SetJointMotor

```lua
SetJointMotor( joint, velocity, [strength] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |
| `velocity` | `number` | 否 | Desired velocity |
| `strength` | `number` | 是 | Desired strength. Default is infinite. Zero to disable. |

示例：

```lua
function server.init()
	--Set motor speed to 0.5 radians per second
	SetJointMotor(FindJoint("hinge"), 0.5)
end
```


### SetJointMotorTarget

```lua
SetJointMotorTarget( joint, target, [maxVel], [strength] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |
| `target` | `number` | 否 | Desired movement target |
| `maxVel` | `number` | 是 | Maximum velocity to reach target. Default is infinite. |
| `strength` | `number` | 是 | Desired strength. Default is infinite. Zero to disable. |

示例：

```lua
function server.init()
	--Make joint reach a 45 degree angle, going at a maximum of 3 radians per second
	SetJointMotorTarget(FindJoint("hinge"), 45, 3)
end
```


### GetJointLimits

```lua
min, max = GetJointLimits( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`min`: number（Minimum joint limit (angle or distance)）；`max`: number（Maximum joint limit (angle or distance)）

示例：

```lua
function client.init()
	local min, max = GetJointLimits(FindJoint("hinge"))
	DebugPrint(min .. "-" .. max)
end
```


### GetJointMovement

```lua
movement = GetJointMovement( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`movement`: number（Current joint position or angle）

示例：

```lua
function client.init()
	local current = GetJointMovement(FindJoint("hinge"))
	DebugPrint(current)
end
```


### GetJointedBodies

```lua
bodies = GetJointedBodies( body )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle (must be dynamic) |

**返回**：`bodies`: table（Handles to all dynamic bodies in the jointed structure. The input handle will also be included.）

示例：

```lua
local body = 0
function client.init()
	body = FindBody("body")
end

function client.tick()
	--Draw outline for all bodies in jointed structure
	local all = GetJointedBodies(body)
	for i=1,#all do
		DrawBodyOutline(all[i], 0.5)
	end
end
```


### DetachJointFromShape

```lua
DetachJointFromShape( joint, shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |
| `shape` | `number` | 否 | Shape handle |

示例：

```lua
function server.init()
	DetachJointFromShape(FindJoint("joint"), FindShape("door"))
end
```


### GetRopeNumberOfPoints

```lua
amount = GetRopeNumberOfPoints( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`amount`: number（Number of points in a rope or zero if invalid）

示例：

```lua
function client.init()
	local joint = FindJoint("joint")
	local numberPoints = GetRopeNumberOfPoints(joint)
end
```


### GetRopePointPosition

```lua
pos = GetRopePointPosition( joint, index )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |
| `index` | `number` | 否 | The point index, starting at 1 |

**返回**：`pos`: TVec（World position of the point, or nil, if invalid）

示例：

```lua
function client.init()
	local joint = FindJoint("joint")
	numberPoints = GetRopeNumberOfPoints(joint)

	for pointIndex = 1, numberPoints do
		DebugCross(GetRopePointPosition(joint, pointIndex))
	end
end
```


### GetRopeBounds

```lua
min, max = GetRopeBounds( joint )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Joint handle |

**返回**：`min`: TVec（Lower point of rope bounds in world space）；`max`: TVec（Upper point of rope bounds in world space）

示例：

```lua
function client.init()
	local joint = FindJoint("joint")
	local mi, ma = GetRopeBounds(joint)

	DebugCross(mi)
	DebugCross(ma)
end
```


### BreakRope

```lua
BreakRope( joint, point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `joint` | `number` | 否 | Rope type joint handle |
| `point` | `TVec` | 否 | Point of break as world space vector |

示例：

```lua
function doPlayerAction(playerId)
	local playerCameraTransform = GetPlayerCameraTransform(playerId)
	local dir = TransformToParentVec(playerCameraTransform, Vec(0, 0, -1))

	local hit, dist, joint = QueryRaycastRope(playerCameraTransform.pos, dir, 5)
	if hit then
		local breakPoint = VecAdd(playerCameraTransform.pos, VecScale(dir, dist))
		BreakRope(joint, breakPoint)
	end
end
```



---

## Animation

<b>33 个函数</b>

### SetAnimatorPositionIK

```lua
SetAnimatorPositionIK( handle, begname, endname, target, [weight], [history], [flag] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `begname` | `string` | 否 | Name of the start-bone of the chain |
| `endname` | `string` | 否 | Name of the end-bone of the chain |
| `target` | `TVec` | 否 | World target position that the 'endname' bone should reach |
| `weight` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |
| `history` | `number` | 是 | How much of the previous frames result [0,1] that should be used when start the IK search, default is 0.0 |
| `flag` | `boolean` | 是 | TRUE if constraints should be used, default is TRUE |

示例：

```lua
SetAnimatorPositionIK(animator, "shoulder_l", "hand_l", Vec(10, 0, 0), 1.0, 0.9, true)
```


### SetAnimatorTransformIK

```lua
SetAnimatorTransformIK( handle, begname, endname, transform, [weight], [history], [locktarget], [useconstraints] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `begname` | `string` | 否 | Name of the start-bone of the chain |
| `endname` | `string` | 否 | Name of the end-bone of the chain |
| `transform` | `TTransform` | 否 | World target transform that the 'endname' bone should reach |
| `weight` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |
| `history` | `number` | 是 | How much of the previous frames result [0,1] that should be used when start the IK search, default is 0.0 |
| `locktarget` | `boolean` | 是 | TRUE if the end-bone should be fixed to the target-transform, FALSE if IK solution is used |
| `useconstraints` | `boolean` | 是 | TRUE if constraints should be used, default is TRUE |

示例：

```lua
SetAnimatorTransformIK(animator, "shoulder_l", "hand_l", Transform(10, 0, 0), 1.0, 0.9, false, true)
```


### GetBoneChainLength

```lua
length = GetBoneChainLength( handle, begname, endname )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `begname` | `string` | 否 | Name of the start-bone of the chain |
| `endname` | `string` | 否 | Name of the end-bone of the chain |

**返回**：`length`: number（Length of the bone chain between 'start-bone' and 'end-bone'）

示例：

```lua
local length = GetBoneChainLength(animator, "shoulder_l", "hand_l")
```


### FindAnimator

```lua
handle = FindAnimator( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first animator with specified tag or zero if not found）

示例：

```lua
--Search for the first animator in script scope
local animator = FindAnimator()

--Search for an animator tagged "anim" in script scope
local animator = FindAnimator("anim")

--Search for an animator tagged "anim2" in entire scene
local anim2 = FindAnimator("anim2", true)
```


### FindAnimators

```lua
list = FindAnimators( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all animators with specified tag）

示例：

```lua
--Search for animators tagged "target" in script scope
local targets = FindAnimators("target")
for i=1, #targets do
	local target = targets[i]
	...
end
```


### GetAnimatorTransform

```lua
transform = GetAnimatorTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |

**返回**：`transform`: TTransform（World space transform of the animator）

示例：

```lua
local pos = GetAnimatorTransform(animator).pos
```


### GetAnimatorAdjustTransformIK

```lua
transform = GetAnimatorAdjustTransformIK( handle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Name of the location node |

**返回**：`transform`: TTransform（World space transform of the animator）

示例：

```lua
--This will adjust the target transform so that the grip defined by a location node in editor called "ik_hand_l" will reach the target
local target = Transform(Vec(10, 0, 0), QuatEuler(0, 90, 0))
local adj = GetAnimatorAdjustTransformIK(animator, "ik_hand_l")
if adj ~= nil then
    target = TransformToParentTransform(target, adj)
end
SetAnimatorTransformIK(animator, "shoulder_l", "hand_l", target, 1.0, 0.9)
```


### SetAnimatorTransform

```lua
SetAnimatorTransform( handle, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `transform` | `TTransform` | 否 | Desired transform |

示例：

```lua
local t = Transform(Vec(10, 0, 0), QuatEuler(0, 90, 0))
SetAnimatorTransform(animator, t)
```


### MakeRagdoll

```lua
MakeRagdoll( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |

示例：

```lua
MakeRagdoll(animator)
```


### UnRagdoll

```lua
UnRagdoll( handle, [time] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `time` | `number` | 是 | Transition time |

示例：

```lua
--Take control of bodies and do a blend during one sec between the animation state and last physics state
UnRagdoll(animator, 1.0)
```


### PlayAnimation

```lua
handle = PlayAnimation( handle, name, [weight], [filter] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `weight` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |
| `filter` | `string` | 是 | Name of the bone and its subtree that will be affected |

**返回**：`handle`: number（Handle to the instance that can be used with PlayAnimationInstance, zero if clip reached its end）

示例：

```lua
--This will play a single animation "Shooting" with a 80% influence but only on the skeleton starting at bone "Spine"
PlayAnimation(animator, "Shooting", 0.8, "Spine")
```


### PlayAnimationLoop

```lua
PlayAnimationLoop( handle, name, [weight], [filter] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `weight` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |
| `filter` | `string` | 是 | Name of the bone and its subtree that will be affected |

示例：

```lua
--This will play an animation loop "Walking" with a 100% influence on the whole skeleton
PlayAnimationLoop(animator, "Walking")
```


### PlayAnimationInstance

```lua
handle = PlayAnimationInstance( handle, instance, [weight], [speed] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `instance` | `number` | 否 | Instance handle |
| `weight` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |
| `speed` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |

**返回**：`handle`: number（Handle to the instance that can be used with PlayAnimationInstance, zero if clip reached its end）

示例：

```lua
--This will control the weight and speed of the animation thas was initiated by PlayAnimation
PlayAnimationInstance(animator, handle, 0.8, 1.0)
```


### StopAnimationInstance

```lua
StopAnimationInstance( handle, instance )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `instance` | `number` | 否 | Instance handle |


### PlayAnimationFrame

```lua
PlayAnimationFrame( handle, name, time, [weight], [filter] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `time` | `number` | 否 | Time in the animation |
| `weight` | `number` | 是 | Weight [0,1] of this animation, default is 1.0 |
| `filter` | `string` | 是 | Name of the bone and its subtree that will be affected |

示例：

```lua
--This will play an animation "Walking" at a specific time of 1.5s with a 80% influence on the whole skeleton
PlayAnimationFrame(animator, "Walking", 1.5, 0.8)
```


### BeginAnimationGroup

```lua
BeginAnimationGroup( handle, [weight], [filter] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `weight` | `number` | 是 | Weight [0,1] of this group, default is 1.0 |
| `filter` | `string` | 是 | Name of the bone and its subtree that will be affected |

示例：

```lua
--This will blend an entire group with 50% influence
BeginAnimationGroup(animator, 0.5)
	PlayAnimationLoop(...)
	PlayAnimationLoop(...)
EndAnimationGroup(animator)

--You can also create a tree of groups, blending is performed in a depth-first order
BeginAnimationGroup(animator, 0.5)
	PlayAnimationLoop(animator, "anim_a", 1.0)
	PlayAnimationLoop(animator, "anim_b", 0.2)
	BeginAnimationGroup(animator, 0.75)
		PlayAnimationLoop(animator, "anim_c", 1.0)
		PlayAnimationLoop(animator, "anim_d", 0.25)
	EndAnimationGroup(animator)
EndAnimationGroup(animator)
```


### EndAnimationGroup

```lua
EndAnimationGroup( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |


### PlayAnimationInstances

```lua
PlayAnimationInstances( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |

示例：

```lua
--First we play a single jump animation affecting the whole skeleton
--Then we play an aiming animation on the upper-body, filter="Spine1", keeping the lower-body unaffected
--Then we force the single-animations to be processed, this will force the "jump" to be processed.
--Then we overwrite just the spine-bone with a mouse controlled rotation("rot")
--Result will be a jump animation with the upperbody playing an aiming animation but the pitch of the spine controlled by the mouse("rot")

if InputPressed("jump") then
	PlayAnimation(animator, "Jump")
end
PlayAnimationLoop(animator, "Pistol Idle", aimWeight, "Spine1")
PlayAnimationInstances(animator)
SetBoneRotation(animator, "Spine1", rot, 1)
```


### GetAnimationClipNames

```lua
list = GetAnimationClipNames( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |

**返回**：`list`: table（Indexed table with animation names）

示例：

```lua
local list = GetAnimationClipNames(animator)
for i=1, #list do
	local name = list[i]
	..
end
```


### GetAnimationClipDuration

```lua
time = GetAnimationClipDuration( handle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |

**返回**：`time`: number（Total duration of the animation）


### SetAnimationClipFade

```lua
SetAnimationClipFade( handle, name, fadein, fadeout )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `fadein` | `number` | 否 | Fadein time of the animation |
| `fadeout` | `number` | 否 | Fadeout time of the animation |

示例：

```lua
SetAnimationClipFade(animator, "fire", 0.5, 0.5)
```


### SetAnimationClipSpeed

```lua
SetAnimationClipSpeed( handle, name, speed )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `speed` | `number` | 否 | Sets the speed factor of the animation |

示例：

```lua
--This will make the clip run 2x as normal speed
SetAnimationClipSpeed(animator, "walking", 2)
```


### TrimAnimationClip

```lua
TrimAnimationClip( handle, name, begoffset, [endoffset] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `begoffset` | `number` | 否 | Time offset from the beginning of the animation |
| `endoffset` | `number` | 是 | Time offset, positive value means from the beginning and negative value means from the end, zero(default) means at end |

示例：

```lua
--This will "remove" 1s from the beginning and 2s from the end.
TrimAnimationClip(animator, "walking", 1, -2)
```


### GetAnimationClipLoopPosition

```lua
time = GetAnimationClipLoopPosition( handle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |

**返回**：`time`: number（Time of the current playposition in the animation）


### GetAnimationInstancePosition

```lua
time = GetAnimationInstancePosition( handle, instance )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `instance` | `number` | 否 | Instance handle |

**返回**：`time`: number（Time of the current playposition in the animation）


### SetAnimationClipLoopPosition

```lua
SetAnimationClipLoopPosition( handle, name, time )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Animation name |
| `time` | `number` | 否 | Time in the animation |

示例：

```lua
--This will set the current playposition to one second
SetAnimationClipLoopPosition(animator, "walking", 1)
```


### SetBoneRotation

```lua
SetBoneRotation( handle, name, quat, [weight] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Bone name |
| `quat` | `TQuat` | 否 | Orientation of the bone |
| `weight` | `number` | 是 | Weight [0,1] default is 1.0 |

示例：

```lua
--This will set the existing rotation by QuatEuler(...)
SetBoneRotation(animator, "spine", QuatEuler(0, 180, 0), 1.0)
```


### SetBoneLookAt

```lua
SetBoneLookAt( handle, name, point, [weight] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Bone name |
| `point` | `table` | 否 | World space point as vector |
| `weight` | `number` | 是 | Weight [0,1] default is 1.0 |

示例：

```lua
--This will set the existing local-rotation to point to world space point
SetBoneLookAt(animator, "upper_arm_l", Vec(10, 20, 30), 1.0)
```


### RotateBone

```lua
RotateBone( handle, name, quat, [weight] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Bone name |
| `quat` | `TQuat` | 否 | Additive orientation |
| `weight` | `number` | 是 | Weight [0,1] default is 1.0 |

示例：

```lua
--This will offset the existing rotation by QuatEuler(...)
RotateBone(animator, "spine", QuatEuler(0, 5, 0), 1.0)
```


### GetBoneNames

```lua
list = GetBoneNames( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |

**返回**：`list`: table（Indexed table with bone-names）

示例：

```lua
local list = GetBoneNames(animator)
for i=1, #list do
	local name = list[i]
	..
end
```


### GetBoneBody

```lua
handle = GetBoneBody( handle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Bone name |

**返回**：`handle`: number（Handle to the bone's body, or zero if no bone is present.）

示例：

```lua
local body = GetBoneBody(animator, "head")
end
```


### GetBoneWorldTransform

```lua
transform = GetBoneWorldTransform( handle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Bone name |

**返回**：`transform`: TTransform（World space transform of the bone）

示例：

```lua
local animator = GetPlayerAnimator()
    local bones = GetBoneNames(animator)
    for i=1, #bones do
        local bone = bones[i]
        local t = GetBoneWorldTransform(animator,bone)
        DebugCross(t.pos)
    end
```


### GetBoneBindPoseTransform

```lua
transform = GetBoneBindPoseTransform( handle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |
| `name` | `string` | 否 | Bone name |

**返回**：`transform`: TTransform（Local space transform of the bone in bindpose）

示例：

```lua
local lt = getBindPoseTransform(animator, "lefthand")
```



---

## Light

<b>11 个函数</b>

### FindLight

```lua
handle = FindLight( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first light with specified tag or zero if not found）

示例：

```lua
function client.init()
	local light = FindLight("main")
	DebugPrint(light)
end
```


### FindLights

```lua
list = FindLights( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all lights with specified tag）

示例：

```lua
function client.init()
	--Search for lights tagged "main" in script scope
	local lights = FindLights("main")
	for i=1, #lights do
		local light = lights[i]
		DebugPrint(light)
	end
end
```


### SetLightEnabled

```lua
SetLightEnabled( handle, enabled )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |
| `enabled` | `boolean` | 否 | Set to true if light should be enabled |

示例：

```lua
function server.init()
	SetLightEnabled(FindLight("main"), false)
end
```


### SetLightColor

```lua
SetLightColor( handle, r, g, b )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |
| `r` | `number` | 否 | Red value |
| `g` | `number` | 否 | Green value |
| `b` | `number` | 否 | Blue value |

示例：

```lua
function server.init()
	--Set light color to yellow
	SetLightColor(FindLight("main"), 1, 1, 0)
end
```


### SetLightIntensity

```lua
SetLightIntensity( handle, intensity )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |
| `intensity` | `number` | 否 | Desired intensity of the light |

示例：

```lua
function server.init()
	--Pulsate light
	SetLightIntensity(FindLight("main"), math.sin(GetTime())*0.5 + 1.0)
end
```


### GetLightTransform

```lua
transform = GetLightTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |

**返回**：`transform`: TTransform（World space light transform）

示例：

```lua
local light = 0
function client.init()
	light = FindLight("main")
	local t = GetLightTransform(light)
	DebugPrint(VecStr(t.pos))
end
```


### GetLightShape

```lua
handle = GetLightShape( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |

**返回**：`handle`: number（Shape handle or zero if not attached to shape）

示例：

```lua
local light = 0
function client.init()
	light = FindLight("main")
	local shape = GetLightShape(light)
	DebugPrint(shape)
end
```


### IsLightActive

```lua
active = IsLightActive( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |

**返回**：`active`: boolean（True if light is currently emitting light）

示例：

```lua
local light = 0
function client.init()
	light = FindLight("main")
	if IsLightActive(light) then
		DebugPrint("Light is active")
	end
end
```


### IsPointAffectedByLight

```lua
affected = IsPointAffectedByLight( handle, point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Light handle |
| `point` | `TVec` | 否 | World space point as vector |

**返回**：`affected`: boolean（Return true if point is in light cone and range）

示例：

```lua
local light = 0
function client.init()
	light = FindLight("main")
	local point = Vec(0, 10, 0)
	local affected = IsPointAffectedByLight(light, point)
	DebugPrint(affected)
end
```


### GetFlashlight

```lua
handle = GetFlashlight( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle of the player's flashlight）

示例：

```lua
function setFlashlightColor(playerId)
	local flashlight = GetFlashlight(playerId)
	SetProperty(flashlight, "color", Vec(0.5, 0, 1))
end
```


### SetFlashlight

```lua
SetFlashlight( handle, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Handle of the light |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
local oldLight = 0
function server.tick()
	... -- some code
	-- in order not to lose the original flashlight, it is better to save it's handle
	oldLight = GetFlashlight(playerId)
	SetFlashlight(FindEntity("mylight", true), playerId)
end
```



---

## Trigger

<b>13 个函数</b>

### FindTrigger

```lua
handle = FindTrigger( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first trigger with specified tag or zero if not found）

示例：

```lua
function server.init()
	local goal = FindTrigger("goal")
end
```


### FindTriggers

```lua
list = FindTriggers( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all triggers with specified tag）

示例：

```lua
function client.init()
	--Find triggers tagged "toxic" in script scope
	local triggers = FindTriggers("toxic")
	for i=1, #triggers do
		local trigger = triggers[i]
		DebugPrint(trigger)
	end
end
```


### GetTriggerTransform

```lua
transform = GetTriggerTransform( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Trigger handle |

**返回**：`transform`: TTransform（Current trigger transform in world space）

示例：

```lua
function client.init()
	local trigger = FindTrigger("toxic")
	local t = GetTriggerTransform(trigger)
	DebugPrint(t.pos)
end
```


### SetTriggerTransform

```lua
SetTriggerTransform( handle, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Trigger handle |
| `transform` | `TTransform` | 否 | Desired trigger transform in world space |

示例：

```lua
function server.init()
	local trigger = FindTrigger("toxic")
	local t = Transform(Vec(0, 1, 0), QuatEuler(0, 90, 0))
	SetTriggerTransform(trigger, t)
end
```


### GetTriggerBounds

```lua
min, max = GetTriggerBounds( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Trigger handle |

**返回**：`min`: TVec（Lower point of trigger bounds in world space）；`max`: TVec（Upper point of trigger bounds in world space）

示例：

```lua
function client.init()
	local trigger = FindTrigger("toxic")
	local mi, ma = GetTriggerBounds(trigger)

	local list = QueryAabbShapes(mi, ma)
	for i = 1, #list do
		DebugPrint(list[i])
	end
end
```


### IsBodyInTrigger

```lua
inside = IsBodyInTrigger( trigger, body )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `trigger` | `number` | 否 | Trigger handle |
| `body` | `number` | 否 | Body handle |

**返回**：`inside`: boolean（True if body is in trigger volume）

示例：

```lua
local trigger = 0
local body = 0
function client.init()
	trigger = FindTrigger("toxic")
	body = FindBody("body")
end

function client.tick()
	if IsBodyInTrigger(trigger, body) then
		DebugPrint("In trigger!")
	end
end
```


### IsVehicleInTrigger

```lua
inside = IsVehicleInTrigger( trigger, vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `trigger` | `number` | 否 | Trigger handle |
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`inside`: boolean（True if vehicle is in trigger volume）

示例：

```lua
local trigger = 0
local vehicle = 0
function client.init()
	trigger = FindTrigger("toxic")
	vehicle = FindVehicle("vehicle")
end

function client.tick()
	if IsVehicleInTrigger(trigger, vehicle) then
		DebugPrint("In trigger!")
	end
end
```


### IsShapeInTrigger

```lua
inside = IsShapeInTrigger( trigger, shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `trigger` | `number` | 否 | Trigger handle |
| `shape` | `number` | 否 | Shape handle |

**返回**：`inside`: boolean（True if shape is in trigger volume）

示例：

```lua
local trigger = 0
local shape = 0
function client.init()
	trigger = FindTrigger("toxic")
	shape = FindShape("shape")
end

function client.tick()
	if IsShapeInTrigger(trigger, shape) then
		DebugPrint("In trigger!")
	end
end
```


### IsPointInTrigger

```lua
inside = IsPointInTrigger( trigger, point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `trigger` | `number` | 否 | Trigger handle |
| `point` | `TVec` | 否 | Word space point as vector |

**返回**：`inside`: boolean（True if point is in trigger volume）

示例：

```lua
local trigger = 0
local point = {}
function client.init()
	trigger = FindTrigger("toxic", true)
	point = Vec(0, 0, 0)
end

function client.tick()
	if IsPointInTrigger(trigger, point) then
		DebugPrint("In trigger!")
	end
end
```


### IsPointInBoundaries

```lua
value, dist = IsPointInBoundaries( point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `point` | `TVec` | 否 | Point |

**返回**：`value`: boolean（True if point is inside scene boundaries or if there are no boundaries）；`dist`: number（Distance to the scene boundaries. Zero if there are no boundaries or if point is outside.）

示例：

```lua
function client.tick()
	local p = Vec(1.5, 3, 2.5)
	DebugWatch("In boundaries", IsPointInBoundaries(p))
end
```


### IsTriggerEmpty

```lua
empty, maxpoint = IsTriggerEmpty( handle, [demolision] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Trigger handle |
| `demolision` | `boolean` | 是 | If true, small debris and vehicles are ignored |

**返回**：`empty`: boolean（True if trigger is empty）；`maxpoint`: TVec（World space point of highest point (largest Y coordinate) if not empty）

示例：

```lua
local trigger = 0
function client.init()
	trigger = FindTrigger("toxic")
end

function client.tick()
	local empty, highPoint = IsTriggerEmpty(trigger)
	if not empty then
		--highPoint[2] is the tallest point in trigger
		DebugPrint("Is not empty")
	end
end
```


### GetTriggerDistance

```lua
distance = GetTriggerDistance( trigger, point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `trigger` | `number` | 否 | Trigger handle |
| `point` | `TVec` | 否 | Word space point as vector |

**返回**：`distance`: number（Positive if point is outside, negative if inside）

示例：

```lua
local trigger = 0
function client.init()
	trigger = FindTrigger("toxic")
	local p = Vec(0, 10, 0)
	local dist = GetTriggerDistance(trigger, p)
	DebugPrint(dist)
end
```


### GetTriggerClosestPoint

```lua
closest = GetTriggerClosestPoint( trigger, point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `trigger` | `number` | 否 | Trigger handle |
| `point` | `TVec` | 否 | Word space point as vector |

**返回**：`closest`: TVec（Closest point in trigger as vector）

示例：

```lua
local trigger = 0
function client.init()
	trigger = FindTrigger("toxic")
	local p = Vec(0, 10, 0)
	local closest = GetTriggerClosestPoint(trigger, p)
	DebugPrint(closest)
end
```



---

## Screen

<b>6 个函数</b>

### FindScreen

```lua
handle = FindScreen( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first screen with specified tag or zero if not found）

示例：

```lua
function client.init()
	local screen = FindScreen("tv")
	DebugPrint(screen)
end
```


### FindScreens

```lua
list = FindScreens( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all screens with specified tag）

示例：

```lua
function client.init()
	--Find screens tagged "tv" in script scope
	local screens = FindScreens("tv")
	for i=1, #screens do
		local screen = screens[i]
		DebugPrint(screen)
	end
end
```


### SetScreenEnabled

```lua
SetScreenEnabled( screen, enabled )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `screen` | `number` | 否 | Screen handle |
| `enabled` | `boolean` | 否 | True if screen should be enabled |

示例：

```lua
function server.init()
	SetScreenEnabled(FindScreen("tv"), true)
end
```


### IsScreenEnabled

```lua
enabled = IsScreenEnabled( screen )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `screen` | `number` | 否 | Screen handle |

**返回**：`enabled`: boolean（True if screen is enabled）

示例：

```lua
function client.init()
	local b = IsScreenEnabled(FindScreen("tv"))
	DebugPrint(b)
end
```


### GetScreenShape

```lua
shape = GetScreenShape( screen )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `screen` | `number` | 否 | Screen handle |

**返回**：`shape`: number（Shape handle or zero if none）

示例：

```lua
local screen = 0
function client.init()
	screen = FindScreen("tv")
	local shape = GetScreenShape(screen)
	DebugPrint(shape)
end
```


### GetScreenPlayer

```lua
GetScreenPlayer( screen, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `screen` | `number` | 否 | Screen handle |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
local player = GetScreenPlayer(screen)
```



---

## Vehicle

<b>18 个函数</b>

### FindVehicle

```lua
handle = FindVehicle( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first vehicle with specified tag or zero if not found）

示例：

```lua
function client.init()
	local vehicle = FindVehicle("mycar")
end
```


### FindVehicles

```lua
list = FindVehicles( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`list`: table（Indexed table with handles to all vehicles with specified tag）

示例：

```lua
function client.init()
	--Find all vehicles in level tagged "boat"
	local boats = FindVehicles("boat")
	for i=1, #boats do
		local boat = boats[i]
		DebugPrint(boat)
	end
end
```


### GetVehicleTransform

```lua
transform = GetVehicleTransform( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`transform`: TTransform（Transform of vehicle）

示例：

```lua
function client.init()
	local vehicle = FindVehicle("vehicle")
	local t = GetVehicleTransform(vehicle)
end
```


### GetVehicleExhaustTransforms

```lua
transforms = GetVehicleExhaustTransforms( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`transforms`: table（Transforms of vehicle exhausts）

示例：

```lua
function client.tick()
	local vehicle = FindVehicle("car", true)
	local t = GetVehicleExhaustTransforms(vehicle)
	for i = 1, #t do
		DebugWatch(tostring(i), t[i])
	end
end
```


### GetVehicleVitalTransforms

```lua
transforms = GetVehicleVitalTransforms( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`transforms`: table（Transforms of vehicle vitals）

示例：

```lua
function client.tick()
	local vehicle = FindVehicle("car", true)
	local t = GetVehicleVitalTransforms(vehicle)
	for i = 1, #t do
		DebugWatch(tostring(i), t[i])
	end
end
```


### GetVehicleBodies

```lua
transforms = GetVehicleBodies( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`transforms`: table（Vehicle bodies handles）

示例：

```lua
function client.tick()
	local vehicle = FindVehicle("car", true)
	local t = GetVehicleBodies(vehicle)
	for i = 1, #t do
		DebugWatch(tostring(i), t[i])
	end
end
```


### GetVehicleBody

```lua
body = GetVehicleBody( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`body`: number（Main body of vehicle）

示例：

```lua
function client.init()
	local vehicle = FindVehicle("vehicle")
	local body = GetVehicleBody(vehicle)
	if IsBodyBroken(body) then
		DebugPrint("Is broken")
	end
end
```


### GetVehicleHealth

```lua
health = GetVehicleHealth( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`health`: number（Vehicle health (zero to one)）

示例：

```lua
function client.init()
	local vehicle = FindVehicle("vehicle")
	local health = GetVehicleHealth(vehicle)
	DebugPrint(health)
end
```


### GetVehicleParams

```lua
params = GetVehicleParams( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`params`: table（Vehicle params）

示例：

```lua
function client.tick()
	local params = GetVehicleParams(FindVehicle("car", true))
	for key, value in pairs(params) do
		DebugWatch(key, value)
	end
end
```


### SetVehicleParam

```lua
SetVehicleParam( handle, param, value )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Vehicle handler |
| `param` | `string` | 否 | Param name |
| `value` | `number` | 否 | Param value |

示例：

```lua
function server.init()
	SetVehicleParam(FindVehicle("car", true), "topspeed", 200)
end
```


### GetVehicleDriverPos

```lua
pos = GetVehicleDriverPos( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`pos`: TVec（Driver position as vector in vehicle space）

示例：

```lua
function client.init()
	local vehicle = FindVehicle("vehicle")
	local driverPos = GetVehicleDriverPos(vehicle)
	local t = GetVehicleTransform(vehicle)
	local worldPos = TransformToParentPoint(t, driverPos)
	DebugPrint(worldPos)
end
```


### GetVehicleAvailableSeatPos

```lua
pos = GetVehicleAvailableSeatPos( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`pos`: TVec（World space position of the next available seat. {0, 0, 0} if none is available.）

示例：

```lua
function client.tick()
	local vehicle = FindVehicle("vehicle")
	local pos = GetVehicleAvailableSeatPos(vehicle)
	DebugPrint(pos)
end
```


### GetVehicleSteering

```lua
steering = GetVehicleSteering( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`steering`: number（Driver steering value -1 to 1）

示例：

```lua
local steering = GetVehicleSteering(vehicle)
```


### GetVehicleDrive

```lua
drive = GetVehicleDrive( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`drive`: number（Driver drive value -1 to 1）

示例：

```lua
local drive = GetVehicleDrive(vehicle)
```


### DriveVehicle

```lua
DriveVehicle( vehicle, drive, steering, handbrake )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |
| `drive` | `number` | 否 | Reverse/forward control -1 to 1 |
| `steering` | `number` | 否 | Left/right control -1 to 1 |
| `handbrake` | `boolean` | 否 | Handbrake control |

示例：

```lua
function server.tick()
	--Drive mycar forwards
	local v = FindVehicle("mycar")
	DriveVehicle(v, 1, 0, false)
end
```


### GetVehicleLocationWorldTransform

```lua
transform = GetVehicleLocationWorldTransform( vehicle, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |
| `name` | `string` | 否 | Name of location |

**返回**：`transform`: TTransform（World transform）

示例：

```lua
local t = GetVehicleLocationWorldTransform(vehicle, "player_steeringwheel")
```


### GetVehiclePassengerCount

```lua
count, seats, hasDriver = GetVehiclePassengerCount( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

**返回**：`count`: number（Number of passengers）；`seats`: number（Number of seats）；`hasDriver`: bool（If vehicle has a driver）

示例：

```lua
local passengers, seats, hasDriver = GetVehiclePassengerCount(vehicle)
```


### SetVehicleHealth

```lua
SetVehicleHealth( vehicle, health )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |
| `health` | `number` | 否 | Set vehicle health (between zero and one) |

示例：

```lua
function server.tick()
	if InputPressed("usetool", playerId) then
		SetVehicleHealth(FindVehicle("car", true), 0.0)
	end
end
```



---

## Rig

<b>7 个函数</b>

### FindRig

```lua
handle = FindRig( [tag], [global] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 是 | Tag name |
| `global` | `boolean` | 是 | Search in entire scene |

**返回**：`handle`: number（Handle to first rig with specified tag or zero if not found）

示例：

```lua
function client.init()
	local rig = FindRig("myrig")
end
```


### GetRigWorldTransform

```lua
transform = GetRigWorldTransform( rig )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |

**返回**：`transform`: TTransform（World transform, nil if rig is missing）

示例：

```lua
local t = GetRigWorldTransform(rig)
```


### SetRigWorldTransform

```lua
SetRigWorldTransform( rig, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |
| `transform` | `TTransform` | 否 | New world transform |

示例：

```lua
SetRigWorldTransform(rig, Transform(...))
```


### GetRigLocationWorldTransform

```lua
transform = GetRigLocationWorldTransform( rig, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |
| `name` | `string` | 否 | Name of location |

**返回**：`transform`: TTransform（World transform, nil if rig is missing or location is missing）

示例：

```lua
local foot_t = GetRigLocationWorldTransform(rigid, "ik_foot_l")
```


### SetRigLocationWorldTransform

```lua
SetRigLocationWorldTransform( rig, name, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |
| `name` | `string` | 否 | Name of location |
| `transform` | `TTransform` | 否 | New world transform |

示例：

```lua
SetRigLocationWorldTransform(rig, "some_location_name", Transform(...))
```


### GetRigLocationLocalTransform

```lua
transform = GetRigLocationLocalTransform( rig, name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |
| `name` | `string` | 否 | Name of location |

**返回**：`transform`: TTransform（Local transform, nil if rig is missing or location is missing）

示例：

```lua
local t = GetRigLocationLocalTransform(rigid, "some_location_name")
```


### SetRigLocationLocalTransform

```lua
SetRigLocationLocalTransform( rig, name, transform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |
| `name` | `string` | 否 | Name of location |
| `transform` | `TTransform` | 否 | New world transform |

示例：

```lua
local someBody = FindBody("bodyname")
    SetPlayerRigTransform(someBody, GetBodyTransform(someBody))
```



---

## Player

<b>105 个函数</b>

### GetAllPlayers

```lua
name = GetAllPlayers(  )
```

**返回**：`name`: list（List of all player Ids）

示例：

```lua
local playerIds = GetAllPlayers()
```


### GetMaxPlayers

```lua
count = GetMaxPlayers(  )
```

**返回**：`count`: interger（Number of max players for the session. Returns 1 for non-multiplayer.）

示例：

```lua
local maxPlayerCount = GetMaxPlayers()
-- create an UI big enough to fit a the max player count
createGameModeUI(maxPlayerCount)
```


### GetPlayerCount

```lua
count = GetPlayerCount(  )
```

**返回**：`count`: number（Number of players）

示例：

```lua
local playerCount = GetPlayerCount()
```


### GetAddedPlayers

```lua
playerIds = GetAddedPlayers(  )
```

**返回**：`playerIds`: table（List of added player Ids）

示例：

```lua
local playerIds = GetAddedPlayers()
```


### GetRemovedPlayers

```lua
playerIds = GetRemovedPlayers(  )
```

**返回**：`playerIds`: table（List of removed player Ids）

示例：

```lua
local playerIds = GetRemovedPlayers()
```


### GetPlayerName

```lua
name = GetPlayerName( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`name`: string（Player name）

示例：

```lua
local name = GetPlayerName(0)
```


### GetLocalPlayer

```lua
GetLocalPlayer = GetLocalPlayer(  )
```

**返回**：`GetLocalPlayer`: number（Local player ID.）

示例：

```lua
local p = GetLocalPlayer()
```


### IsPlayerLocal

```lua
IsPlayerLocal = IsPlayerLocal( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`IsPlayerLocal`: boolean（Whether a player is the local player.）

示例：

```lua
if IsPlayerLocal(attacker) then
	score = score + 1
end
```


### SetPlayerCharacter

```lua
SetPlayerCharacter( character, [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `character` | `string` | 否 | Character id |
| `playerId` | `number` | 是 | Player ID |

示例：

```lua
SetPlayerCharacter("spacesuit", 2)
```


### GetPlayerCharacter

```lua
character = GetPlayerCharacter( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`character`: string（Character id）

示例：

```lua
local character = GetPlayerCharacter(0)
```


### IsPlayerHost

```lua
IsPlayerHost = IsPlayerHost( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`IsPlayerHost`: boolean（Whether a player is the host）

示例：

```lua
local isHost = IsPlayerHost()
```


### IsPlayerValid

```lua
IsPlayerValid = IsPlayerValid( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`IsPlayerValid`: boolean（Whether a player is valid (existing player)）

示例：

```lua
local isValid = IsPlayerValid(flagCarrier)
if not isValid then
	dropFlag()
end
```


### GetPlayerPos

```lua
position = GetPlayerPos( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`position`: TVec（Player center position）

示例：

```lua
function client.init()
	local p = GetPlayerPos()
	DebugPrint(p)

	--This is equivalent to
	p = VecAdd(GetPlayerTransform().pos, Vec(0,1,0))
	DebugPrint(p)
end
```


### GetPlayerAimInfo

```lua
hit, startpos, endpos, direction, hitnormal, hitdist, hitentity, hitmaterial = GetPlayerAimInfo( position, [maxdist], [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `position` | `TVec` | 否 | Start position of the search |
| `maxdist` | `number` | 是 | Max search distance |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`hit`: boolean（TRUE if hit, FALSE otherwise.）；`startpos`: TVec（Player can modify start position when close to walls etc）；`endpos`: TVec（Hit position）；`direction`: TVec（Direction from start position to end position）；`hitnormal`: TVec（Normal of the hitpoint）；`hitdist`: number（Distance of the hit）；`hitentity`: handle（Handle of the entitiy being hit）；`hitmaterial`: handle（Name of the material being hit）

示例：

```lua
local muzzle = GetToolLocationWorldTransform("muzzle")
local _, pos, _, dir = GetPlayerAimInfo(muzzle.pos)
Shoot(pos, dir)
```


### GetPlayerPitch

```lua
pitch = GetPlayerPitch( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`pitch`: number（Current player pitch angle）

示例：

```lua
function client.init()
	local pitchRotation = Quat(Vec(1,0,0), GetPlayerPitch())
end
```


### GetPlayerYaw

```lua
yaw = GetPlayerYaw( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`yaw`: number（Current player yaw angle）

示例：

```lua
function client.init()
	local compassBearing = GetPlayerYaw()
end
```


### SetPlayerPitch

```lua
SetPlayerPitch( pitch, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `pitch` | `number` | 否 | Pitch. |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	-- look straight ahead
	SetPlayerPitch(0.0, playerId)
end
```


### GetPlayerCrouch

```lua
recoil = GetPlayerCrouch( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`recoil`: number（Current player crouch）

示例：

```lua
function client.tick()
    local crouch = GetPlayerCrouch()
    if crouch > 0.0 then
        ...
    end
end
```


### GetPlayerTransform

```lua
transform = GetPlayerTransform( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`transform`: TTransform（Current player transform）

示例：

```lua
function client.init()
	local t = GetPlayerTransform()
	DebugPrint(TransformStr(t))
end
```


### GetPlayerTransformWithPitch

```lua
transform = GetPlayerTransformWithPitch( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`transform`: table（Current player transform, including pitch (look up/down)）

示例：

```lua
local t = GetPlayerTransform()
```


### SetPlayerTransform

```lua
SetPlayerTransform( transform, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Desired player transform |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	if InputPressed("jump", playerId) then
		local t = Transform(Vec(50, 0, 0), QuatEuler(0, 90, 0))
		SetPlayerTransform(t, playerId)
	end
end
```


### SetPlayerTransformWithPitch

```lua
SetPlayerTransformWithPitch( transform, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `table` | 否 | Desired player transform |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
local t = Transform(Vec(10, 0, 0), QuatEuler(30, 90, 0))
SetPlayerTransform(t, playerId)
```


### SetPlayerGroundVelocity

```lua
SetPlayerGroundVelocity( vel, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vel` | `TVec` | 否 | Desired ground velocity |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	SetPlayerGroundVelocity(Vec(2,0,0), playerId)
end
```


### GetPlayerEyeTransform

```lua
transform = GetPlayerEyeTransform( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`transform`: TTransform（Current player eye transform）

示例：

```lua
function client.init()
	local t = GetPlayerEyeTransform()
	DebugPrint(TransformStr(t))
end
```


### GetPlayerCameraTransform

```lua
transform = GetPlayerCameraTransform( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`transform`: TTransform（Current player camera transform）

示例：

```lua
function client.init()
	local t = GetPlayerCameraTransform()
	DebugPrint(TransformStr(t))
end
```


### SetPlayerCameraOffsetTransform

```lua
SetPlayerCameraOffsetTransform( transform, [stackable], [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Desired player camera offset transform |
| `stackable` | `boolean` | 是 | True if eye offset should summ up with multiple calls per tick |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. |

示例：

```lua
function client.tick()
	local t = Transform(Vec(), QuatAxisAngle(Vec(1, 0, 0), math.sin(GetTime()*3.0) * 3.0))
	SetPlayerCameraOffsetTransform(t, playerId)
end
```


### SetPlayerSpawnTransform

```lua
SetPlayerSpawnTransform( transform, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Desired player spawn transform |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function setPlayerSpawnTransform(playerId)
	local t = Transform(Vec(10, 0, 0), QuatEuler(0, 90, 0))
	SetPlayerSpawnTransform(t, playerId)
end
```


### SetPlayerSpawnHealth

```lua
SetPlayerSpawnHealth( health, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `health` | `number` | 否 | Desired player spawn health (between zero and one) |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function playerJoined(playerId)
	SetPlayerSpawnHealth(0.5, playerId)
end
```


### SetPlayerSpawnTool

```lua
SetPlayerSpawnTool( id, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 否 | Tool unique identifier |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function playerJoined(playerId)
	SetPlayerSpawnTool("pistol", playerId)
end
```


### GetPlayerVelocity

```lua
velocity = GetPlayerVelocity( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`velocity`: TVec（Player velocity in world space as vector）

示例：

```lua
function client.tick()
	local vel = GetPlayerVelocity()
	DebugPrint(VecStr(vel))
end
```


### SetPlayerVehicle

```lua
SetPlayerVehicle( vehicle, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Handle to vehicle or zero to not drive. |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	if InputPressed("interact", playerId) then
		local car = FindVehicle("mycar")
		SetPlayerVehicle(car, playerId)
	end
end
```


### SetPlayerAnimator

```lua
SetPlayerAnimator( animator, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `animator` | `number` | 否 | Handle to animator or zero for no animator |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |


### GetPlayerAnimator

```lua
animator = GetPlayerAnimator( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`animator`: number（Handle to animator or zero for no animator）


### GetPlayerBodies

```lua
bodies = GetPlayerBodies( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`bodies`: list（Get bodies associated with a player）

示例：

```lua
local bodies = GetPlayerBodies(playerId)
```


### SetPlayerVelocity

```lua
SetPlayerVelocity( velocity, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `velocity` | `TVec` | 否 | Player velocity in world space as vector |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	if InputPressed("jump", playerId) then
		SetPlayerVelocity(Vec(0, 5, 0), playerId)
	end
end
```


### GetPlayerVehicle

```lua
handle = GetPlayerVehicle( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Current vehicle handle, or zero if not in vehicle）

示例：

```lua
function client.tick()
	local vehicle = GetPlayerVehicle()
	if vehicle ~= 0 then
		DebugPrint("Player drives the vehicle")
	end
end
```


### IsPlayerGrounded

```lua
isGrounded = IsPlayerGrounded( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`isGrounded`: boolean（Whether the player is grounded）

示例：

```lua
local isGrounded = IsPlayerGrounded()
```


### IsPlayerVehicleDriver

```lua
isDriver = IsPlayerVehicleDriver( handle, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Vehicle handle |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`isDriver`: boolean（Whether the player is driver for this vehicle）

示例：

```lua
local vehicle = FindVehicle("myvehicle")
local isDriver = IsPlayerVehicleDriver(vehicle)
```


### IsPlayerVehiclePassenger

```lua
isPassenger = IsPlayerVehiclePassenger( handle, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Vehicle handle |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`isPassenger`: boolean（Whether the player is a passenger of this vehicle）

示例：

```lua
local vehicle = FindVehicle("myvehicle")
local isPassenger = IsPlayerVehiclePassenger(vehicle)
```


### IsPlayerJumping

```lua
isGrounded = IsPlayerJumping( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`isGrounded`: boolean（Whether the player is jumping or not）

示例：

```lua
local isJumping = IsPlayerJumping()
```


### GetPlayerGroundContact

```lua
contact, shape, point, normal = GetPlayerGroundContact( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`contact`: boolean（Whether the player is grounded）；`shape`: number（Handle to shape）；`point`: Vec（Point of contact）；`normal`: Vec（Normal of contact）

示例：

```lua
function client.tick()
	hasGroundContact, shape, point, normal = GetPlayerGroundContact()

	if hasGroundContact then
		-- print ground contact data
		DebugPrint(VecStr(point).." : "..VecStr(normal))
	end
end
```


### GetPlayerGrabShape

```lua
handle = GetPlayerGrabShape( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to grabbed shape or zero if not grabbing.）

示例：

```lua
function client.tick()
	local shape = GetPlayerGrabShape()
	if shape ~= 0 then
		DebugPrint("Player is grabbing a shape")
	end
end
```


### GetPlayerGrabBody

```lua
handle = GetPlayerGrabBody( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to grabbed body or zero if not grabbing.）

示例：

```lua
function client.tick()
	local body = GetPlayerGrabBody()
	if body ~= 0 then
		DebugPrint("Player is grabbing a body")
	end
end
```


### ReleasePlayerGrab

```lua
ReleasePlayerGrab( [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	if InputPressed("jump", playerId) then
		ReleasePlayerGrab(playerId)
	end
end
```


### GetPlayerGrabPoint

```lua
pos = GetPlayerGrabPoint( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`pos`: TVec（The world space grab point.）

示例：

```lua
local body = GetPlayerGrabBody()
if body ~= 0 then
	local pos = GetPlayerGrabPoint()
end
```


### GetPlayerPickShape

```lua
handle = GetPlayerPickShape( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to picked shape or zero if nothing is picked）

示例：

```lua
function client.tick()
	local shape = GetPlayerPickShape()
	if shape ~= 0 then
		DebugPrint("Picked shape " .. shape)
	end
end
```


### GetPlayerPickBody

```lua
handle = GetPlayerPickBody( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to picked body or zero if nothing is picked）

示例：

```lua
function client.tick()
	local body = GetPlayerPickBody()
	if body ~= 0 then
		DebugWatch("Pick body ", body)
	end
end
```


### GetPlayerInteractShape

```lua
handle = GetPlayerInteractShape( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to interactable shape or zero）

示例：

```lua
function client.tick()
	local shape = GetPlayerInteractShape()
	if shape ~= 0 then
		DebugPrint("Interact shape " .. shape)
	end
end
```


### GetPlayerInteractBody

```lua
handle = GetPlayerInteractBody( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to interactable body or zero）

示例：

```lua
function client.tick()
	local body = GetPlayerInteractBody()
	if body ~= 0 then
		DebugPrint("Interact body " .. body)
	end
end
```


### SetPlayerScreen

```lua
SetPlayerScreen( handle, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Handle to screen or zero for no screen |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	if InputPressed("interact", playerId) then
		if GetPlayerScreen(playerId) ~= 0 then
			SetPlayerScreen(0, playerId)
		else
			SetPlayerScreen(screen, playerId)
		end

	end
end
```


### GetPlayerScreen

```lua
handle = GetPlayerScreen( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to interacted screen or zero if none）

示例：

```lua
function server.tick()
	if InputPressed("interact", playerId) then
		if GetPlayerScreen(playerId) ~= 0 then
			SetPlayerScreen(0, playerId)
		else
			SetPlayerScreen(screen, playerId)
		end

	end
end
```


### SetPlayerHealth

```lua
SetPlayerHealth( health, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `health` | `number` | 否 | Set player health (between zero and one) |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	if InputPressed("interact", playerId) then
		if GetPlayerHealth() < 0.75 then
			SetPlayerHealth(1.0, playerId)
		else
			SetPlayerHealth(0.5, playerId)
		end
	end
end
```


### GetPlayerHealth

```lua
health = GetPlayerHealth( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`health`: number（Current player health）

示例：

```lua
function server.tick()
	if InputPressed("interact", playerId) then
		if GetPlayerHealth() < 0.75 then
			SetPlayerHealth(1.0, playerId)
		else
			SetPlayerHealth(0.5, playerId)
		end
	end
end
```


### GetPlayerCanUseTool

```lua
canusetool = GetPlayerCanUseTool( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`canusetool`: bool（If the player currenty can use tool.）

示例：

```lua
function server.tick()
	for p in Players() do
		if GetPlayerCanUseTool(p) and InputPressed("usetool", p) then
			-- fire laser
		end
	end
end
```


### SetPlayerRegenerationState

```lua
SetPlayerRegenerationState( state, [player] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `state` | `boolean` | 否 | State of player regeneration |
| `player` | `number` | 是 | Player ID change regeneration for |

示例：

```lua
function playerJoined(playerId)
	-- initially disable regeneration for player
	SetPlayerRegenerationState(false, playerId)
end
```


### SetPlayerTool

```lua
SetPlayerTool( toolId, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Set Tool ID |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function playerJoined(playerId)
	-- Server sets player tool to "gun"
	SetPlayerTool("gun", playerId)
end
```


### GetPlayerTool

```lua
toolId = GetPlayerTool( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`toolId`: string（Get Tool ID）

示例：

```lua
local tool = GetPlayerTool()
```


### RespawnPlayer

```lua
RespawnPlayer( [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	for p in Players() do
		if InputPressed("interact", p) then
			RespawnPlayer(p)
		end
	end
end
```


### RespawnPlayerAtTransform

```lua
RespawnPlayerAtTransform( transform, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `transform` | 否 | Transform |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	for p in Players() do
		if InputPressed("interact", p) then
			RespawnPlayerAtTransform(Transform(Vec(1,2,3)), p)
		end
	end
end
```


### GetPlayerWalkingSpeed

```lua
speed = GetPlayerWalkingSpeed( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`speed`: number（Current player base walking speed）

示例：

```lua
function client.tick()
	DebugPrint(GetPlayerWalkingSpeed())
end
```


### SetPlayerWalkingSpeed

```lua
SetPlayerWalkingSpeed( speed, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `speed` | `number` | 否 | Set player walking speed |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()

	for p in Players() do
		-- Set player walking speed based on whether shift is pressed
		if InputDown("shift", p) then
			SetPlayerWalkingSpeed(15.0, p)
		else
			SetPlayerWalkingSpeed(7.0, p)
		end
	end
end
```


### GetPlayerCrouchSpeedScale

```lua
speed = GetPlayerCrouchSpeedScale( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`speed`: number（Current player walking speed while crouched）

示例：

```lua
function client.tick()
	DebugPrint(GetPlayerCrouchSpeedScale())
end
```


### SetPlayerCrouchSpeedScale

```lua
SetPlayerCrouchSpeedScale( speed, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `speed` | `number` | 否 | Set player walking speed while crouched |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	for p in Players() do
		if InputDown("shift") then
			SetPlayerCrouchSpeedScale(5.0, p)
		else
			SetPlayerCrouchSpeedScale(3.0, p)
		end
	end
end
```


### GetPlayerHurtSpeedScale

```lua
speed = GetPlayerHurtSpeedScale( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`speed`: number（Current player walking speed when hurt）

示例：

```lua
function client.tick()
	DebugPrint(GetPlayerHurtSpeedScale())
end
```


### SetPlayerHurtSpeedScale

```lua
SetPlayerHurtSpeedScale( speed, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `speed` | `number` | 否 | Set player walking speed when hurt |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	-- Reduce hurt penalty (default is 2/7 or roughly 0.29)
	for p in Players() do
		SetPlayerHurtSpeedScale(0.6, p)
	end
end
```


### GetPlayerParam

```lua
value = GetPlayerParam( parameter, [player] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `parameter` | `string` | 否 | Parameter name |
| `player` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`value`: any（Parameter value）

| Param name | Type | Description |
| --- | --- | --- |
| health | float | Current value of the player's health. |
| healthRegeneration | boolean &nbsp | Is the player's health regeneration enabled. |
| walkingSpeed | float | The player's walking speed. |
| jumpSpeed | float | The player's jump speed. |
| godMode | boolean &nbsp | If the value is True, the player does not lose health |
| friction | float | Player body friction |
| frictionMode | string | Player friction combine mode |
| flyMode | boolean &nbsp | If the value is True, the player will fly |
| flashlightAllowed | boolean &nbsp | Changes ability to use flashlight |
| disableInteract | boolean &nbsp | Disable interactions for player |
| CollisionMask | int | Player collision mask bits (0-255) with respect to all shapes layer bits |

示例：

```lua
function client.tick()
	-- The parameter names are case-insensitive, so any of the specified writing styles will be correct:
	-- "GodMode", "godmode", "godMode"
	local paramName = "GodMode"
	local param = GetPlayerParam(paramName)
	DebugWatch(paramName, param)
end
```


### SetPlayerParam

```lua
SetPlayerParam( parameter, value, [player] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `parameter` | `string` | 否 | Parameter name |
| `value` | `any` | 否 | Parameter value |
| `player` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

| Persistent param name | Type | Description |
| --- | --- | --- |
| health | float | Current value of the player's health. |
| healthRegeneration | boolean &nbsp | Is the player's health regeneration enabled. |
| godMode | boolean &nbsp | If the value is True, the player does not lose health |
| friction | float | Player body friction. Default is 0.8 |
| frictionMode | string | Player friction combine mode. Can be (average\|minimum\|multiply\|maximum) |
| flyMode | boolean &nbsp | If the value is True, the player will fly |
| flashlightAllowed | boolean &nbsp | Changes ability to use flashlight |
| CollisionMask | int | Player collision mask bits (0-255) with respect to all shapes layer bits |

| Immediate param name | Type | Description |
| --- | --- | --- |
| walkingSpeed | float | The player's walking speed. This value is applied for one frame and must be set every tick. |
| jumpSpeed | float | The player's jump speed. The height of the jump depends non-linearly on the jump speed. This value is applied for one frame and must be set every tick. |
| disableInteract | boolean &nbsp | Disable interactions for player. This value is applied for one frame and must be set every tick. |

示例：

```lua
function server.tick()
	-- The parameter names are case-insensitive, so any of the specified writing styles will be correct:
	-- "JumpSpeed", "jumpspeed", "jumpSpeed"
	local paramName = "JumpSpeed"

	for p in Players() do
		-- Set player jump speed based on whether shift is pressed
		if InputDown("shift", p) then
			SetPlayerParam(paramName, 10, p)
		else
			SetPlayerParam(paramName, 5, p)
		end
	end
end
```


### SetPlayerHidden

```lua
SetPlayerHidden( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
function client.tick()
	...
	SetCameraTransform(t)
	SetPlayerHidden()
end
```


### RegisterTool

```lua
RegisterTool( id, name, file, [group] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 否 | Tool unique identifier |
| `name` | `string` | 否 | Tool name to show in hud |
| `file` | `string` | 否 | Path to vox file or prefab xml |
| `group` | `number` | 是 | Tool group for this tool (1-6) Default is 6. |

示例：

```lua
#include "script/include/player.lua"

function server.init()
	RegisterTool("lasergun", "Laser Gun", "MOD/vox/lasergun.vox", 6)
end

function server.tick()

	for p in PlayersAdded() do
		SetToolEnabled("lasergun", true, p)
		SetToolAmmo("lasergun", 60, p)
	end

	for p in Players() do
		if GetPlayerTool(p) == "lasergun" then
			--Tool is selected. Tool logic goes here.
			if InputPressed("usetool", p) then
				-- Fire the tool
			end
		end
	end
end

function client.tick()
	for p in Players() do
		if GetPlayerTool(p) == "lasergun" then
			if InputPressed("usetool", p) then
				-- Spawn client side particles, play sound, etc.
			end
		end
	end
end
```


### SetToolAmmoPickupAmount

```lua
SetToolAmmoPickupAmount( toolId, ammo )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Tool ID |
| `ammo` | `number` | 否 | The default ammo pickup amount |

示例：

```lua
function server.init()
	RegisterTool("lasergun", "Laser Gun", "MOD/vox/lasergun.vox", 6)
	SetToolAmmoPickupAmount("lasergun", 30)
end
```


### GetToolAmmoPickupAmount

```lua
ammo = GetToolAmmoPickupAmount( toolId )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Tool ID |

**返回**：`ammo`: number（The default ammo pickup amount）

示例：

```lua
local ammo = GetToolAmmoPickupAmount("gun")
```


### GetToolBody

```lua
handle = GetToolBody( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`handle`: number（Handle to currently visible tool body or zero if none）

示例：

```lua
function client.tick()
	local toolBody = GetToolBody()
	if toolBody~=0 then
		DebugPrint("Tool body: " .. toolBody)
	end
end
```


### GetToolHandPoseLocalTransform

```lua
right, left = GetToolHandPoseLocalTransform( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`right`: TTransform（Transform of right hand relative to the tool body origin, or nil if the right hand is not used）；`left`: TTransform（Transform of left hand, or nil if left hand is not used）

示例：

```lua
local right, left = GetToolHandPoseLocalTransform()
```


### GetToolHandPoseWorldTransform

```lua
right, left = GetToolHandPoseWorldTransform( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`right`: TTransform（Transform of right hand in world space, or nil if the right hand is not used）；`left`: TTransform（Transform of left hand, or nil if left hand is not used）

示例：

```lua
local right, left = GetToolHandPoseWorldTransform()
```


### SetToolHandPoseLocalTransform

```lua
SetToolHandPoseLocalTransform( right, left, [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `right` | `TTransform` | 否 | Transform of right hand relative to the tool body origin, or nil if right hand is not used |
| `left` | `TTransform` | 否 | Transform of left hand, or nil if left hand is not used |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. |

示例：

```lua
if GetBool("game.thirdperson") then
	if aiming then
		SetToolHandPoseLocalTransform(Transform(Vec(0.2,0.0,0.0), QuatAxisAngle(Vec(0,1,0), 90.0)), Transform(Vec(-0.1, 0.0, -0.4)))
	else
		SetToolHandPoseLocalTransform(Transform(Vec(0.2,0.0,0.0), QuatAxisAngle(Vec(0,1,0), 90.0)), nil)
	end
end
```


### GetToolLocationLocalTransform

```lua
location = GetToolLocationLocalTransform( name, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Name of location |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`location`: TTransform（Transform of a tool location in tool space or nil if location is not found.）

示例：

```lua
local right  = GetToolLocationLocalTransform("righthand")
SetToolHandPoseLocalTransform(right, nil)
```


### GetToolLocationWorldTransform

```lua
location = GetToolLocationWorldTransform( name, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Name of location |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`location`: TTransform（Transform of a tool location in world space or nil if the location is not found or if there is no visible tool body.）

示例：

```lua
local muzzle = GetToolLocationWorldTransform("muzzle")
Shoot(muzzle, direction)
```


### SetToolTransform

```lua
SetToolTransform( transform, [sway], [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Tool body transform |
| `sway` | `number` | 是 | Tool sway amount. Default is 1.0 |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. |

示例：

```lua
function client.tick()
	--Offset the tool half a meter to the right for the local player
	local offset = Transform(Vec(0.5, 0, 0))
	SetToolTransform(offset)
end
```


### SetToolAllowedZoom

```lua
SetToolAllowedZoom( zoom, [zoom sensitivity] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `zoom` | `number` | 否 | Zoom factor |
| `zoom sensitivity` | `number` | 是 | Input sensitivity when zoomed in. Default is 1.0. |

示例：

```lua
function client.tick()
	-- allow our scoped tool to zoom by factor 4.
	SetToolAllowedZoom(4.0, 0.5)
end
```


### SetToolTransformOverride

```lua
SetToolTransformOverride( transform, [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Tool body transform |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. |

示例：

```lua
function client.tick()

	if GetBool("game.thirdperson") then
		local toolTransform = Transform(Vec(0.3, -0.3, -0.2), Quat(0.0, 0.0, 15.0))

		-- Rotate around point
		local pivotPoint = Vec(-0.01, -0.2, 0.04)
		toolTransform.pos = VecSub(toolTransform.pos, pivotPoint)
		local rotation = Transform(Vec(), QuatAxisAngle(Vec(0,0,1), GetPlayerPitch()))
		toolTransform = TransformToParentTransform(rotation, toolTransform)
		toolTransform.pos = VecAdd(toolTransform.pos, pivotPoint)

		SetToolTransformOverride(toolTransform)
	else
		local toolTransform = Transform(Vec(0.3, -0.3, -0.2), Quat(0.0, 0.0, 15.0))
		SetToolTransform(toolTransform)
	end
end
```


### SetToolOffset

```lua
SetToolOffset( offset, [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `offset` | `TVec` | 否 | Tool body offset |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. |

示例：

```lua
function client.tick()
	--Offset the tool depending on character height
	local defaultEyeY = 1.7
	local offsetY = characterHeight - defaultEyeY
	local offset = Vec(0, offsetY, 0)
	SetToolOffset(offset)
end
```


### SetToolAmmo

```lua
SetToolAmmo( toolId, ammo, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Tool ID |
| `ammo` | `number` | 否 | Total ammo |
| `playerId` | `number` | 是 | Player ID. On server, zero means server (host) player. |

示例：

```lua
SetToolAmmo("gun", 10, 1)
```


### GetToolAmmo

```lua
ammo = GetToolAmmo( toolId, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Tool ID |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`ammo`: number（Total ammo for tool）

示例：

```lua
local ammo = GetToolAmmo("gun", 1)
```


### SetToolEnabled

```lua
SetToolEnabled( toolId, enabled, [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Tool ID |
| `enabled` | `bool` | 否 | Tool enabled |
| `playerId` | `number` | 是 | Player ID |

示例：

```lua
SetToolEnabled("gun", false, playerId)
```


### IsToolEnabled

```lua
enabled = IsToolEnabled( toolId, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `toolId` | `string` | 否 | Tool ID |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`enabled`: bool（Tool enabled for player）

示例：

```lua
if IsToolEnabled("gun", 1) then
	...
end
```


### SetPlayerOrientation

```lua
SetPlayerOrientation( orientation, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `orientation` | `Quat` | 否 | Base orientation |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
function server.tick()
	SetGravity(Vec(0, 0, 0))

	-- Turn players upside-down.
	for p in Players() do
		SetPlayerOrientation(QuatAxisAngle(Vec(1,0,0), 180), p)
	end
end
```


### GetPlayerOrientation

```lua
GetPlayerOrientation( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
function server.tick(dt)
	SetGravity(Vec(0, 0, 0))

	for p in Players() do
		-- Spin the player if using zero gravity
		local base = QuatRotateQuat(GetPlayerOrientation(p), QuatAxisAngle(Vec(1,0,0), dt))
		SetPlayerOrientation(base, p)
	end
end
```


### GetPlayerUp

```lua
up = GetPlayerUp( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`up`: TVec（Up vector of the player）

示例：

```lua
function client.tick()
	local up = GetPlayerUp()
	DebugPrint("Player up vector: " .. up)
end
```


### SetPlayerRig

```lua
SetPlayerRig( rig, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig` | `number` | 否 | Rig handle |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
local rig = FindRig("myrig")
    SetPlayerRig(rig)
```


### GetPlayerRig

```lua
rig = GetPlayerRig( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`rig`: number（Rig handle）

示例：

```lua
local rig = GetPlayerRig(rigid)
```


### GetPlayerRigWorldTransform

```lua
transform = GetPlayerRigWorldTransform( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`transform`: TTransform（World transform, nil if player doesnt have a rig）

示例：

```lua
local t = GetPlayerRigWorldTransform()
```


### ClearPlayerRig

```lua
ClearPlayerRig( rig-id, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig-id` | `number` | 否 | Unique rig-id, -1 means all rigs |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
ClearPlayerRig(someId)
```


### SetPlayerRigLocationLocalTransform

```lua
SetPlayerRigLocationLocalTransform( rig-id, name, location, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig-id` | `number` | 否 | Unique id |
| `name` | `string` | 否 | Name of location |
| `location` | `table` | 否 | Rig Local transform of the location |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
local someBody = FindBody("bodyname")
    SetPlayerRigLocationLocalTransform(someBody, "ik_foot_l", TransformToLocalTransform(GetBodyTransform(someBody), GetLocationTransform(FindLocation("ik_foot_l"))))
```


### SetPlayerRigTransform

```lua
SetPlayerRigTransform( rig-id, location, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig-id` | `number` | 否 | Unique id |
| `location` | `table` | 否 | New world transform |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
local someBody = FindBody("bodyname")
    SetPlayerRigTransform(someBody, GetBodyTransform(someBody))
```


### GetPlayerRigLocationWorldTransform

```lua
location = GetPlayerRigLocationWorldTransform( name, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Name of location |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`location`: table（Transform of a location in world space）

示例：

```lua
local t = GetPlayerRigLocationWorldTransform("ik_hand_l")
```


### SetPlayerRigTags

```lua
SetPlayerRigTags( rig-id, tag, [playerId] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `rig-id` | `number` | 否 | Unique id |
| `tag` | `string` | 否 | Tag |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. |


### GetPlayerRigHasTag

```lua
exists = GetPlayerRigHasTag( tag, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 否 | Tag name |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`exists`: boolean（Returns true if entity has tag）


### GetPlayerRigTagValue

```lua
value = GetPlayerRigTagValue( tag, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `tag` | `string` | 否 | Tag name |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`value`: string（Returns the tag value, if any. Empty string otherwise.）


### GetPlayerColor

```lua
inuse, r, g, b = GetPlayerColor( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

**返回**：`inuse`: boolean（If color is used or not）；`r`: number（Red channel value）；`g`: number（Green channel value）；`b`: number（Blue channel value）

示例：

```lua
function client.tick()
	local inuse, r, g, b = GetPlayerColor()
	if inuse then
		DebugPrint("Player color: " .. r .. ", " .. g .. ", " .. b)
	else
		DebugPrint("Player color is not set")
	end
end
```


### SetPlayerColor

```lua
SetPlayerColor( r, g, b, [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red value |
| `g` | `number` | 否 | Green value |
| `b` | `number` | 否 | Blue value |
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
end
function client.tick()
	local r, g, b = 1.0, 0.5, 0.2
	SetPlayerColor(r, g, b)
	DebugPrint("Set player color to: " .. r .. ", " .. g .. ", " .. b)
end
```


### ApplyPlayerDamage

```lua
ApplyPlayerDamage( targetPlayerId, damage, [cause], [instigatingPlayerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `targetPlayerId` | `number` | 否 | Target player ID |
| `damage` | `number` | 否 | Damage to apply to target player |
| `cause` | `string` | 是 | The cause of damage |
| `instigatingPlayerId` | `number` | 是 | Instigating player ID. |

示例：

```lua
function server.tick(dt)
	
	for player in Players() do
		if isOnFire(player) then
			-- Apply 20% of dt as damage to the player
			ApplyPlayerDamage(player, 0.2 * dt, "fire")
		end
	end
	
	-- or

	for player in Players() do
		if InputIsPressed("usetool", player) then
			for target in Players() do
				if target ~= player and isInRange(player, target) then
					-- Apply 50% damage to the target player
					ApplyPlayerDamage(target, 0.5, "tool", player)
				end
			end
		end
	end
end
```


### DisablePlayerInput

```lua
DisablePlayerInput( player )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `player` | `playerIndex` | 否 | Player to disable input for |

示例：

```lua
-- Disable player 2 input as she/he is interacting with something.
DisablePlayerInput(2)
```


### DisablePlayer

```lua
DisablePlayer( playerId )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 否 | Player to disable |

示例：

```lua
function updateFinalScoreboard()
	for i=1,#hiddenPlayers do
		DisablePlayer(hiddenPlayers[i])
	end
end
```


### IsPlayerDisabled

```lua
IsPlayerDisabled( playerId )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 否 | Check if player is disabled |

示例：

```lua
--check if disabled
playerDisabled = IsPlayerDisabled(playerId)
```


### DisablePlayerDamage

```lua
DisablePlayerDamage( playerId )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 否 | Player for which damage should be disabled |

示例：

```lua
function server.tick()
	for i=1,#invulnerablePlayers do
		DisablePlayerDamage(invulnerablePlayers[i])
	end
end
```



---

## Sound

<b>22 个函数</b>

### LoadSound

```lua
handle = LoadSound( path, [nominalDistance] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to ogg sound file |
| `nominalDistance` | `number` | 是 | The distance in meters this sound is recorded at. Affects attenuation, default is 10.0 |

**返回**：`handle`: number（Sound handle）

示例：

```lua
function client.init()
	local snd = LoadSound("warning-beep.ogg")
end
```


### UnloadSound

```lua
UnloadSound( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound handle |

示例：

```lua
function client.init()
	local snd = LoadSound("warning-beep.ogg")
	UnloadSound(snd)
end
```


### LoadLoop

```lua
handle = LoadLoop( path, [nominalDistance] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to ogg sound file |
| `nominalDistance` | `number` | 是 | The distance in meters this sound is recorded at. Affects attenuation, default is 10.0 |

**返回**：`handle`: number（Loop handle）

示例：

```lua
local loop
function client.init()
	loop = LoadLoop("radio/jazz.ogg")
end

function client.tick()
	local pos = Vec(0, 0, 0)
	PlayLoop(loop, pos, 1.0)
end
```


### UnloadLoop

```lua
UnloadLoop( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Loop handle |

示例：

```lua
local loop = -1
function client.init()
	loop = LoadLoop("radio/jazz.ogg")
end

function client.tick()
	if loop ~= -1 then
		local pos = Vec(0, 0, 0)
		PlayLoop(loop, pos, 1.0)
	end

	if InputPressed("space") then
		UnloadLoop(loop)
		loop = -1
	end
end
```


### SetSoundLoopUser

```lua
flag = SetSoundLoopUser( handle, nominalDistance )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Loop handle |
| `nominalDistance` | `number` | 否 | User index |

**返回**：`flag`: boolean（TRUE if sound applied to gamepad speaker, FALSE otherwise.）

示例：

```lua
function client.init()
	local loop = LoadLoop("radio/jazz.ogg")
	SetSoundLoopUser(loop, 0)
end
--This function will move (if possible) sound to gamepad of appropriate user
```


### PlaySound

```lua
handle = PlaySound( handle, [pos], [volume], [registerVolume], [pitch] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound handle |
| `pos` | `TVec` | 是 | World position as vector. Default is player position. |
| `volume` | `number` | 是 | Playback volume. Default is 1.0 |
| `registerVolume` | `boolean` | 是 | Register position and volume of this sound for GetLastSound. Default is true |
| `pitch` | `number` | 是 | Playback pitch. Default 1.0 |

**返回**：`handle`: number（Sound play handle）

示例：

```lua
local snd
function client.init()
	snd = LoadSound("warning-beep.ogg")
end

function client.tick()
	if InputPressed("interact") then
		local pos = Vec(0, 0, 0)
		PlaySound(snd, pos, 0.5)
	end
end

-- If you have a list of sound files and you add a sequence number, starting from zero, at the end of each filename like below,
-- then each time you call PlaySound it will pick a random sound from that list and play that sound.

-- "example-sound0.ogg"
-- "example-sound1.ogg"
-- "example-sound2.ogg"
-- "example-sound3.ogg"
-- ...
--[[
	local snd
	function client.init()
		snd = LoadSound("example-sound0.ogg")
	end

	-- Plays a random sound from the loaded sound series
	function client.tick()
		if trigSound then
			local pos = Vec(100, 0, 0)
			PlaySound(snd, pos, 0.5)
		end
	end
]]
```


### PlaySoundForUser

```lua
handle = PlaySoundForUser( handle, user, [pos], [volume], [registerVolume], [pitch] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound handle |
| `user` | `number` | 否 | Index of user to play. |
| `pos` | `TVec` | 是 | World position as vector. Default is player position. |
| `volume` | `number` | 是 | Playback volume. Default is 1.0 |
| `registerVolume` | `boolean` | 是 | Register position and volume of this sound for GetLastSound. Default is true |
| `pitch` | `number` | 是 | Playback pitch. Default 1.0 |

**返回**：`handle`: number（Sound play handle）

示例：

```lua
local snd
function client.init()
	snd = LoadSound("warning-beep.ogg")
end

function client.tick()
	if InputPressed("interact") then
		PlaySoundForUser(snd, 0)
	end
end

-- If you have a list of sound files and you add a sequence number, starting from zero, at the end of each filename like below,
-- then each time you call PlaySoundForUser it will pick a random sound from that list and play that sound.

-- "example-sound0.ogg"
-- "example-sound1.ogg"
-- "example-sound2.ogg"
-- "example-sound3.ogg"
-- ...

--[[
	local snd
	function client.init()
		snd = LoadSound("example-sound0.ogg")
	end

	-- Plays a random sound from the loaded sound series
	function client.tick()
		if trigSound then
			local pos = Vec(100, 0, 0)
			PlaySoundForUser(snd, 0, pos, 0.5)
		end
	end
]]
```


### StopSound

```lua
StopSound( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound play handle |

示例：

```lua
local snd
function client.init()
	snd = LoadSound("radio/jazz.ogg")
end

local sndPlay
function client.tick()
	if InputPressed("interact") then
		if not IsSoundPlaying(sndPlay) then
			local pos = Vec(0, 0, 0)
			sndPlay = PlaySound(snd, pos, 0.5)
		else
			StopSound(sndPlay)
		end
	end
end
```


### IsSoundPlaying

```lua
playing = IsSoundPlaying( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound play handle |

**返回**：`playing`: boolean（True if sound is playing, false otherwise.）

示例：

```lua
local snd
function client.init()
	snd = LoadSound("radio/jazz.ogg")
end

local sndPlay
function client.tick()
	if InputPressed("interact") then
		if not IsSoundPlaying(sndPlay) then
			local pos = Vec(0, 0, 0)
			sndPlay = PlaySound(snd, pos, 0.5)
		else
			StopSound(sndPlay)
		end
	end
end
```


### GetSoundProgress

```lua
progress = GetSoundProgress( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound play handle |

**返回**：`progress`: number（Current sound progress in seconds.）

示例：

```lua
local snd
function client.init()
	snd = LoadSound("radio/jazz.ogg")
end

local sndPlay
function client.tick()
	if InputPressed("interact") then
		if not IsSoundPlaying(sndPlay) then
			local pos = Vec(0, 0, 0)
			sndPlay = PlaySound(snd, pos, 0.5)
		else
			SetSoundProgress(sndPlay, GetSoundProgress(sndPlay) - 1.0)
		end
	end
end
```


### SetSoundProgress

```lua
SetSoundProgress( handle, progress )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sound play handle |
| `progress` | `number` | 否 | Progress in seconds |

示例：

```lua
local snd
function client.init()
	snd = LoadSound("radio/jazz.ogg")
end

local sndPlay
function client.tick()
	if InputPressed("interact") then
		if not IsSoundPlaying(sndPlay) then
			local pos = Vec(0, 0, 0)
			sndPlay = PlaySound(snd, pos, 0.5)
		else
			SetSoundProgress(sndPlay, GetSoundProgress(sndPlay) - 1.0)
		end
	end
end
```


### PlayLoop

```lua
PlayLoop( handle, [pos], [volume], [registerVolume], [pitch] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Loop handle |
| `pos` | `TVec` | 是 | World position as vector. Default is player position. |
| `volume` | `number` | 是 | Playback volume. Default is 1.0 |
| `registerVolume` | `boolean` | 是 | Register position and volume of this sound for GetLastSound. Default is true |
| `pitch` | `number` | 是 | Playback pitch. Default 1.0 |

示例：

```lua
local loop
function client.init()
	loop = LoadLoop("radio/jazz.ogg")
end

function client.tick()
	local pos = Vec(0, 0, 0)
	PlayLoop(loop, pos, 1.0)
end
```


### GetSoundLoopProgress

```lua
progress = GetSoundLoopProgress( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Loop handle |

**返回**：`progress`: number（Current music progress in seconds.）

示例：

```lua
function client.init()
	loop = LoadLoop("radio/jazz.ogg")
end

function client.tick()
	local pos = Vec(0, 0, 0)
	PlayLoop(loop, pos, 1.0)
	if InputPressed("interact") then
		SetSoundLoopProgress(loop, GetSoundLoopProgress(loop) - 1.0)
	end
end
```


### SetSoundLoopProgress

```lua
SetSoundLoopProgress( handle, [progress] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Loop handle |
| `progress` | `number` | 是 | Progress in seconds. Default 0.0. |

示例：

```lua
function client.init()
	loop = LoadLoop("radio/jazz.ogg")
end

function client.tick()
	local pos = Vec(0, 0, 0)
	PlayLoop(loop, pos, 1.0)
	if InputPressed("interact") then
		SetSoundLoopProgress(loop, GetSoundLoopProgress(loop) - 1.0)
	end
end
```


### PlayMusic

```lua
PlayMusic( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Music path |

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end
```


### StopMusic

```lua
StopMusic(  )
```

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputDown("interact") then
		StopMusic()
	end
end
```


### IsMusicPlaying

```lua
playing = IsMusicPlaying(  )
```

**返回**：`playing`: boolean（True if music is playing, false otherwise.）

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputPressed("interact") and IsMusicPlaying() then
		DebugPrint("music is playing")
	end
end
```


### SetMusicPaused

```lua
SetMusicPaused( paused )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `paused` | `boolean` | 否 | True to pause, false to resume. |

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputPressed("interact") then
		SetMusicPaused(IsMusicPlaying())
	end
end
```


### GetMusicProgress

```lua
progress = GetMusicProgress(  )
```

**返回**：`progress`: number（Current music progress in seconds.）

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputPressed("interact") then
		DebugPrint(GetMusicProgress())
	end
end
```


### SetMusicProgress

```lua
SetMusicProgress( [progress] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `progress` | `number` | 是 | Progress in seconds. Default 0.0. |

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputPressed("interact") then
 		SetMusicProgress(GetMusicProgress() - 1.0)
	end
end
```


### SetMusicVolume

```lua
SetMusicVolume( volume )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `volume` | `number` | 否 | Music volume. |

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputDown("interact") then
 		SetMusicVolume(0.3)
	end
end
```


### SetMusicLowPass

```lua
SetMusicLowPass( wet )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `wet` | `number` | 否 | Music low pass filter 0.0 - 1.0. |

示例：

```lua
function client.init()
	PlayMusic("about.ogg")
end

function client.tick()
	if InputDown("interact") then
 		SetMusicLowPass(0.6)
	end
end
```



---

## Sprite

<b>2 个函数</b>

### LoadSprite

```lua
handle = LoadSprite( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to sprite. Must be PNG or JPG format. |

**返回**：`handle`: number（Sprite handle）

示例：

```lua
function client.init()
	arrow = LoadSprite("gfx/arrowdown.png")
end
```


### DrawSprite

```lua
DrawSprite( handle, transform, width, height, [r], [g], [b], [a], [depthTest], [additive], [fogAffected] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Sprite handle |
| `transform` | `TTransform` | 否 | Transform |
| `width` | `number` | 否 | Width in meters |
| `height` | `number` | 否 | Height in meters |
| `r` | `number` | 是 | Red color. Default 1.0. |
| `g` | `number` | 是 | Green color. Default 1.0. |
| `b` | `number` | 是 | Blue color. Default 1.0. |
| `a` | `number` | 是 | Alpha. Default 1.0. |
| `depthTest` | `boolean` | 是 | Depth test enabled. Default false. |
| `additive` | `boolean` | 是 | Additive blending enabled. Default false. |
| `fogAffected` | `boolean` | 是 | Enable distance fog effect. Default false. |

示例：

```lua
function client.init()
	arrow = LoadSprite("gfx/arrowdown.png")
end

function client.tick()
	--Draw sprite using transform
	--Size is two meters in width and height
	--Color is white, fully opaue
	local t = Transform(Vec(0, 10, 0), QuatEuler(0, GetTime(), 0))
	DrawSprite(arrow, t, 2, 2, 1, 1, 1, 1)
end
```



---

## Scene queries

<b>28 个函数</b>

### QueryRequire

```lua
QueryRequire( layers )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `layers` | `string` | 否 | Space separate list of layers |

| Layer | Description |
| --- | --- |
| physical | have a physical representation |
| dynamic | part of a dynamic body |
| static | part of a static body |
| large | above debris threshold |
| small | below debris threshold |
| visible | only hit visible shapes |
| animator | part of an animator hierarchy |
| player | part of an player animator hierarchy |
| tool | part of a tool |

示例：

```lua
--Raycast dynamic, physical objects above debris threshold, but not specific vehicle
function client.tick()
	local vehicle = FindVehicle("vehicle")
	QueryRequire("physical dynamic large")
	QueryRejectVehicle(vehicle)
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryInclude

```lua
QueryInclude( layers )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `layers` | `string` | 否 | Space separate list of layers |

| Layer | Description |
| --- | --- |
| physical | have a physical representation |
| dynamic | part of a dynamic body |
| static | part of a static body |
| large | above debris threshold |
| small | below debris threshold |
| visible | only hit visible shapes |
| animator | part of an animator hierarchy |
| player | part of an player |
| tool | part of a tool |

示例：

```lua
--Raycast all the default layers and include the player layer.
function client.tick()
	QueryInclude("player")
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryCollisionMask

```lua
QueryCollisionMask( mask )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `mask` | `number` | 否 | Mask bits (0-255) |

示例：

```lua
--Find the closest point on any shape (within 2 meters) to the player eye that the player can collide with.
function client.tick()
	QueryRequire("physical")
	QueryCollisionMask(GetPlayerParam("CollisionMask"))
	local hit, hitpos = QueryClosestPoint(GetPlayerEyeTransform().pos, 2)
	if hit then
		DebugCross(hitpos)
	end
end
```


### QueryRejectAnimator

```lua
QueryRejectAnimator( handle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Animator handle |


### QueryRejectVehicle

```lua
QueryRejectVehicle( vehicle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vehicle` | `number` | 否 | Vehicle handle |

示例：

```lua
function client.tick()
	local vehicle = FindVehicle("vehicle")
	QueryRequire("physical dynamic large")
	--Do not include vehicle in next raycast
	QueryRejectVehicle(vehicle)
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryRejectBody

```lua
QueryRejectBody( body )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `body` | `number` | 否 | Body handle |

示例：

```lua
function client.tick()
	local body = FindBody("body")
	QueryRequire("physical dynamic large")
	--Do not include body in next raycast
	QueryRejectBody(body)
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryRejectBodies

```lua
QueryRejectBodies( bodies )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bodies` | `table` | 否 | Array with bodies handles |

示例：

```lua
function client.tick()
	local body = FindBody("body")
	QueryRequire("physical dynamic large")
	local bodies = {body}
	--Do not include body in next raycast
	QueryRejectBodies(bodies)
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryRejectShape

```lua
QueryRejectShape( shape )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |

示例：

```lua
function client.tick()
	local shape = FindShape("shape")
	QueryRequire("physical dynamic large")
	--Do not include shape in next raycast
	QueryRejectShape(shape)
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryRejectShapes

```lua
QueryRejectShapes( shapes )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shapes` | `table` | 否 | Array with shapes handles |

示例：

```lua
function client.tick()
	local shape = FindShape("shape")
	QueryRequire("physical dynamic large")
	local shapes = {shape}
	--Do not include shape in next raycast
	QueryRejectShapes(shapes)
	local hit, dist = QueryRaycast(Vec(0, 0, 0), Vec(1, 0, 0), 10)
	if hit then
		DebugPrint(dist)
	end
end
```


### QueryRejectPlayer

```lua
QueryRejectPlayer( [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `playerId` | `number` | 是 | Player ID. On client, zero means client player. On server, zero means server (host) player. |

示例：

```lua
--Do not include shape in next raycast
QueryRejectPlayer(1)
QueryRaycast(...)
```


### QueryRaycast

```lua
hit, dist, normal, shape = QueryRaycast( origin, direction, maxDist, [radius], [rejectTransparent] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Raycast origin as world space vector |
| `direction` | `TVec` | 否 | Unit length raycast direction as world space vector |
| `maxDist` | `number` | 否 | Raycast maximum distance. Keep this as low as possible for good performance. |
| `radius` | `number` | 是 | Raycast thickness. Default zero. |
| `rejectTransparent` | `boolean` | 是 | Raycast through transparent materials. Default false. |

**返回**：`hit`: boolean（True if raycast hit something）；`dist`: number（Hit distance from origin）；`normal`: TVec（World space normal at hit point）；`shape`: number（Handle to hit shape）

示例：

```lua
function client.init()
	local vehicle = FindVehicle("vehicle")
	QueryRejectVehicle(vehicle)
	--Raycast from a high point straight downwards, excluding a specific vehicle
	local hit, d = QueryRaycast(Vec(0, 100, 0), Vec(0, -1, 0), 100)
	if hit then
		DebugPrint(d)
	end
end
```


### QueryRaycastRope

```lua
hit, dist, joint = QueryRaycastRope( origin, direction, maxDist, [radius] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Raycast origin as world space vector |
| `direction` | `TVec` | 否 | Unit length raycast direction as world space vector |
| `maxDist` | `number` | 否 | Raycast maximum distance. Keep this as low as possible for good performance. |
| `radius` | `number` | 是 | Raycast thickness. Default zero. |

**返回**：`hit`: boolean（True if raycast hit something）；`dist`: number（Hit distance from origin）；`joint`: number（Handle to hit joint of rope type）

示例：

```lua
function client.tick()
	local playerCameraTransform = GetPlayerCameraTransform()
	local dir = TransformToParentVec(playerCameraTransform, Vec(0, 0, -1))

	local hit, dist, joint = QueryRaycastRope(playerCameraTransform.pos, dir, 10)
	if hit then
		DebugWatch("distance", dist)
		DebugWatch("joint", joint)
	end
end
```


### QueryRaycastWater

```lua
hit, dist, hitPos = QueryRaycastWater( origin, direction, maxDist )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Raycast origin as world space vector |
| `direction` | `TVec` | 否 | Unit length raycast direction as world space vector |
| `maxDist` | `number` | 否 | Raycast maximum distance. Keep this as low as possible for good performance. |

**返回**：`hit`: boolean（True if raycast hit something）；`dist`: number（Hit distance from origin）；`hitPos`: TVec（Hit point as world space vector）

示例：

```lua
function client.init()
	--Raycast from a high point straight downwards, looking for water
	local hit, d = QueryRaycast(Vec(0, 100, 0), Vec(0, -1, 0), 100)
	if hit then
		DebugPrint(d)
	end
end
```


### QueryShot

```lua
didHit, dist, shape, playerId, playerDamageFactor, normal = QueryShot( origin, direction, maxDist, [radius], [playerId] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Shot ray origin as world space vector |
| `direction` | `TVec` | 否 | Unit length direction as world space vector |
| `maxDist` | `number` | 否 | Shot maximum distance. Keep this as low as possible for good performance. |
| `radius` | `number` | 是 | Ray thickness. Default zero. |
| `playerId` | `number` | 是 | Instigating player, will be ignored during hit detection. |

**返回**：`didHit`: bool（If it was a valid hit.）；`dist`: number（Distance along direction where the hit was registered.）；`shape`: number（Handle to hit shape, zero if it did not hit a shape）；`playerId`: number（PlayerId of hit player, zero if it did not hit a player）；`playerDamageFactor`: number（1.0 for a hit on the torso, and less for a lower body hit. Applicable only if a player was hit. Use this to scale the damage.）；`normal`: Vec（Normal vector of the hit）

示例：

```lua
-- Note: 'shape' and 'player' are IDs/handles (numbers), not object references.
function server.tick()

	for p in Players() do
		if InputPressed("usetool", p) then

			local pos = GetPlayerEyeTransform(p).pos
			local dir = TransformToParentVec(GetPlayerEyeTransform(p), Vec(0, 0, -1))

			local hit, dist, shape, player, hitFactor, normal = QueryShot(pos, dir, 100, 0, p)
			if hit then
				if player then
					DebugPrint("Hit player " .. GetPlayerName(player) .. " with damage factor " .. hitFactor)
					ApplyPlayerDamage(player, 0.2 * hitFactor, "SuperGun", p)
				elseif shape then
					DebugPrint("Hit shape " .. shape .. " at distance " .. dist)
					local body = GetShapeBody(shape)
					local impPos = VecAdd(pos, VecScale(dir, dist))
					local imp = Vec(100, 0, 0)
					ApplyBodyImpulse(body, impPos, imp)
				end
			else
				DebugPrint("No hit")
			end
		end
	end
end
```


### QueryClosestPoint

```lua
hit, point, normal, shape = QueryClosestPoint( origin, maxDist )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | World space point |
| `maxDist` | `number` | 否 | Maximum distance. Keep this as low as possible for good performance. |

**返回**：`hit`: boolean（True if a point was found）；`point`: TVec（World space closest point）；`normal`: TVec（World space normal at closest point）；`shape`: number（Handle to closest shape）

示例：

```lua
function client.tick()
	local vehicle = FindVehicle("vehicle")
	--Find closest point within 10 meters of {0, 5, 0}, excluding any point on myVehicle
	QueryRejectVehicle(vehicle)
	local hit, p, n, s = QueryClosestPoint(Vec(0, 5, 0), 10)
	if hit then
		DebugPrint(p)
	end
end
```


### QueryAabbShapes

```lua
list = QueryAabbShapes( min, max )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `min` | `TVec` | 否 | Aabb minimum point |
| `max` | `TVec` | 否 | Aabb maximum point |

**返回**：`list`: table（Indexed table with handles to all shapes in the aabb）

示例：

```lua
function client.tick()
	local list = QueryAabbShapes(Vec(0, 0, 0), Vec(10, 10, 10))
	for i=1, #list do
		local shape = list[i]
		DebugPrint(shape)
	end
end
```


### QueryAabbBodies

```lua
list = QueryAabbBodies( min, max )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `min` | `TVec` | 否 | Aabb minimum point |
| `max` | `TVec` | 否 | Aabb maximum point |

**返回**：`list`: table（Indexed table with handles to all bodies in the aabb）

示例：

```lua
function client.tick()
	local list = QueryAabbBodies(Vec(0, 0, 0), Vec(10, 10, 10))
	for i=1, #list do
		local body = list[i]
		DebugPrint(body)
	end
end
```


### QueryPath

```lua
QueryPath( start, end, [maxDist], [targetRadius], [type] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `start` | `TVec` | 否 | World space start point |
| `end` | `TVec` | 否 | World space target point |
| `maxDist` | `number` | 是 | Maximum path length before giving up. Default is infinite. |
| `targetRadius` | `number` | 是 | Maximum allowed distance to target in meters. Default is 2.0 |
| `type` | `string` | 是 | Type of path. Can be 'low', 'standart', 'water', 'flying'. Default is 'standart' |

示例：

```lua
function client.init()
	QueryPath(Vec(-10, 0, 0), Vec(10, 0, 0))
end
```


### CreatePathPlanner

```lua
id = CreatePathPlanner(  )
```

**返回**：`id`: number（Path planner id）

示例：

```lua
local paths = {}

function server.init()
	paths[1] = {
		id = CreatePathPlanner(),
		location = GetProperty(FindEntity("loc1", true), "transform").pos,
	}

	paths[2] = {
		id = CreatePathPlanner(),
		location = GetProperty(FindEntity("loc2", true), "transform").pos,
	}

	for i = 1, #paths do
		PathPlannerQuery(paths[i].id, GetPlayerTransform().pos, paths[i].location)
	end
end
```


### DeletePathPlanner

```lua
DeletePathPlanner( id )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 否 | Path planner id |

示例：

```lua
local paths = {}

function server.init()
	local id = CreatePathPlanner()
	DeletePathPlanner(id)
	-- now calling PathPlannerQuery for 'id' will result in an error
end
```


### PathPlannerQuery

```lua
PathPlannerQuery( id, start, end, [maxDist], [targetRadius], [type] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 否 | Path planner id |
| `start` | `TVec` | 否 | World space start point |
| `end` | `TVec` | 否 | World space target point |
| `maxDist` | `number` | 是 | Maximum path length before giving up. Default is infinite. |
| `targetRadius` | `number` | 是 | Maximum allowed distance to target in meters. Default is 2.0 |
| `type` | `string` | 是 | Type of path. Can be 'low', 'standart', 'water', 'flying'. Default is 'standart' |

示例：

```lua
local paths = {}

function server.init()
	paths[1] = {
		id = CreatePathPlanner(),
		location = GetProperty(FindEntity("loc1", true), "transform").pos,
	}

	paths[2] = {
		id = CreatePathPlanner(),
		location = GetProperty(FindEntity("loc2", true), "transform").pos,
	}

	for i = 1, #paths do
		PathPlannerQuery(paths[i].id, GetPlayerTransform().pos, paths[i].location)
	end
end
```


### AbortPath

```lua
AbortPath( [id] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 是 | Path planner id. Default value is 0. |

示例：

```lua
function server.init()
	QueryPath(Vec(-10, 0, 0), Vec(10, 0, 0))
	AbortPath()
end
```


### GetPathState

```lua
state = GetPathState( [id] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 是 | Path planner id. Default value is 0. |

**返回**：`state`: string（Current path planning state）

| State | Description |
| --- | --- |
| idle | No recent query |
| busy | Busy computing. No path found yet. |
| fail | Failed to find path. You can still get the resulting path (even though it won't reach the target). |
| done | Path planning completed and a path was found. Get it with GetPathLength and GetPathPoint) |

示例：

```lua
function server.init()
	QueryPath(Vec(-10, 0, 0), Vec(10, 0, 0))
end

function server.tick()
	local s = GetPathState()
	if s == "done" then
		DebugPrint("done")
	end
end
```


### GetPathLength

```lua
length = GetPathLength( [id] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 是 | Path planner id. Default value is 0. |

**返回**：`length`: number（Length of last path planning result (in meters)）

示例：

```lua
function server.init()
	QueryPath(Vec(-10, 0, 0), Vec(10, 0, 0))
end

function server.tick()
	local s = GetPathState()
	if s == "done" then
		DebugPrint("done " .. GetPathLength())
	end
end
```


### GetPathPoint

```lua
point = GetPathPoint( dist, [id] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `dist` | `number` | 否 | The distance along path. Should be between zero and result from GetPathLength() |
| `id` | `number` | 是 | Path planner id. Default value is 0. |

**返回**：`point`: TVec（The path point dist meters along the path）

示例：

```lua
function client.init()
	QueryPath(Vec(-10, 0, 0), Vec(10, 0, 0))
end

function client.tick()
	local d = 0
	local l = GetPathLength()
	while d < l do
		DebugCross(GetPathPoint(d))
		d = d + 0.5
	end
end
```


### GetLastSound

```lua
volume, position = GetLastSound(  )
```

**返回**：`volume`: number（Volume of loudest sound played last frame）；`position`: TVec（World position of loudest sound played last frame）

示例：

```lua
function client.tick()
	local vol, pos = GetLastSound()
	if vol > 0 then
		DebugPrint(vol .. " " .. VecStr(pos))
	end
end
```


### IsPointInWater

```lua
inWater, depth = IsPointInWater( point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `point` | `TVec` | 否 | World point as vector |

**返回**：`inWater`: boolean（True if point is in water）；`depth`: number（Depth of point into water, or zero if not in water）

示例：

```lua
function client.tick()
	local wet, d = IsPointInWater(Vec(10, 0, 0))
	if wet then
		DebugPrint("point" .. d .. " meters into water")
	end
end
```


### GetWindVelocity

```lua
vel = GetWindVelocity( point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `point` | `TVec` | 否 | World point as vector |

**返回**：`vel`: TVec（Wind at provided position）

示例：

```lua
function client.tick()
	local v = GetWindVelocity(Vec(0, 10, 0))
	DebugPrint(VecStr(v))
end
```



---

## Particles

<b>15 个函数</b>

### ParticleReset

```lua
ParticleReset(  )
```

示例：

```lua
function client.init()
	ParticleReset()
end
```


### ParticleType

```lua
ParticleType( type )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `type` | `string` | 否 | Type of particle. Can be 'smoke' or 'plain'. |

示例：

```lua
function client.init()
	ParticleType("smoke")
end
```


### ParticleTile

```lua
ParticleTile( type )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `type` | `number` | 否 | Tile in the particle texture atlas (0-15) |

示例：

```lua
function client.init()
	--Smoke particle
	ParticleTile(0)

	--Fire particle
	ParticleTile(5)
end
```


### ParticleColor

```lua
ParticleColor( r0, g0, b0, [r1], [g1], [b1] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r0` | `number` | 否 | Red value |
| `g0` | `number` | 否 | Green value |
| `b0` | `number` | 否 | Blue value |
| `r1` | `number` | 是 | Red value at end |
| `g1` | `number` | 是 | Green value at end |
| `b1` | `number` | 是 | Blue value at end |

示例：

```lua
function client.init()
	--Constant red
	ParticleColor(1,0,0)

	--Animating from yellow to red
	ParticleColor(1,1,0, 1,0,0)
end
```


### ParticleRadius

```lua
ParticleRadius( r0, [r1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r0` | `number` | 否 | Radius |
| `r1` | `number` | 是 | End radius |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Constant radius 0.4 meters
	ParticleRadius(0.4)

	--Interpolate from small to large
	ParticleRadius(0.1, 0.7)
end
```


### ParticleAlpha

```lua
ParticleAlpha( a0, [a1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `a0` | `number` | 否 | Alpha (0.0 - 1.0) |
| `a1` | `number` | 是 | End alpha (0.0 - 1.0) |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Interpolate from opaque to transparent
	ParticleAlpha(1.0, 0.0)
end
```


### ParticleGravity

```lua
ParticleGravity( g0, [g1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `g0` | `number` | 否 | Gravity |
| `g1` | `number` | 是 | End gravity |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Move particles slowly upwards
	ParticleGravity(2)
end
```


### ParticleDrag

```lua
ParticleDrag( d0, [d1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `d0` | `number` | 否 | Drag |
| `d1` | `number` | 是 | End drag |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Slow down fast moving particles
	ParticleDrag(0.5)
end
```


### ParticleEmissive

```lua
ParticleEmissive( d0, [d1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `d0` | `number` | 否 | Emissive |
| `d1` | `number` | 是 | End emissive |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Highly emissive at start, not emissive at end
	ParticleEmissive(5, 0)
end
```


### ParticleRotation

```lua
ParticleRotation( r0, [r1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r0` | `number` | 否 | Rotation speed in radians per second. |
| `r1` | `number` | 是 | End rotation speed in radians per second. |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Rotate fast at start and slow at end
	ParticleRotation(10, 1)
end
```


### ParticleStretch

```lua
ParticleStretch( s0, [s1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `s0` | `number` | 否 | Stretch |
| `s1` | `number` | 是 | End stretch |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Stretch particle along direction of motion
	ParticleStretch(1.0)
end
```


### ParticleSticky

```lua
ParticleSticky( s0, [s1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `s0` | `number` | 否 | Sticky (0.0 - 1.0) |
| `s1` | `number` | 是 | End sticky (0.0 - 1.0) |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Make particles stick to objects
	ParticleSticky(0.5)
end
```


### ParticleCollide

```lua
ParticleCollide( c0, [c1], [interpolation], [fadein], [fadeout] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `c0` | `number` | 否 | Collide (0.0 - 1.0) |
| `c1` | `number` | 是 | End collide (0.0 - 1.0) |
| `interpolation` | `string` | 是 | Interpolation method: linear, smooth, easein, easeout or constant. Default is linear. |
| `fadein` | `number` | 是 | Fade in between t=0 and t=fadein. Default is zero. |
| `fadeout` | `number` | 是 | Fade out between t=fadeout and t=1. Default is one. |

示例：

```lua
function client.init()
	--Disable collisions
	ParticleCollide(0)

	--Enable collisions over time
	ParticleCollide(0, 1)

	--Ramp up collisions very quickly, only skipping the first 5% of lifetime
	ParticleCollide(1, 1, "constant", 0.05)
end
```


### ParticleFlags

```lua
ParticleFlags( bitmask )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bitmask` | `number` | 否 | Particle flags (bitmask 0-65535) |

示例：

```lua
function client.tick()
	--Fire extinguishing particle
	ParticleFlags(256)
	SpawnParticle(Vec(0, 10, 0), -0.1, math.random() + 1)
end
```


### SpawnParticle

```lua
SpawnParticle( pos, velocity, lifetime )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `pos` | `TVec` | 否 | World space point as vector |
| `velocity` | `TVec` | 否 | World space velocity as vector |
| `lifetime` | `number` | 否 | Particle lifetime in seconds |

示例：

```lua
function client.tick()
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0.7, 0.6, 0.5)
	--Spawn particle at world origo with upwards velocity and a lifetime of ten seconds
	SpawnParticle(Vec(0, 5, 0), Vec(0, 1, 0), 10.0)
end
```



---

## Spawn

<b>3 个函数</b>

### Spawn

```lua
entities = Spawn( xml, transform, [allowStatic], [jointExisting] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `xml` | `string` | 否 | File name or xml string |
| `transform` | `TTransform` | 否 | Spawn transform |
| `allowStatic` | `boolean` | 是 | Allow spawning static shapes and bodies (default false) |
| `jointExisting` | `boolean` | 是 | Allow joints to connect to existing scene geometry (default false) |

**返回**：`entities`: table（Indexed table with handles to all spawned entities）

示例：

```lua
function server.init()
	Spawn("MOD/prefab/mycar.xml", Transform(Vec(0, 5, 0)))
	Spawn("<voxbox size='10 10 10' prop='true' material='wood'/>", Transform(Vec(0, 10, 0)))
end
```


### SpawnLayer

```lua
entities = SpawnLayer( xml, layer, transform, [allowStatic], [jointExisting] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `xml` | `string` | 否 | File name or xml string |
| `layer` | `string` | 否 | Vox layer name |
| `transform` | `TTransform` | 否 | Spawn transform |
| `allowStatic` | `boolean` | 是 | Allow spawning static shapes and bodies (default false) |
| `jointExisting` | `boolean` | 是 | Allow joints to connect to existing scene geometry (default false) |

**返回**：`entities`: table（Indexed table with handles to all spawned entities）

示例：

```lua
function server.init()
	Spawn("MOD/prefab/mycar.xml", "some_vox_layer", Transform(Vec(0, 5, 0)))
	Spawn("<voxbox size='10 10 10' prop='true' material='wood'/>", "some_vox_layer", Transform(Vec(0, 10, 0)))
end
```


### SpawnTool

```lua
entities = SpawnTool( id, transform, [allowStatic], [voxScale] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 否 | Tool ID |
| `transform` | `TTransform` | 否 | Spawn transform |
| `allowStatic` | `boolean` | 是 | Allow spawning static shapes and bodies (default false) |
| `voxScale` | `number` | 是 | Applies a scale to voxels (default 1.0) |

**返回**：`entities`: table（Indexed table with handles to all spawned entities）

示例：

```lua
function server.init()
	SpawnTool("sledge", Transform(Vec(0, 5, 0)))
end
```



---

## Miscellaneous

<b>54 个函数</b>

### AddMapMarker

```lua
AddMapMarker( id, tag, name, category, showLabelOnMap, info, pos, color, [infoImage], [dotIcon] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `number` | 否 | An id to identify the marker, typically player ID or body ID. |
| `tag` | `string` | 否 | A tag to help distinguish markers. |
| `name` | `string` | 否 | Name of the marker. |
| `category` | `string` | 否 | Used to group markers together in map target list. |
| `showLabelOnMap` | `bool` | 否 | name label will be shown on map if true |
| `info` | `string` | 否 | Additional information about the marker, displayed when selected. |
| `pos` | `Vec` | 否 | The world position of the marker. |
| `color` | `Vec` | 否 | The color of the marker, as a Vec table (e.g. Vec(1, 0, 0) for red) |
| `infoImage` | `string` | 是 | Path to the image to be displayed in the info section. |
| `dotIcon` | `string` | 是 | Path to the image used to represent the marker on map. |

示例：

```lua
function client.tick()
	AddMapMarker(1, "bonusTarget", "Bonus Target", "One of a kind", Vec(30, 40, 50), Vec(1,0,0), "MOD/gfx/bonus_info.png", "MOD/gfx/bonus_icon.png")
end
```


### SelectedMapMarker

```lua
id, tag = SelectedMapMarker(  )  -- client only
```

**返回**：`id`: number（id of map marker that was selected this tick.）；`tag`: string（the corresponding tag.）

示例：

```lua
function client.tick()
	AddMapMarker(1, "bonusTarget", "Bonus Target", "One of a kind", Vec(30, 40, 50), Vec(1,0,0), "MOD/gfx/bonus_info.png", "MOD/gfx/bonus_icon.png")

	local id, tag = SelectedMapMarker()

	if id == 1 and tag == "bonusTarget" then
		DebugPrint("You selected the Bonus Target on the map!")
	end
end
```


### Shoot

```lua
Shoot( origin, direction, [type], [strength], [maxDist], [playerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Origin in world space as vector |
| `direction` | `TVec` | 否 | Unit length direction as world space vector |
| `type` | `string` | 是 | Shot type, see description, default is 'bullet' |
| `strength` | `number` | 是 | Strength scaling, default is 1.0 |
| `maxDist` | `number` | 是 | Maximum distance, default is 100.0 |
| `playerId` | `number` | 是 | Instigating player. Can be skipped for non-player shots (helicopters etc.) |

示例：

```lua
function server.tick()
	Shoot(Vec(0, 10, 0), Vec(0, -1, 0), "shotgun")
end
```


### Paint

```lua
Paint( origin, radius, [type], [probability] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Origin in world space as vector |
| `radius` | `number` | 否 | Affected radius, in range 0.0 to 5.0 |
| `type` | `string` | 是 | Paint type. Can be 'explosion' or 'spraycan'. Default is spraycan. |
| `probability` | `number` | 是 | Dithering probability between zero and one, default is 1.0 |

示例：

```lua
function server.tick()
	Paint(Vec(0, 2, 0), 5.0, "spraycan")
end
```


### PaintRGBA

```lua
PaintRGBA( origin, radius, red, green, blue, [alpha], [probability] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | Origin in world space as vector |
| `radius` | `number` | 否 | Affected radius, in range 0.0 to 5.0 |
| `red` | `number` | 否 | red color value, in range 0.0 to 1.0 |
| `green` | `number` | 否 | green color value, in range 0.0 to 1.0 |
| `blue` | `number` | 否 | blue color value, in range 0.0 to 1.0 |
| `alpha` | `number` | 是 | alpha channel value, in range 0.0 to 1.0 |
| `probability` | `number` | 是 | Dithering probability between zero and one, default is 1.0 |

示例：

```lua
function server.tick()
	PaintRGBA(Vec(0, 5, 0), 5.5, 1.0, 0.0, 0.0)
end
```


### MakeHole

```lua
count = MakeHole( position, r0, [r1], [r2], [silent] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `position` | `TVec` | 否 | Hole center point |
| `r0` | `number` | 否 | Hole radius for soft materials |
| `r1` | `number` | 是 | Hole radius for medium materials. May not be bigger than r0. Default zero. |
| `r2` | `number` | 是 | Hole radius for hard materials. May not be bigger than r1. Default zero. |
| `silent` | `boolean` | 是 | Make hole without playing any break sounds. |

**返回**：`count`: number（Number of voxels that was cut out. This will be zero if there were no changes to any shape.）

示例：

```lua
function server.init()
	MakeHole(Vec(0, 0, 0), 5.0, 1.0)
end
```


### Explosion

```lua
Explosion( pos, size, [instigatingPlayerId] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `pos` | `TVec` | 否 | Position in world space as vector |
| `size` | `number` | 否 | Explosion size from 0.5 to 4.0 |
| `instigatingPlayerId` | `number` | 是 | Instigating player ID. |

示例：

```lua
function server.init()
	Explosion(Vec(0, 5, 0), 1)
end
```


### SpawnFire

```lua
SpawnFire( pos )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `pos` | `TVec` | 否 | Position in world space as vector |

示例：

```lua
function server.tick()
	SpawnFire(Vec(0, 2, 0))
end
```


### GetFireCount

```lua
count = GetFireCount(  )
```

**返回**：`count`: number（Number of active fires in level）

示例：

```lua
function client.tick()
	local c = GetFireCount()
	DebugPrint("Fire count " .. c)
end
```


### QueryClosestFire

```lua
hit, pos = QueryClosestFire( origin, maxDist )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `origin` | `TVec` | 否 | World space position as vector |
| `maxDist` | `number` | 否 | Maximum search distance |

**返回**：`hit`: boolean（A fire was found within search distance）；`pos`: TVec（Position of closest fire）

示例：

```lua
function client.tick()
	local hit, pos = QueryClosestFire(GetPlayerTransform().pos, 5.0)
	if hit then
		--There is a fire within 5 meters to the player. Mark it with a debug cross.
		DebugCross(pos)
	end
end
```


### QueryAabbFireCount

```lua
count = QueryAabbFireCount( min, max )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `min` | `TVec` | 否 | Aabb minimum point |
| `max` | `TVec` | 否 | Aabb maximum point |

**返回**：`count`: number（Number of active fires in bounding box）

示例：

```lua
function client.tick()
	local count = QueryAabbFireCount(Vec(0,0,0), Vec(10,10,10))
	DebugPrint(count)
end
```


### RemoveAabbFires

```lua
count = RemoveAabbFires( min, max )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `min` | `TVec` | 否 | Aabb minimum point |
| `max` | `TVec` | 否 | Aabb maximum point |

**返回**：`count`: number（Number of fires removed）

示例：

```lua
function server.tick()
	local removedCount= RemoveAabbFires(Vec(0,0,0), Vec(10,10,10))
	DebugPrint(removedCount)
end
```


### GetCameraTransform

```lua
transform = GetCameraTransform(  )  -- client only
```

**返回**：`transform`: TTransform（Current camera transform）

示例：

```lua
function client.tick()
	local t = GetCameraTransform()
	DebugPrint(TransformStr(t))
end
```


### SetCameraTransform

```lua
SetCameraTransform( transform, [fov] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Desired camera transform |
| `fov` | `number` | 是 | Optional horizontal field of view in degrees (default: 90) |

示例：

```lua
function client.tick()
	SetCameraTransform(Transform(Vec(0, 10, 0), QuatEuler(0, 90, 0)))
end
```


### RequestFirstPerson

```lua
RequestFirstPerson( transition )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transition` | `boolean` | 否 | Use transition |

示例：

```lua
function client.tick()
	if useViewFinder then
		RequestFirstPerson(true)
	end
end

function client.draw()
	if useViewFinder and !GetBool("game.thirdperson") then
		-- Draw view finder overlay
	end
end
```


### RequestThirdPerson

```lua
RequestThirdPerson( transition )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transition` | `boolean` | 否 | Use transition |

示例：

```lua
function client.tick()
	if useThirdPerson then
		RequestThirdPerson(true)
	end
end
```


### SetCameraOffsetTransform

```lua
SetCameraOffsetTransform( transform, [stackable] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | Desired camera offset transform |
| `stackable` | `boolean` | 是 | True if camera offset should summ up with multiple calls per tick |

示例：

```lua
function client.tick()
	local tPosX = Transform(Vec(math.sin(GetTime()*3.0) * 0.2, 0, 0))
	local tPosY = Transform(Vec(0, math.cos(GetTime()*3.0) * 0.2, 0), QuatAxisAngle(Vec(0, 0, 0)))

	SetCameraOffsetTransform(tPosX, true)
	SetCameraOffsetTransform(tPosY, true)
end
```


### AttachCameraTo

```lua
AttachCameraTo( handle, [ignoreRotation] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `number` | 否 | Body or shape handle |
| `ignoreRotation` | `boolean` | 是 | True to ignore rotation and use position only, false to use full transform |

示例：

```lua
function client.tick()
	local vehicle = GetPlayerVehicle()
	if vehicle ~= 0 then
		AttachCameraTo(GetVehicleBody(vehicle))
		SetCameraOffsetTransform(Transform(Vec(1, 2, 3)))
	end
end
```


### SetPivotClipBody

```lua
SetPivotClipBody( bodyHandle, mainShapeIdx )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `bodyHandle` | `number` | 否 | Handle of a body, shapes of which should be |
| `mainShapeIdx` | `number` | 否 | Optional index of a shape among the given |

示例：

```lua
local body_1 = 0
local body_2 = 0
function client.init()
	body_1 = FindBody("body_1")
	body_2 = FindBody("body_2")
end

function client.tick()
	SetPivotClipBody(body_1, 0) -- this overload should be called once and
	-- only once per frame to take effect
	SetPivotClipBody(body_2)
end
```


### ShakeCamera

```lua
ShakeCamera( strength )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `strength` | `number` | 否 | Normalized strength of shaking |

示例：

```lua
function client.tick()
	ShakeCamera(0.5)
end
```


### SetCameraFov

```lua
SetCameraFov( degrees )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `degrees` | `number` | 否 | Horizontal field of view in degrees (10-170) |

示例：

```lua
function client.tick()
	SetCameraFov(60)
end
```


### SetCameraDof

```lua
SetCameraDof( distance, [amount] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `distance` | `number` | 否 | Depth of field distance |
| `amount` | `number` | 是 | Optional amount of blur (default 1.0) |

示例：

```lua
function client.tick()
	--Set depth of field to 10 meters
	SetCameraDof(10)
end
```


### DisableMotionBlur

```lua
DisableMotionBlur(  )  -- client only
```

示例：

```lua
function client.tick()
	--Disable motion blur to improve readability of certain game play elements.
	DisableMotionBlur()
end
```


### SetLowHealthBlurThreshold

```lua
SetLowHealthBlurThreshold( health )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `health` | `number` | 否 | health value where anything lower results in blurred vision |

示例：

```lua
function client.tick()
	-- Don't show the blurry vision until the player's health drops below 0.4
	SetLowHealthBlurThreshold(0.4)
end
```


### PointLight

```lua
PointLight( pos, r, g, b, [intensity] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `pos` | `TVec` | 否 | World space light position |
| `r` | `number` | 否 | Red |
| `g` | `number` | 否 | Green |
| `b` | `number` | 否 | Blue |
| `intensity` | `number` | 是 | Intensity. Default is 1.0. |

示例：

```lua
function client.tick()
	--Pulsating, yellow light above world origo
	local intensity = 3 + math.sin(GetTime())
	PointLight(Vec(0, 5, 0), 1, 1, 0, intensity)
end
```


### SetTimeScale

```lua
SetTimeScale( scale )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `scale` | `number` | 否 | Time scale 0.0 to 2.0 |

示例：

```lua
function server.tick()
	--Slow down time when holding down a key
	if InputDown('t', hostPlayerId) then
		SetTimeScale(0.2)
	end
end
```


### SetEnvironmentDefault

```lua
SetEnvironmentDefault(  )  -- server only
```

示例：

```lua
function server.init()
	SetEnvironmentDefault()
end
```


### SetEnvironmentProperty

```lua
SetEnvironmentProperty( name, value0, [value1], [value2], [value3] )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Property name |
| `value0` | `any` | 否 | Property value (type depends on property) |
| `value1` | `any` | 是 | Extra property value (only some properties) |
| `value2` | `any` | 是 | Extra property value (only some properties) |
| `value3` | `any` | 是 | Extra property value (only some properties) |

示例：

```lua
function server.init()
	SetEnvironmentDefault()
	SetEnvironmentProperty("skybox", "cloudy.dds")
	SetEnvironmentProperty("rain", 0.7)
	SetEnvironmentProperty("fogcolor", 0.5, 0.5, 0.8)
	SetEnvironmentProperty("nightlight", false)
end
```


### GetEnvironmentProperty

```lua
value0, value1, value2, value3, value4 = GetEnvironmentProperty( name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Property name |

**返回**：`value0`: any（Property value (type depends on property)）；`value1`: any（Property value (only some properties)）；`value2`: any（Property value (only some properties)）；`value3`: any（Property value (only some properties)）；`value4`: any（Property value (only some properties)）

示例：

```lua
function client.init()
	local skyboxPath = GetEnvironmentProperty("skybox")
	local rainValue = GetEnvironmentProperty("rain")
	local r,g,b = GetEnvironmentProperty("fogcolor")
	local enabled = GetEnvironmentProperty("nightlight")
	DebugPrint(skyboxPath)
	DebugPrint(rainValue)
	DebugPrint(r .. " " .. g .. " " .. b)
	DebugPrint(enabled)
end
```


### SetPostProcessingDefault

```lua
SetPostProcessingDefault(  )
```

示例：

```lua
function client.tick()
	SetPostProcessingProperty("saturation", 0.4)
	SetPostProcessingProperty("colorbalance", 1.3, 1.0, 0.7)
	SetPostProcessingDefault()
end
```


### SetPostProcessingProperty

```lua
SetPostProcessingProperty( name, value0, [value1], [value2] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Property name |
| `value0` | `number` | 否 | Property value |
| `value1` | `number` | 是 | Extra property value (only some properties) |
| `value2` | `number` | 是 | Extra property value (only some properties) |

示例：

```lua
--Sepia post processing
function client.tick()
	SetPostProcessingProperty("saturation", 0.4)
	SetPostProcessingProperty("colorbalance", 1.3, 1.0, 0.7)
end
```


### GetPostProcessingProperty

```lua
value0, value1, value2 = GetPostProcessingProperty( name )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Property name |

**返回**：`value0`: number（Property value）；`value1`: number（Property value (only some properties)）；`value2`: number（Property value (only some properties)）

示例：

```lua
function client.tick()
	SetPostProcessingProperty("saturation", 0.4)
	SetPostProcessingProperty("colorbalance", 1.3, 1.0, 0.7)
	local saturation = GetPostProcessingProperty("saturation")
	local r,g,b = GetPostProcessingProperty("colorbalance")
	DebugPrint("saturation " .. saturation)
	DebugPrint("colorbalance " .. r .. " " .. g .. " " .. b)
end
```


### DrawLine

```lua
DrawLine( p0, p1, [r], [g], [b], [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `p0` | `TVec` | 否 | World space point as vector |
| `p1` | `TVec` | 否 | World space point as vector |
| `r` | `number` | 是 | Red |
| `g` | `number` | 是 | Green |
| `b` | `number` | 是 | Blue |
| `a` | `number` | 是 | Alpha |

示例：

```lua
function server.tick()
	--Draw white debug line
	DrawLine(Vec(0, 0, 0), Vec(-10, 5, -10))

	--Draw red debug line
	DrawLine(Vec(0, 0, 0), Vec(10, 5, 10), 1, 0, 0)
end

-- Or

function client.tick()
	--Draw white debug line
	DrawLine(Vec(0, 0, 0), Vec(-10, 5, -10))

	--Draw red debug line
	DrawLine(Vec(0, 0, 0), Vec(10, 5, 10), 1, 0, 0)
end
```


### DebugLine

```lua
DebugLine( p0, p1, [r], [g], [b], [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `p0` | `TVec` | 否 | World space point as vector |
| `p1` | `TVec` | 否 | World space point as vector |
| `r` | `number` | 是 | Red |
| `g` | `number` | 是 | Green |
| `b` | `number` | 是 | Blue |
| `a` | `number` | 是 | Alpha |

示例：

```lua
function server.tick()
	--Draw white debug line
	DebugLine(Vec(0, 0, 0), Vec(-10, 5, -10))

	--Draw red debug line
	DebugLine(Vec(0, 0, 0), Vec(10, 5, 10), 1, 0, 0)
end

-- Or

function client.tick()
	--Draw white debug line
	DebugLine(Vec(0, 0, 0), Vec(-10, 5, -10))

	--Draw red debug line
	DebugLine(Vec(0, 0, 0), Vec(10, 5, 10), 1, 0, 0)
end
```


### DebugCross

```lua
DebugCross( p0, [r], [g], [b], [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `p0` | `TVec` | 否 | World space point as vector |
| `r` | `number` | 是 | Red |
| `g` | `number` | 是 | Green |
| `b` | `number` | 是 | Blue |
| `a` | `number` | 是 | Alpha |

示例：

```lua
function server.tick()
	DebugCross(Vec(10, 5, 5))
end
-- Or
function client.tick()
	DebugCross(Vec(10, 5, 5))
end
```


### DebugTransform

```lua
DebugTransform( transform, [scale] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `transform` | `TTransform` | 否 | The transform |
| `scale` | `number` | 是 | Length of the axis |

示例：

```lua
function server.tick()
	DebugTransform(GetPlayerCameraTransform(), 0.5)
end
-- Or
function client.tick()
	DebugTransform(GetPlayerCameraTransform(), 0.5)
end
```


### DebugWatch

```lua
DebugWatch( name, value, [lineWrapping] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | Name |
| `value` | `any` | 否 | Value |
| `lineWrapping` | `boolean` | 是 | True if you need to wrap Table lines. Works only with tables. |

示例：

```lua
function client.tick()
	DebugWatch("Player camera transform", GetPlayerCameraTransform())

	local anyTable = {
		"teardown",
		{
			name = "Alex",
			age = 25,
			child = { name = "Lena" }
		},
		nil,
		version = "1.6.0",
		true
	}
	DebugWatch("table", anyTable);
end
```


### DebugPrint

```lua
DebugPrint( message, [lineWrapping] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `message` | `string` | 否 | Message to display |
| `lineWrapping` | `boolean` | 是 | True if you need to wrap Table lines. Works only with tables. |

示例：

```lua
function client.init()
	DebugPrint("time")

	DebugPrint(GetPlayerCameraTransform())

	local anyTable = {
		"teardown",
		{
			name = "Alex",
			age = 25,
			child = { name = "Lena" }
		},
		nil,
		version = "1.6.0",
		true,
	}
	DebugPrint(anyTable)
end
```


### RegisterListenerTo

```lua
RegisterListenerTo( eventName, listenerFunction )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `eventName` | `string` | 否 | Event name |
| `listenerFunction` | `string` | 否 | Listener function name |

示例：

```lua
function onLangauageChanged()
	DebugPrint("langauageChanged")
end

function client.init()
	RegisterListenerTo("LanguageChanged", "onLangauageChanged")
	TriggerEvent("LanguageChanged")
end
```


### UnregisterListener

```lua
UnregisterListener( eventName, listenerFunction )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `eventName` | `string` | 否 | Event name |
| `listenerFunction` | `string` | 否 | Listener function name |

示例：

```lua
function onLangauageChanged()
	DebugPrint("langauageChanged")
end

function client.init()
	RegisterListenerTo("LanguageChanged", "onLangauageChanged")
	UnregisterListener("LanguageChanged", "onLangauageChanged")
	TriggerEvent("LanguageChanged")
end
```


### TriggerEvent

```lua
TriggerEvent( eventName, [args] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `eventName` | `string` | 否 | Event name |
| `args` | `string` | 是 | Event parameters |

示例：

```lua
function onLangauageChanged()
	DebugPrint("langauageChanged")
end

function client.init()
	RegisterListenerTo("LanguageChanged", "onLangauageChanged")
	UnregisterListener("LanguageChanged", "onLangauageChanged")
	TriggerEvent("LanguageChanged")
end
```


### LoadHaptic

```lua
handle = LoadHaptic( filepath )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `filepath` | `string` | 否 | Path to Haptic effect to play |

**返回**：`handle`: string（Haptic effect handle）

示例：

```lua
-- Rumble with gun Haptic effect
function client.init()
	haptic_effect = LoadHaptic("haptic/gun_fire.xml")
end

function client.tick()
	if trigHaptic then
		PlayHaptic(haptic_effect, 1)
	end
end
```


### CreateHaptic

```lua
handle = CreateHaptic( leftMotorRumble, rightMotorRumble, leftTriggerRumble, rightTriggerRumble )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `leftMotorRumble` | `number` | 否 | Amount of rumble for left motor |
| `rightMotorRumble` | `number` | 否 | Amount of rumble for right motor |
| `leftTriggerRumble` | `number` | 否 | Amount of rumble for left trigger |
| `rightTriggerRumble` | `number` | 否 | Amount of rumble for right trigger |

**返回**：`handle`: string（Haptic effect handle）

示例：

```lua
-- Rumble with gun Haptic effect
function client.init()
	haptic_effect = CreateHaptic(1, 1, 0, 0)
end

function client.tick()
	if trigHaptic then
		PlayHaptic(haptic_effect, 1)
	end
end
```


### PlayHaptic

```lua
PlayHaptic( handle, amplitude )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `string` | 否 | Handle of haptic effect |
| `amplitude` | `number` | 否 | Amplidute used for calculation of Haptic effect. |

示例：

```lua
-- Rumble with gun Haptic effect
function client.init()
	haptic_effect = LoadHaptic("haptic/gun_fire.xml")
end

function client.tick()
	if trigHaptic then
		PlayHaptic(haptic_effect, 1)
	end
end
```


### PlayHapticDirectional

```lua
PlayHapticDirectional( handle, direction, amplitude )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `string` | 否 | Handle of haptic effect |
| `direction` | `TVec` | 否 | Direction in which effect must be played |
| `amplitude` | `number` | 否 | Amplidute used for calculation of Haptic effect. |

示例：

```lua
-- Rumble with gun Haptic effect
local haptic_effect
function client.init()
	haptic_effect = LoadHaptic("haptic/gun_fire.xml")
end

function client.tick()
	if InputPressed("interact") then
		PlayHapticDirectional(haptic_effect, Vec(-1, 0, 0), 1)
	end
end
```


### HapticIsPlaying

```lua
flag = HapticIsPlaying( handle )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `string` | 否 | Handle of haptic effect |

**返回**：`flag`: boolean（is current Haptic playing or not）

示例：

```lua
-- Rumble infinitely
local haptic_effect
function client.init()
	haptic_effect = LoadHaptic("haptic/gun_fire.xml")
end

function client.tick()
	if not HapticIsPlaying(haptic_effect) then
		PlayHaptic(haptic_effect, 1)
	end
end
```


### SetToolHaptic

```lua
SetToolHaptic( id, handle, [amplitude] )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 否 | Tool unique identifier |
| `handle` | `string` | 否 | Handle of haptic effect |
| `amplitude` | `number` | 是 | Amplitude multiplier. Default (1.0) |

示例：

```lua
function client.init()
	RegisterTool("minigun", "loc@MINIGUN", "MOD/vox/minigun.vox")
	toolHaptic = LoadHaptic("MOD/haptic/tool.xml")
	SetToolHaptic("minigun", toolHaptic)
end
```


### StopHaptic

```lua
StopHaptic( handle )  -- client only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `handle` | `string` | 否 | Handle of haptic effect |

示例：

```lua
-- Rumble infinitely
local haptic_effect
function client.init()
	haptic_effect = LoadHaptic("haptic/gun_fire.xml")
end

function client.tick()
    if InputDown("interact") then
        StopHaptic(haptic_effect)
    elseif not HapticIsPlaying(haptic_effect) then
		PlayHaptic(haptic_effect, 1)
    end
end
```


### AddHeat

```lua
AddHeat( shape, pos, amount )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `shape` | `number` | 否 | Shape handle |
| `pos` | `TVec` | 否 | World space point as vector |
| `amount` | `number` | 否 | amount of heat |

示例：

```lua
function server.tick(dt)
	if InputDown("usetool") then
		local playerCameraTransform = GetPlayerCameraTransform()
		local dir = TransformToParentVec(playerCameraTransform, Vec(0, 0, -1))

		-- Cast ray out of player camera and add heat to shape if we can find one
		local hit, dist, normal, shape = QueryRaycast(playerCameraTransform.pos, dir, 50)

		if hit then
			local hitPos = VecAdd(playerCameraTransform.pos, VecScale(dir, dist))
			AddHeat(shape, hitPos, 2 * dt)
		end

		DrawLine(VecAdd(playerCameraTransform.pos, Vec(0.5, 0, 0)), VecAdd(playerCameraTransform.pos, VecScale(dir, dist)), 1, 0, 0, 1)
	end
end
```


### GetBoundaryArea

```lua
area = GetBoundaryArea(  )
```

**返回**：`area`: Number（Number representing the area of the boundary.）

示例：

```lua
function GenerateRandomPointInLevel()
	aabbMin, aabbMax = GetBoundaryBounds()
	local x = GetRandomFloat(aabbMin[1], aabbMax[1])
	local z = GetRandomFloat(aabbMin[3], aabbMax[3])
	return x,z
end
```


### GetBoundaryBounds

```lua
min, max = GetBoundaryBounds(  )
```

**返回**：`min`: Vec（Vector representing the AABB lower bound）；`max`: Vec（Vector representing the AABB upper bound）

示例：

```lua
function GenerateRandomPointInLevel()
	aabbMin, aabbMax = GetBoundaryBounds()
	local x = GetRandomFloat(aabbMin[1], aabbMax[1])
	local z = GetRandomFloat(aabbMin[3], aabbMax[3])
	return x,z
end
```


### GetGravity

```lua
vector = GetGravity(  )
```

**返回**：`vector`: TVec（Gravity vector）

示例：

```lua
function client.tick()
	DebugPrint(VecStr(GetGravity()))
end
```


### SetGravity

```lua
SetGravity( vec )  -- server only
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `vec` | `TVec` | 否 | Gravity vector |

示例：

```lua
local isMoonGravityEnabled = false

function server.tick()
	if InputPressed("g", hostPlayerId) then
		isMoonGravityEnabled = not isMoonGravityEnabled
		if isMoonGravityEnabled then
			SetGravity(Vec(0, -1.6, 0))
		else
			SetGravity(Vec(0, -10.0, 0))
		end
	end
end
```


### GetFps

```lua
fps = GetFps(  )
```

**返回**：`fps`: number（Frames per second）

示例：

```lua
function client.tick()
	DebugWatch("fps", GetFps())
end
```



---

## User Interface

<b>99 个函数</b>

### UiMakeInteractive

```lua
UiMakeInteractive(  )
```

示例：

```lua
UiMakeInteractive()
```


### UiPush

```lua
UiPush(  )
```

示例：

```lua
UiColor(1,0,0)
UiText("Red")
UiPush()
	UiColor(0,1,0)
	UiText("Green")
UiPop()
UiText("Red")
```


### UiPop

```lua
UiPop(  )
```

示例：

```lua
UiColor(1,0,0)
UiText("Red")
UiPush()
	UiColor(0,1,0)
	UiText("Green")
UiPop()
UiText("Red")
```


### UiWidth

```lua
width = UiWidth(  )
```

**返回**：`width`: number（Width of draw context）

示例：

```lua
local w = UiWidth()
```


### UiHeight

```lua
height = UiHeight(  )
```

**返回**：`height`: number（Height of draw context）

示例：

```lua
local h = UiHeight()
```


### UiCenter

```lua
center = UiCenter(  )
```

**返回**：`center`: number（Half width of draw context）

示例：

```lua
local c = UiCenter()
--Same as
local c = UiWidth()/2
```


### UiMiddle

```lua
middle = UiMiddle(  )
```

**返回**：`middle`: number（Half height of draw context）

示例：

```lua
local m = UiMiddle()
--Same as
local m = UiHeight()/2
```


### UiColor

```lua
UiColor( r, g, b, [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red channel |
| `g` | `number` | 否 | Green channel |
| `b` | `number` | 否 | Blue channel |
| `a` | `number` | 是 | Alpha channel. Default 1.0 |

示例：

```lua
--Set color yellow
UiColor(1,1,0)
```


### UiColorFilter

```lua
UiColorFilter( r, g, b, [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red channel |
| `g` | `number` | 否 | Green channel |
| `b` | `number` | 否 | Blue channel |
| `a` | `number` | 是 | Alpha channel. Default 1.0 |

示例：

```lua
UiPush()
	--Draw menu in transparent, yellow color tint
	UiColorFilter(1, 1, 0, 0.5)
	drawMenu()
UiPop()
```


### UiResetColor

```lua
UiResetColor(  )
```

示例：

```lua
function client.draw()
	UiPush()
        UiFont("bold.ttf", 44)
		UiTranslate(100, 100)
		UiColor(1, 0, 0)
		UiText("A")
		UiTranslate(100, 0)
		UiResetColor()
		UiText("B")
	UiPop()
end
```


### UiTranslate

```lua
UiTranslate( x, y )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 否 | X component |
| `y` | `number` | 否 | Y component |

示例：

```lua
UiPush()
	UiTranslate(100, 0)
	UiText("Indented")
UiPop()
```


### UiRotate

```lua
UiRotate( angle )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `angle` | `number` | 否 | Angle in degrees, counter clockwise |

示例：

```lua
UiPush()
	UiRotate(45)
	UiText("Rotated")
UiPop()
```


### UiScale

```lua
UiScale( x, [y] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 否 | X component |
| `y` | `number` | 是 | Y component. Default value is x. |

示例：

```lua
UiPush()
	UiScale(2)
	UiText("Double size")
UiPop()
```


### UiGetScale

```lua
x, y = UiGetScale(  )
```

**返回**：`x`: number（X scale）；`y`: number（Y scale）

示例：

```lua
function client.draw()
	UiPush()
		UiScale(2)
		x, y = UiGetScale()
		DebugPrint(x .. " " .. y)
	UiPop()
end
```


### UiClipRect

```lua
UiClipRect( width, height, [inherit] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Rect width |
| `height` | `number` | 否 | Rect height |
| `inherit` | `boolean` | 是 | True if must include the parent's clip rect |

示例：

```lua
function client.draw()
    UiTranslate(200, 200)
    UiPush()
        UiClipRect(100, 50)
        UiTranslate(5, 15)
        UiFont("regular.ttf", 50)
        UiText("Text")
    UiPop()
end
```


### UiWindow

```lua
UiWindow( width, height, [clip], [inherit] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Window width |
| `height` | `number` | 否 | Window height |
| `clip` | `boolean` | 是 | Clip content outside window. Default is false. |
| `inherit` | `boolean` | 是 | Inherit current clip region (for nested clip regions) |

示例：

```lua
UiPush()
	UiWindow(400, 200)
	local w = UiWidth()
	--w is now 400
UiPop()
```


### UiGetCurrentWindow

```lua
tl_x, tl_y, br_x, br_y = UiGetCurrentWindow(  )
```

**返回**：`tl_x`: number（Top left x）；`tl_y`: number（Top left y）；`br_x`: number（Bottom right x）；`br_y`: number（Bottom right y）

示例：

```lua
function client.draw()
	UiPush()
		UiWindow(400, 200)
		tl_x, tl_y, br_x, br_y = UiGetCurrentWindow()
		-- do something
	UiPop()
end
```


### UiIsInCurrentWindow

```lua
val = UiIsInCurrentWindow( x, y )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 否 | X |
| `y` | `number` | 否 | Y |

**返回**：`val`: boolean（True if）

示例：

```lua
function client.draw()
	UiPush()
		UiWindow(400, 200)
		DebugPrint("point 1: " .. tostring(UiIsInCurrentWindow(200, 100)))
        DebugPrint("point 2: " .. tostring(UiIsInCurrentWindow(450, 100)))
	UiPop()
end
```


### UiIsRectFullyClipped

```lua
value = UiIsRectFullyClipped( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Width |
| `h` | `number` | 否 | Height |

**返回**：`value`: boolean（True if rect is fully clipped）

示例：

```lua
function client.draw()
    UiTranslate(200, 200)
    UiPush()
        UiClipRect(150, 150)
        UiColor(1.0, 1.0, 1.0, 0.15)
        UiRect(150, 150)
        UiRect(w, h)
        UiTranslate(-50, 30)
        UiColor(1, 0, 0)
        local w, h = 100, 100
        UiRect(w, h)
        DebugPrint(UiIsRectFullyClipped(w, h))
    UiPop()
end
```


### UiIsInClipRegion

```lua
value = UiIsInClipRegion( x, y )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 否 | X |
| `y` | `number` | 否 | Y |

**返回**：`value`: boolean（True if point is in clip region）

示例：

```lua
function client.draw()
    UiPush()
        UiTranslate(200, 200)
        UiClipRect(150, 150)
        UiColor(1.0, 1.0, 1.0, 0.15)
        UiRect(150, 150)
        UiRect(w, h)

        DebugPrint("point 1: " .. tostring(UiIsInClipRegion(250, 250)))
        DebugPrint("point 2: " .. tostring(UiIsInClipRegion(350, 250)))
    UiPop()
end
```


### UiIsFullyClipped

```lua
value = UiIsFullyClipped( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Width |
| `h` | `number` | 否 | Height |

**返回**：`value`: boolean（True if rect is not overlapping clip region）

示例：

```lua
function client.draw()
    UiPush()
        UiTranslate(200, 200)
        UiClipRect(150, 150)
        UiColor(1.0, 1.0, 1.0, 0.15)
        UiRect(150, 150)
        UiRect(w, h)

        DebugPrint("rect 1: " .. tostring(UiIsFullyClipped(200, 200)))
        UiTranslate(200, 0)
        DebugPrint("rect 2: " .. tostring(UiIsFullyClipped(200, 200)))
    UiPop()
end
```


### UiSafeMargins

```lua
x0, y0, x1, y1 = UiSafeMargins(  )
```

**返回**：`x0`: number（Left）；`y0`: number（Top）；`x1`: number（Right）；`y1`: number（Bottom）

示例：

```lua
function client.draw()
	local x0, y0, x1, y1 = UiSafeMargins()
	UiTranslate(x0, y0)
	UiWindow(x1-x0, y1-y0, true)
	--The drawing area is now 1920 by 1080 in the center of screen
	drawMenu()
end
```


### UiCanvasSize

```lua
value = UiCanvasSize(  )
```

**返回**：`value`: table（Canvas width and height）

示例：

```lua
function client.draw()
	UiPush()
        local canvas = UiCanvasSize()
        UiWindow(canvas.w, canvas.h)
        --[[
            ...
        ]]
	UiPop()
end
```


### UiAlign

```lua
UiAlign( alignment )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `alignment` | `string` | 否 | Alignment keywords |

| Alignment | Description |
| --- | --- |
| left | Horizontally align to the left |
| right | Horizontally align to the right |
| center | Horizontally align to the center |
| top | Vertically align to the top |
| bottom | Veritcally align to the bottom |
| middle | Vertically align to the middle |

示例：

```lua
UiAlign("left")
UiText("Aligned left at baseline")

UiAlign("center middle")
UiText("Fully centered")
```


### UiTextAlignment

```lua
UiTextAlignment( alignment )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `alignment` | `string` | 否 | Alignment keyword |

| Alignment | Description |
| --- | --- |
| left | Horizontally align to the left |
| right | Horizontally align to the right |
| center | Horizontally align to the center |

示例：

```lua
UiTextAlignment("left")
UiText("Aligned left at baseline")

UiTextAlignment("center")
UiText("Centered")
```


### UiModalBegin

```lua
UiModalBegin( [force] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `force` | `boolean` | 是 | Pass true if you need to increase the priority of this modal in the context |

示例：

```lua
UiModalBegin()
if UiTextButton("Okay") then
	--All other interactive ui elements except this one are disabled
end
UiModalEnd()

--This is also okay
UiPush()
	UiModalBegin()
	if UiTextButton("Okay") then
		--All other interactive ui elements except this one are disabled
	end
UiPop()
--No longer modal
```


### UiModalEnd

```lua
UiModalEnd(  )
```

示例：

```lua
UiModalBegin()
if UiTextButton("Okay") then
	--All other interactive ui elements except this one are disabled
end
UiModalEnd()
```


### UiDisableInput

```lua
UiDisableInput(  )
```

示例：

```lua
UiPush()
	UiDisableInput()
	if UiTextButton("Okay") then
		--Will never happen
	end
UiPop()
```


### UiEnableInput

```lua
UiEnableInput(  )
```

示例：

```lua
UiDisableInput()
if UiTextButton("Okay") then
	--Will never happen
end

UiEnableInput()
if UiTextButton("Okay") then
	--This can happen
end
```


### UiReceivesInput

```lua
receives = UiReceivesInput(  )
```

**返回**：`receives`: boolean（True if current context receives input）

示例：

```lua
if UiReceivesInput() then
	highlightItemAtMousePointer()
end
```


### UiGetMousePos

```lua
x, y = UiGetMousePos(  )
```

**返回**：`x`: number（X coordinate）；`y`: number（Y coordinate）

示例：

```lua
local x, y = UiGetMousePos()
```


### UiGetCanvasMousePos

```lua
x, y = UiGetCanvasMousePos(  )
```

**返回**：`x`: number（X coordinate）；`y`: number（Y coordinate）

示例：

```lua
function client.draw()
	local x, y = UiGetCanvasMousePos()
	DebugPrint("x :" .. x .. " y:" .. y)
end
```


### UiIsMouseInRect

```lua
inside = UiIsMouseInRect( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Width |
| `h` | `number` | 否 | Height |

**返回**：`inside`: boolean（True if mouse pointer is within rectangle）

示例：

```lua
if UiIsMouseInRect(100, 100) then
	-- mouse pointer is in rectangle
end
```


### UiWorldToPixel

```lua
x, y, distance = UiWorldToPixel( point )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `point` | `TVec` | 否 | 3D world position as vector |

**返回**：`x`: number（X coordinate）；`y`: number（Y coordinate）；`distance`: number（Distance to point）

示例：

```lua
local x, y, dist = UiWorldToPixel(point)
if dist > 0 then
UiTranslate(x, y)
UiText("Label")
end
```


### UiPixelToWorld

```lua
direction = UiPixelToWorld( x, y )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `x` | `number` | 否 | X coordinate |
| `y` | `number` | 否 | Y coordinate |

**返回**：`direction`: TVec（3D world direction as vector）

示例：

```lua
UiMakeInteractive()
local x, y = UiGetMousePos()
local dir = UiPixelToWorld(x, y)
local pos = GetCameraTransform().pos
local hit, dist = QueryRaycast(pos, dir, 100)
if hit then
	DebugPrint("hit distance: " .. dist)
end
```


### UiGetCursorPos

```lua
UiGetCursorPos(  )
```

示例：

```lua
function client.draw()
    UiTranslate(100, 50)
    x, y = UiGetCursorPos()
    DebugPrint("x: " .. x .. "; y: " .. y)
end
```


### UiBlur

```lua
UiBlur( amount )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `amount` | `number` | 否 | Blur amount (0.0 to 1.0) |

示例：

```lua
UiBlur(1.0)
drawMenu()
```


### UiFont

```lua
UiFont( path, size )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to TTF font file |
| `size` | `number` | 否 | Font size (10 to 100) |

示例：

```lua
UiFont("bold.ttf", 24)
UiText("Hello")
```


### UiFontHeight

```lua
size = UiFontHeight(  )
```

**返回**：`size`: number（Font size）

示例：

```lua
local h = UiFontHeight()
```


### UiText

```lua
w, h, x, y, linkId = UiText( text, [move], [maxChars] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `text` | `string` | 否 | Print text at cursor location |
| `move` | `boolean` | 是 | Automatically move cursor vertically. Default false. |
| `maxChars` | `number` | 是 | Maximum amount of characters. Default 100000. |

**返回**：`w`: number（Width of text）；`h`: number（Height of text）；`x`: number（End x-position of text.）；`y`: number（End y-position of text.）；`linkId`: string（Link id of clicked link）

示例：

```lua
UiFont("bold.ttf", 24)
UiText("Hello")

...

--Automatically advance cursor
UiText("First line", true)
UiText("Second line", true)



--Using links
UiFont("bold.ttf", 26)
UiTranslate(100,100)
--Using virtual links
link = "[[link;label=loc@UI_TEXT_FREE_ROAM_OPTIONS_LINK_NAME;id=options/game;color=#DDDD7FDD;underline=true]]"
someText = "Some text with a link: " .. link .. " and some more text"

w, h, x, y, linkId = UiText(someText)
if linkId:len() ~= 0 then
	if linkId == "options/game" then
		DebugPrint(linkId.." link clicked")
	elseif linkId == "options/sound" then
		--Do something else
	end
end
UiTranslate(0,50)

--Using game links, id attribute is required, color is optional, same as virtual links
link = "[[game://options;label=loc@UI_TEXT_FREE_ROAM_OPTIONS_LINK_NAME;id=game;color=#DDDD7FDD;underline=false]]"
someText = "Some text with a link: " .. link .. " and some more text"
w, h, x, y, linkId = UiText(someText)
if linkId:len() ~= 0 then
	DebugPrint(linkId.." link clicked")
end
UiTranslate(0,50)

--Using http/s links is also possible, link will be opened in the default browser
link = "[[http://www.example.com;label=loc@SOME_KEY;]]"
someText = "Goto: " .. link
UiText(someText)
```


### UiTextDisableWildcards

```lua
UiTextDisableWildcards( disable )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `disable` | `boolean` | 否 | Enable or disable wildcard [[...]] substitution support in UiText |

示例：

```lua
UiFont("regular.ttf", 30)
UiPush()
	UiTextDisableWildcards(true)
	-- icon won't be embedded here, text will be left as is
	UiText("Text with embedded icon image [[menu:menu_accept;iconsize=42,42]]")
UiPop()

-- embedding works as expected
UiText("Text with embedded icon image [[menu:menu_accept;iconsize=42,42]]")
```


### UiTextUniformHeight

```lua
UiTextUniformHeight( uniform )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `uniform` | `boolean` | 否 | Enable or disable fixed line height for text rendering |

示例：

```lua
#include "script/common.lua"
enabled = false
group = 1
local desc = {
    {
        {"A mod desc without descenders"},
        {"Author: Abcd"},
        {"Tags: map, spawnable"},
    },
    {
        {"A mod with descenders, like g, j, p, q, y"},
        {"Author: Ggjyq"},
        {"Tags: map, spawnable"},
    },
}
-- Function to draw text with or without uniform line height
local function drawDescriptions()
    UiAlign("top")
    for _, text in ipairs(desc[group]) do
        UiTextUniformHeight(enabled)
        UiText(text[1], true)
    end
end

function client.draw()
    UiFont("regular.ttf", 22)
    UiTranslate(100, 100)

    UiPush()
        local r,g,b
        if enabled then
            r,g,b = 0,1,0
        else
            r,g,b = 1,0,0
        end
        UiColor(0,0,0)
        UiButtonImageBox("ui/common/box-solid-6.png", 6, 6, r,g,b)
        if UiTextButton("Uniform height "..(enabled and "enabled" or "disabled")) then
            enabled = not enabled
        end
        UiTranslate(0,35)
        if UiTextButton(">") then
            group = clamp(group + 1, 1, #desc)
        end
        UiTranslate(0,35)
        if UiTextButton("<") then
            group = clamp(group - 1, 1, #desc)
        end
    UiPop()
    UiTranslate(0,80)
    drawDescriptions()
end
```


### UiGetTextSize

```lua
w, h, x, y = UiGetTextSize( text )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `text` | `string` | 否 | A text string |

**返回**：`w`: number（Width of text）；`h`: number（Height of text）；`x`: number（Offset x-component of text AABB）；`y`: number（Offset y-component of text AABB）

示例：

```lua
local w, h = UiGetTextSize("Some text")
```


### UiMeasureText

```lua
w, h = UiMeasureText( space, text/locale )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `space` | `number` | 否 | Space between lines |
| `text/locale` | `string` | 否 | , ... A text strings |

**返回**：`w`: number（Width of biggest line）；`h`: number（Height of all lines combined with interval）

示例：

```lua
local w, h = UiMeasureText(0, "Some text", "loc@key")
```


### UiGetSymbolsCount

```lua
count = UiGetSymbolsCount( text )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `text` | `string` | 否 | Text |

**返回**：`count`: number（Symbols count）

示例：

```lua
function client.draw()
    DebugPrint(UiGetSymbolsCount("Hello world!"))
end
```


### UiTextSymbolsSub

```lua
substring = UiTextSymbolsSub( text, from, to )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `text` | `string` | 否 | Text |
| `from` | `number` | 否 | From element index |
| `to` | `number` | 否 | To element index |

**返回**：`substring`: string（Substring）

示例：

```lua
function client.draw()
    DebugPrint(UiTextSymbolsSub("Hello world", 1, 5))
end
```


### UiWordWrap

```lua
UiWordWrap( width )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Maximum width of text |

示例：

```lua
UiWordWrap(200)
UiText("Some really long text that will get wrapped into several lines")
```


### UiTextLineSpacing

```lua
UiTextLineSpacing( value )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `value` | `number` | 否 | Text linespacing |

示例：

```lua
function client.draw()
    UiTextLineSpacing(10)
	UiWordWrap(200)
	UiText("TEXT TEXT TEXT TEXT TEXT TEXT TEXT TEXT TEXT TEXT TEXT TEXT TEXT")
end
```


### UiTextOutline

```lua
UiTextOutline( r, g, b, a, [thickness] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red channel |
| `g` | `number` | 否 | Green channel |
| `b` | `number` | 否 | Blue channel |
| `a` | `number` | 否 | Alpha channel |
| `thickness` | `number` | 是 | Outline thickness. Default is 0.1 |

示例：

```lua
--Black outline, standard thickness
UiTextOutline(0,0,0,1)
UiText("Text with outline")
```


### UiTextShadow

```lua
UiTextShadow( r, g, b, a, [distance], [blur] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red channel |
| `g` | `number` | 否 | Green channel |
| `b` | `number` | 否 | Blue channel |
| `a` | `number` | 否 | Alpha channel |
| `distance` | `number` | 是 | Shadow distance. Default is 1.0 |
| `blur` | `number` | 是 | Shadow blur. Default is 0.5 |

示例：

```lua
--Black drop shadow, 50% transparent, distance 2
UiTextShadow(0, 0, 0, 0.5, 2.0)
UiText("Text with drop shadow")
```


### UiRect

```lua
UiRect( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Width |
| `h` | `number` | 否 | Height |

示例：

```lua
--Draw full-screen black rectangle
UiColor(0, 0, 0)
UiRect(UiWidth(), UiHeight())

--Draw smaller, red, rotating rectangle in center of screen
UiPush()
	UiColor(1, 0, 0)
	UiTranslate(UiCenter(), UiMiddle())
	UiRotate(GetTime())
	UiAlign("center middle")
	UiRect(100, 100)
UiPop()
```


### UiRectOutline

```lua
UiRectOutline( width, height, thickness )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Rectangle width |
| `height` | `number` | 否 | Rectangle height |
| `thickness` | `number` | 否 | Rectangle outline thickness |

示例：

```lua
--Draw a red rotating rectangle outline in center of screen
UiPush()
	UiColor(1, 0, 0)
	UiTranslate(UiCenter(), UiMiddle())
	UiRotate(GetTime())
	UiAlign("center middle")
	UiRectOutline(100, 100, 5)
UiPop()
```


### UiRoundedRect

```lua
UiRoundedRect( width, height, roundingRadius )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Rectangle width |
| `height` | `number` | 否 | Rectangle height |
| `roundingRadius` | `number` | 否 | Round corners radius |

示例：

```lua
UiPush()
	UiColor(1, 0, 0)
	UiTranslate(UiCenter(), UiMiddle())
	UiRotate(GetTime())
	UiAlign("center middle")
	UiRoundedRect(100, 100, 8)
UiPop()
```


### UiRoundedRectOutline

```lua
UiRoundedRectOutline( width, height, roundingRadius, thickness )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Rectangle width |
| `height` | `number` | 否 | Rectangle height |
| `roundingRadius` | `number` | 否 | Round corners radius |
| `thickness` | `number` | 否 | Rectangle outline thickness |

示例：

```lua
UiPush()
	UiColor(1, 0, 0)
	UiTranslate(UiCenter(), UiMiddle())
	UiRotate(GetTime())
	UiAlign("center middle")
	UiRoundedRectOutline(100, 100, 20, 5)
UiPop()
```


### UiCircle

```lua
UiCircle( radius )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `radius` | `number` | 否 | Circle radius |

示例：

```lua
UiPush()
	UiColor(1, 0, 0)
	UiTranslate(UiCenter(), UiMiddle())
	UiAlign("center middle")
	UiCircle(100)
UiPop()
```


### UiCircleOutline

```lua
UiCircleOutline( radius, thickness )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `radius` | `number` | 否 | Circle radius |
| `thickness` | `number` | 否 | Circle outline thickness |

示例：

```lua
--Draw a red rotating rectangle outline in center of screen
UiPush()
	UiColor(1, 0, 0)
	UiTranslate(UiCenter(), UiMiddle())
	UiAlign("center middle")
	UiCircleOutline(100, 8)
UiPop()
```


### UiFillImage

```lua
UiFillImage( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |

示例：

```lua
UiPush()
	UiFillImage("ui/hud/tutorial/plank-lift.jpg")
	UiTranslate(UiCenter(), UiMiddle())
	UiRotate(GetTime())
	UiAlign("center middle")
	UiRoundedRect(100, 100, 8)
UiPop()
```


### UiBackgroundBlur

```lua
UiBackgroundBlur( amount )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `amount` | `number` | 否 | Blur amount (0.0 to 1.0) |

示例：

```lua
UiBackgroundBlur(1.0)
UiRect(300, 300)
```


### UiImage

```lua
w, h = UiImage( path, [x0], [y0], [x1], [y1] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |
| `x0` | `number` | 是 | Lower x coordinate (default is 0) |
| `y0` | `number` | 是 | Lower y coordinate (default is 0) |
| `x1` | `number` | 是 | Upper x coordinate (default is image width) |
| `y1` | `number` | 是 | Upper y coordinate (default is image height) |

**返回**：`w`: number（Width of drawn image）；`h`: number（Height of drawn image）

示例：

```lua
--Draw image in center of screen
UiPush()
	UiTranslate(UiCenter(), UiMiddle())
	UiAlign("center middle")
	UiImage("test.png")
UiPop()
```


### UiUnloadImage

```lua
UiUnloadImage( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |

示例：

```lua
local image = "gfx/cursor.png"

function client.draw()
    UiTranslate(300, 300)
	if UiHasImage(image) then
		if InputDown("interact") then
			UiUnloadImage("img/background.jpg")
		else
			UiImage(image)
		end
	end
end
```


### UiHasImage

```lua
exists = UiHasImage( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |

**返回**：`exists`: boolean（Does the image exists at the specified path）

示例：

```lua
local image = "gfx/circle.png"

function client.draw()
	if UiHasImage(image) then
		DebugPrint("image " .. image .. " exists")
	end
end
```


### UiGetImageSize

```lua
w, h = UiGetImageSize( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |

**返回**：`w`: number（Image width）；`h`: number（Image height）

示例：

```lua
local w,h = UiGetImageSize("test.png")
```


### UiImageBox

```lua
UiImageBox( path, width, height, [borderWidth], [borderHeight] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |
| `width` | `number` | 否 | Width |
| `height` | `number` | 否 | Height |
| `borderWidth` | `number` | 是 | Border width. Default 0 |
| `borderHeight` | `number` | 是 | Border height. Default 0 |

示例：

```lua
UiImageBox("menu-frame.png", 200, 200, 10, 10)
```


### UiSound

```lua
UiSound( path, [volume], [pitch], [panAzimuth], [panDepth] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to sound file (OGG format) |
| `volume` | `number` | 是 | Playback volume. Default 1.0 |
| `pitch` | `number` | 是 | Playback pitch. Default 1.0 |
| `panAzimuth` | `number` | 是 | Playback stereo panning azimuth (-PI to PI). Default 0.0. |
| `panDepth` | `number` | 是 | Playback stereo panning depth (0.0 to 1.0). Default 1.0. |

示例：

```lua
UiSound("click.ogg")
```


### UiSoundLoop

```lua
UiSoundLoop( path, [volume], [pitch] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to looping sound file (OGG format) |
| `volume` | `number` | 是 | Playback volume. Default 1.0 |
| `pitch` | `number` | 是 | Playback pitch. Default 1.0 |

示例：

```lua
if animating then
	UiSoundLoop("screech.ogg")
end
```


### UiMute

```lua
UiMute( amount, [music] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `amount` | `number` | 否 | Mute by this amount (0.0 to 1.0) |
| `music` | `boolean` | 是 | Mute music as well |

示例：

```lua
if menuOpen then
	UiMute(1.0)
end
```


### UiButtonImageBox

```lua
UiButtonImageBox( path, borderWidth, borderHeight, [r], [g], [b], [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Path to image (PNG or JPG format) |
| `borderWidth` | `number` | 否 | Border width |
| `borderHeight` | `number` | 否 | Border height |
| `r` | `number` | 是 | Red multiply. Default 1.0 |
| `g` | `number` | 是 | Green multiply. Default 1.0 |
| `b` | `number` | 是 | Blue multiply. Default 1.0 |
| `a` | `number` | 是 | Alpha channel. Default 1.0 |

示例：

```lua
UiButtonImageBox("button-9slice.png", 10, 10)
if UiTextButton("Test") then
	...
end
```


### UiButtonHoverColor

```lua
UiButtonHoverColor( r, g, b, [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red multiply |
| `g` | `number` | 否 | Green multiply |
| `b` | `number` | 否 | Blue multiply |
| `a` | `number` | 是 | Alpha channel. Default 1.0 |

示例：

```lua
UiButtonHoverColor(1, 0, 0)
if UiTextButton("Test") then
	...
end
```


### UiButtonPressColor

```lua
UiButtonPressColor( r, g, b, [a] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red multiply |
| `g` | `number` | 否 | Green multiply |
| `b` | `number` | 否 | Blue multiply |
| `a` | `number` | 是 | Alpha channel. Default 1.0 |

示例：

```lua
UiButtonPressColor(0, 1, 0)
if UiTextButton("Test") then
	...
end
```


### UiButtonPressDist

```lua
UiButtonPressDist( distX, distY )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `distX` | `number` | 否 | Press distance along X axis |
| `distY` | `number` | 否 | Press distance along Y axis |

示例：

```lua
UiButtonPressDistance(4, 4)
if UiTextButton("Test") then
	...
end
```


### UiButtonTextHandling

```lua
UiButtonTextHandling( type )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `type` | `number` | 否 | One of the enum value |

示例：

```lua
UiButtonTextHandling(1)
if UiTextButton("Test") then
	...
end
```


### UiTextButton

```lua
pressed = UiTextButton( text, [w], [h] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `text` | `string` | 否 | Text on button |
| `w` | `number` | 是 | Button width |
| `h` | `number` | 是 | Button height |

**返回**：`pressed`: boolean（True if user clicked button）

示例：

```lua
if UiTextButton("Test") then
	...
end
```


### UiImageButton

```lua
pressed = UiImageButton( path )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Image path (PNG or JPG file) |

**返回**：`pressed`: boolean（True if user clicked button）

示例：

```lua
if UiImageButton("image.png") then
	...
end
```


### UiBlankButton

```lua
pressed = UiBlankButton( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Button width |
| `h` | `number` | 否 | Button height |

**返回**：`pressed`: boolean（True if user clicked button）

示例：

```lua
if UiBlankButton(30, 30) then
	...
end
```


### UiSlider

```lua
value, done = UiSlider( path, axis, current, min, max )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `path` | `string` | 否 | Image path (PNG or JPG file) |
| `axis` | `string` | 否 | Drag axis, must be 'x' or 'y' |
| `current` | `number` | 否 | Current value |
| `min` | `number` | 否 | Minimum value |
| `max` | `number` | 否 | Maximum value |

**返回**：`value`: number（New value, same as current if not changed）；`done`: boolean（True if user is finished changing (released slider)）

示例：

```lua
value = UiSlider("dot.png", "x", value, 0, 100)
```


### UiSliderHoverColorFilter

```lua
UiSliderHoverColorFilter( r, g, b, a )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `r` | `number` | 否 | Red channel |
| `g` | `number` | 否 | Green channel |
| `b` | `number` | 否 | Blue channel |
| `a` | `number` | 否 | Alpha channel |

示例：

```lua
local slider = 0

function client.draw()
    local thumbPath = "common/thumb_I218_249_2430_49029.png"
    UiTranslate(200, 200)
    UiPush()
        UiMakeInteractive()
        UiPush()
            UiAlign("top right")
            UiTranslate(40, 3.4)
            UiColor(0.5291666388511658, 0.5291666388511658, 0.5291666388511658, 1)
            UiFont("regular.ttf", 27)
            UiText("slider")
        UiPop()
        UiTranslate(45.0, 3.0)
        UiPush()
            UiTranslate(0, 4.0)
            UiImageBox("common/rect_c#ffffff_o0.10_cr3.png", 301.0, 12.0, 4, 4)
        UiPop()
        UiTranslate(2, 0)
        UiSliderHoverColorFilter(1.0, 0.2, 0.2)
        UiSliderThumbSize(8, 20)
        slider = UiSlider(thumbPath, "x", slider * 295, 0, 295) / 295
    UiPop()
end
```


### UiSliderThumbSize

```lua
UiSliderThumbSize( width, height )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Thumb width |
| `height` | `number` | 否 | Thumb height |

示例：

```lua
local slider = 0

function client.draw()
    local thumbPath = "common/thumb_I218_249_2430_49029.png"
    UiTranslate(200, 200)
    UiPush()
        UiMakeInteractive()
        UiPush()
            UiAlign("top right")
            UiTranslate(40, 3.4)
            UiColor(0.5291666388511658, 0.5291666388511658, 0.5291666388511658, 1)
            UiFont("regular.ttf", 27)
            UiText("slider")
        UiPop()
        UiTranslate(45.0, 3.0)
        UiPush()
            UiTranslate(0, 4.0)
            UiImageBox("common/rect_c#ffffff_o0.10_cr3.png", 301.0, 12.0, 4, 4)
        UiPop()
        UiTranslate(2, 0)
        UiSliderHoverColorFilter(1.0, 0.2, 0.2)
        UiSliderThumbSize(8, 20)
        slider = UiSlider(thumbPath, "x", slider * 295, 0, 295) / 295
    UiPop()
end
```


### UiGetScreen

```lua
handle = UiGetScreen(  )
```

**返回**：`handle`: number（Handle to the screen running this script or zero if none.）

示例：

```lua
--Turn off screen running current script
screen = UiGetScreen()
SetScreenEnabled(screen, false)
```


### UiNavComponent

```lua
id = UiNavComponent( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Width of the component |
| `h` | `number` | 否 | Height of the component |

**返回**：`id`: string（Generated ID of the component which can be used to get an info about the component state）

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end
    UiTranslate(960, 540)
    local id = UiNavComponent(100, 20)
    local isInFocus = UiIsComponentInFocus(id)
    if isInFocus then
        local rect = UiFocusedComponentRect()
        DebugPrint("Position: (" .. tostring(rect.x) .. ", " .. tostring(rect.y) .. "), Size: (" .. tostring(rect.w) .. ", " .. tostring(rect.h) .. ")")
    end
end
```


### UiIgnoreNavigation

```lua
UiIgnoreNavigation( [ignore] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `ignore` | `boolean` | 是 | Whether ignore the navigation in a current UI scope or not. |

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end
    UiTranslate(960, 540)
    UiNavComponent(100, 20)

	UiTranslate(150, 40)
	UiPush()
		UiIgnoreNavigation(true)
		local id = UiNavComponent(100, 20)
		local isInFocus = UiIsComponentInFocus(id)
		-- will be always "false"
		DebugPrint(isInFocus)
	UiPop()
end
```


### UiResetNavigation

```lua
UiResetNavigation(  )
```

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end
    UiTranslate(960, 540)
    local id = UiNavComponent(100, 20)

	UiResetNavigation()
	UiTranslate(150, 40)
	UiNavComponent(100, 20)

	local isInFocus = UiIsComponentInFocus(id)
	-- will be always "false"
	DebugPrint(isInFocus)
end
```


### UiNavSkipUpdate

```lua
UiNavSkipUpdate(  )
```

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end
    UiTranslate(960, 540)
	UiNavComponent(100, 20)

	UiTranslate(0, 50)
    local id = UiNavComponent(100, 20)
	local isInFocus = UiIsComponentInFocus(id)

	if isInFocus and InputPressed("menu_up") then
		-- don't let navigation to update and if component in focus
		-- and do different action
		UiNavSkipUpdate()
		DebugPrint("Navigation action UP is overrided")
	end
end
```


### UiIsComponentInFocus

```lua
focus = UiIsComponentInFocus( id )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 否 | Navigation id of the component |

**返回**：`focus`: boolean（Flag whether the component in focus on not）

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

    UiTranslate(960, 540)

	local gId = UiNavGroupBegin()

	UiNavComponent(100, 20)
	UiTranslate(0, 50)
    local id = UiNavComponent(100, 20)
	local isInFocus = UiIsComponentInFocus(id)

	UiNavGroupEnd()

	local groupInFocus = UiIsComponentInFocus(gId)


	if isInFocus then
		DebugPrint(groupInFocus)
	end
end
```


### UiNavGroupBegin

```lua
id = UiNavGroupBegin( [id] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 是 | Name of navigation group. If not presented, will be generated automatically. |

**返回**：`id`: string（Generated ID of the group which can be used to get an info about the group state）

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

    UiTranslate(960, 540)

	local gId = UiNavGroupBegin()

	UiNavComponent(100, 20)
	UiTranslate(0, 50)
    local id = UiNavComponent(100, 20)
	local isInFocus = UiIsComponentInFocus(id)

	UiNavGroupEnd()

	local groupInFocus = UiIsComponentInFocus(gId)


	if isInFocus then
		DebugPrint(groupInFocus)
	end
end
```


### UiNavGroupEnd

```lua
UiNavGroupEnd(  )
```

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

    UiTranslate(960, 540)

	local gId = UiNavGroupBegin()

	UiNavComponent(100, 20)
	UiTranslate(0, 50)
    local id = UiNavComponent(100, 20)
	local isInFocus = UiIsComponentInFocus(id)

	UiNavGroupEnd()

	local groupInFocus = UiIsComponentInFocus(gId)


	if isInFocus then
		DebugPrint(groupInFocus)
	end
end
```


### UiNavGroupSize

```lua
UiNavGroupSize( w, h )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `w` | `number` | 否 | Width of the component |
| `h` | `number` | 否 | Height of the component |

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
		-- active mouse cursor has higher priority over the gamepad control
		-- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

	UiTranslate(960, 540)

	local gId = UiNavGroupBegin()
	UiNavGroupSize(500, 300)

	UiNavComponent(100, 20)
	UiTranslate(0, 50)
    local id = UiNavComponent(100, 20)
	local isInFocus = UiIsComponentInFocus(id)

	UiNavGroupEnd()

	local groupInFocus = UiIsComponentInFocus(gId)

    if groupInFocus then
		-- get a rect of the focused component parent
        local rect = UiFocusedComponentRect(1)
        DebugPrint("Position: (" .. tostring(rect.x) .. ", " .. tostring(rect.y) .. "), Size: (" .. tostring(rect.w) .. ", " .. tostring(rect.h) .. ")")
    end
end
```


### UiForceFocus

```lua
UiForceFocus( id )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `id` | `string` | 否 | Id of the component |

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
        -- active mouse cursor has higher priority over the gamepad control
        -- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

	UiPush()

    UiTranslate(960, 540)

    local id1 = UiNavComponent(100, 20)
    UiTranslate(0, 50)
    local id2 = UiNavComponent(100, 20)

	UiPop()

    local f1 = UiIsComponentInFocus(id1)
    local f2 = UiIsComponentInFocus(id2)

    local rect = UiFocusedComponentRect()
    UiPush()
        UiColor(1, 0, 0)
        UiTranslate(rect.x, rect.y)
        UiRect(rect.w, rect.h)
    UiPop()

    if InputPressed("menu_accept") then
        UiForceFocus(id2)
    end
end
```


### UiFocusedComponentId

```lua
id = UiFocusedComponentId(  )
```

**返回**：`id`: string（Id of the focused component）

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
        -- active mouse cursor has higher priority over the gamepad control
        -- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

	UiPush()

    UiTranslate(960, 540)

    local id1 = UiNavComponent(100, 20)
    UiTranslate(0, 50)
    local id2 = UiNavComponent(100, 20)

	UiPop()

    local f1 = UiIsComponentInFocus(id1)
    local f2 = UiIsComponentInFocus(id2)

    local rect = UiFocusedComponentRect()
    UiPush()
        UiColor(1, 0, 0)
        UiTranslate(rect.x, rect.y)
        UiRect(rect.w, rect.h)
    UiPop()

    DebugPrint(UiFocusedComponentId())
end
```


### UiFocusedComponentRect

```lua
rect = UiFocusedComponentRect( [n] )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `n` | `number` | 是 | Take n-th parent of the focused component insetad of the component itself |

**返回**：`rect`: table（Rect object with info about the component bounding rectangle）

示例：

```lua
function client.draw()
    -- window declaration is necessary for navigation to work
    UiWindow(1920, 1080)
    if LastInputDevice() == UI_DEVICE_GAMEPAD then
        -- active mouse cursor has higher priority over the gamepad control
        -- so it will reset focused components if the mouse moves
        UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
    end

    UiPush()

    UiTranslate(960, 540)

    local id1 = UiNavComponent(100, 20)
    UiTranslate(0, 50)
    local id2 = UiNavComponent(100, 20)

    UiPop()

    local f1 = UiIsComponentInFocus(id1)
    local f2 = UiIsComponentInFocus(id2)

    local rect = UiFocusedComponentRect()
    UiPush()
        UiColor(1, 0, 0)
        UiTranslate(rect.x, rect.y)
        UiRect(rect.w, rect.h)
    UiPop()
end
```


### UiGetItemSize

```lua
x, y = UiGetItemSize(  )
```

**返回**：`x`: number（Width）；`y`: number（Height）

示例：

```lua
function client.draw()
    UiTranslate(200, 200)
    UiPush()
        UiBeginFrame()
            UiFont("regular.ttf", 30)
            UiText("Text")
        UiEndFrame()
        w, h = UiGetItemSize()
        DebugPrint(w .. " " .. h)
    UiPop()
end
```


### UiAutoTranslate

```lua
UiAutoTranslate( value )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `value` | `boolean` | 否 |  |

示例：

```lua
function client.draw()
    UiPush()
        UiBeginFrame()
            if InputDown("interact") then
                UiAutoTranslate(false)
            else
                UiAutoTranslate(true)
            end

            UiRect(50, 50)
            local w, h = UiGetItemSize()
            DebugPrint(math.ceil(w) .. "x" .. math.ceil(h))
        UiEndFrame()
    UiPop()
end
```


### UiBeginFrame

```lua
UiBeginFrame(  )
```

示例：

```lua
function client.draw()
	UiPush()
        UiBeginFrame()
            UiColor(1.0, 1.0, 0.8)
            UiTranslate(UiCenter(), 300)
            UiFont("bold.ttf", 40)
            UiText("Hello")
        local panelWidth, panelHeight = UiEndFrame()
        DebugPrint(math.ceil(panelWidth) .. "x" .. math.ceil(panelHeight))
    UiPop()
end
```


### UiResetFrame

```lua
UiResetFrame(  )
```

示例：

```lua
function client.draw()
    UiPush()
        UiTranslate(UiCenter(), 300)
        UiFont("bold.ttf", 40)
        UiBeginFrame()
            UiTextButton("Button1")
            UiTranslate(200, 0)
            UiTextButton("Button2")
        UiResetFrame()
        local panelWidth, panelHeight = UiEndFrame()
        DebugPrint("w: " .. panelWidth .. "; h:" .. panelHeight)
    UiPop()
end
```


### UiFrameOccupy

```lua
UiFrameOccupy( width, height )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `width` | `number` | 否 | Width |
| `height` | `number` | 否 | Height |

示例：

```lua
function client.draw()
	UiPush()
        UiBeginFrame()
            UiColor(1.0, 1.0, 0.8)
            UiRect(200, 200)
            UiRect(300, 200)
            UiFrameOccupy(500, 500)
        local panelWidth, panelHeight = UiEndFrame()
        DebugPrint(math.ceil(panelWidth) .. "x" .. math.ceil(panelHeight))
    UiPop()
end
```


### UiEndFrame

```lua
width, height = UiEndFrame(  )
```

**返回**：`width`: number（Width of content drawn between since UiBeginFrame was called）；`height`: number（Height of content drawn between since UiBeginFrame was called）

示例：

```lua
function client.draw()
	UiPush()
        UiBeginFrame()
            UiColor(1.0, 1.0, 0.8)
            UiRect(200, 200)
            UiRect(300, 200)
        local panelWidth, panelHeight = UiEndFrame()
        DebugPrint(math.ceil(panelWidth) .. "x" .. math.ceil(panelHeight))
    UiPop()
end
```


### UiFrameSkipItem

```lua
UiFrameSkipItem( skip )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `skip` | `boolean` | 否 | Should skip item |

示例：

```lua
function client.draw()
	UiPush()
		UiBeginFrame()
			UiFrameSkipItem(true)
			--[[
				...
			]]
		UiEndFrame()
	UiPop()
end
```


### UiGetFrameNo

```lua
frameNo = UiGetFrameNo(  )
```

**返回**：`frameNo`: number（Frame number since the level start）

示例：

```lua
function client.draw()
	local fNo = GetFrame()
	DebugPrint(fNo)
end
```


### UiGetLanguage

```lua
index = UiGetLanguage(  )
```

**返回**：`index`: number（Language index）

示例：

```lua
local n = UiGetLanguage()
```


### UiSetCursorState

```lua
UiSetCursorState( state )
```

| 参数 | 类型 | 可选 | 说明 |
|---|---|---|---|
| `state` | `number` | 否 |  |

示例：

```lua
#include "ui/ui_helpers.lua"

function client.draw()
	UiPush()
		-- If the last input device was a gamepad, hide the cursor and proceed to control through D-pad navigation
		if LastInputDevice() == UI_DEVICE_GAMEPAD then
			UiSetCursorState(UI_CURSOR_HIDE_AND_LOCK)
		end

        UiMakeInteractive()
        UiAlign("center")
        UiColor(1.0, 1.0, 1.0)
		UiButtonHoverColor(1.0, 0.5, 0.5)
        UiFont("regular.ttf", 50)
        UiTranslate(UiCenter(), 200)

        UiTranslate(0, 100)
        if UiTextButton("1") then
            DebugPrint(1)
        end
        UiTranslate(0, 100)
        if UiTextButton("2") then
            DebugPrint(2)
        end
	UiPop()
end
```

