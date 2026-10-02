# Teardown 开放 API 调研报告

> 调研对象：**Teardown**（Steam appid 1167630，Tuxedo Labs / Saber，引擎为改造版 Godot 3）
> 调研时间：2026-02 ｜ 对应游戏版本 **2.1.0.2**（官方 API 文档标注 **2.1.0**）
> 主要来源：官方 [Modding 文档](https://teardowngame.com/modding/) ｜ [api.html](https://teardowngame.com/modding/api.html) ｜ [api.xml](https://teardowngame.com/modding/api.xml) ｜ [多人与联机 Modding](https://teardowngame.com/modding-mp/) ｜ [Changelog](https://teardowngame.com/changelog/)

---

## 0. 一句话结论

Teardown 的"开放 API"**不是 REST/网络 API，而是进程内的 Lua 5.1 脚本 API**：
官方暴露 **609 个全局函数、24 个分类**，覆盖刚体/体素形状/关节/射线查询/玩家/载具/UI/音效/粒子/动画，
脚本与引擎之间**只能**通过这批函数 + registry 全局键值库交互（官方原话：*"Each Teardown script runs in its own Lua context and can only interact with the engine and other scripts through API functions and the registry"*）。

**没有任何官方文件 IO / HTTP / Socket 函数** —— 唯一与"外部数据"相关的是 `HasFile(path)`（判断文件存在）和 `Spawn(xml)` / `CreateShape(refShape=Vox路径)`（加载 XML 与 .vox）。
所有外部输入必须通过**资源文件（.vox/.xml/.png/.ogg）+ registry 持久化**完成，这是一个有意设计的沙箱。

对"给引擎加新能力"而言，官方只给 Lua 层；要碰 C++ 内核只能走社区的 **TDLL 注入**（见第 8 节，非官方）。

---

## 1. API 的三种"开放面"

| 层面 | 开放形式 | 官方支持 | 能做什么 | 不能做什么 |
|---|---|---|---|---|
| **Lua 脚本 API** | 609 个全局函数 + registry + 事件系统 | ✅ 完整文档 | 造工具/武器、写游戏模式、操作刚体与体素、UI、粒子、音效、联机 | 无文件 IO、无网络、无 OS 调用 |
| **关卡/资源格式** | XML 关卡、.vox 体素、prefab、脚本参数 | ✅ | 编辑器搭场景、脚本参数注入、Spawn 实例化 | XML 只描述数据，不含逻辑 |
| **引擎内核** | 无公开接口；Lua 虚拟机在引擎内 | ❌ | — | 官方不提供 C/C++ 插件 API、不提供 mod 加载 DLL 机制 |

> 注：Teardown 用 Godot 3，但**不**开放 GDExtension/GDNative 那一套；社区做的 TDLL 是通过劫持进程符号把 Lua 绑定注入进已运行的引擎（见第 8 节）。

---

## 2. 脚本执行模型

### 2.1 两级生命周期（v2 脚本 / 联机版）

同一份 `.lua` 文件**在服务端和每个客户端各跑一份**，用三个内建表区分：

| 表 | 存在位置 | 用途 |
|---|---|---|
| `server` | 仅主机（服务端） | 权威逻辑：计分、规则、生成、校验玩家行为 |
| `client` | 每个客户端 | 表现层：HUD/UI、粒子、音效、相机、动画 |
| `shared` | 由服务端自动同步到客户端 | 同步数据；客户端**只读**，频繁写会吃带宽 |

回调（全部可选）：

| 服务端回调 | 时机 |
|---|---|
| `server.init()` | 加载时一次 |
| `server.tick(dt)` | 每帧一次，dt ∈ (0, 0.0333] 可变步长 |
| `server.update(dt)` | 固定步长 60Hz，每帧最多 2 次（可能 0 次） |
| `server.postUpdate()` | 同 update，但在物理之后 |
| `server.destroy()` | 脚本/游戏模式停止 |

| 客户端回调 | 时机 |
|---|---|
| `client.init() / tick(dt) / update(dt) / postUpdate()` | 同上 |
| `client.draw()` | 2D 覆盖层绘制期间——**只有这里能用 `Ui*` 函数** |
| `client.render(dt)` | 每帧一次，实际绘制前 |
| `client.destroy()` | 脚本停止 |

### 2.2 版本开关（关键坑）

- 单机脚本：文件顶部**无需**标记，直接写 `function init() / tick(dt)`（v1 风格，全局函数）。
- 联机脚本：文件**首行**必须是 `#version 2`，否则该脚本在联机中会被**静默禁用**。
- mod 的 `info.txt` 需要 `version = 2` 才被识别为多人 mod。
- 反过来的坑：如果 mod 里**任一**脚本缺 `#version 2`，整个 mod 在联机里可能部分或完全跑不起来。

### 2.3 数据模型：一切都是 number

官方原话：*"The Teardown API uses only native lua types. Handles to objects are plain Lua numbers."*

- **handle**：所有实体（body/shape/joint/light/trigger/vehicle/rig/screen/location/animator）都是 **number**；0 表示无效。
- **playerId**：多数玩家相关函数末尾可选参数；客户端里 `0` = 本机玩家，服务端里 `0` = 主机（host）玩家。
- **输入**：`InputDown / InputPressed / InputReleased / InputValue(input, playerId?)`，`input` 取逻辑名（`up/down/left/right/jump/crouch/interact/usetool/grab/flashlight/map/pause/vehicleraise/...`）或物理名（`lmb/rmb/mmb/space/return/shift/ctrl/f1-f12/...`）；`camerax/cameray` 只在 `InputValue` 有效。
- **TVec**：普通 Lua table `{x, y, z}`（也支持索引 1..3）。
- **TQuat**：`{x, y, z, w}`；**TTransform**：`{pos = TVec, rot = TQuat}`。
- 类型错误不会报编译错，而是运行时静默失败 → 建议用 `IsHandleValid(h)` 防御式编程。

---

## 3. API 全貌（24 类 / 609 函数）

| 分类 | 数量 | 内容概要 |
|---|---|---|
| Parameters | 5 | `GetIntParam/GetFloatParam/...` 读关卡 XML 传入的脚本参数 |
| Script control | 22 | 输入(`InputDown/Pressed/Value`)、`GetTime/GetTimeStep`、`StartLevel`、`SetPaused`、`Restart`、`Menu`、`ClientCall/ServerCall` |
| Registry | 17 | 全局层级键值库 `SetInt/GetString/ListKeys/ClearKey` 等；`savegame.mod.*` 可持久化 |
| Events | 3 | `PostEvent/GetEvent/GetEventCount`；内建事件 playerhurt / playerdied / explosion / projectilehit |
| Vector math | 38 | `Vec*/Quat*/Transform*` 全套 + `GetRandomInt/Float/Direction`、`SetRandomSeed` |
| Entity | 16 | `FindEntity/FindEntities`、tag 系统、`GetProperty/SetProperty`、`Delete` |
| **Body** | **33** | 刚体：变换/质量/速度/角速度/重力缩放/激活、`ApplyBodyImpulse`、`GetBodyShapes`、`Constrain*` 约束、`GetWorldBody` |
| **Shape** | **40** | 体素形状核心：`CreateShape`、`SetBrush`+绘画三件套、`ResizeShape`、`TrimShape`、`SplitShape`、`MergeShape`、`IsShapeDisconnected`、调色板/材质 |
| Location | 3 | 命名位置点（用于 spawn 点、工具箱等约定标记） |
| Joint | 16 | 关节：类型/马达/限位/绳索(`GetRopePointPosition/BreakRope`)、`GetJointedBodies` |
| Animation | 33 | animator/bone/动画片段/IK/布娃娃(`MakeRagdoll`) |
| Light | 11 | 灯光开关/颜色/强度/手电 |
| Trigger | 13 | 触发体空间测试：`IsBodyInTrigger`、`IsPointInTrigger`、`IsTriggerEmpty` |
| Screen | 6 | 屏幕实体（可显示脚本输出） |
| Vehicle | 18 | 载具：参数/血量/座位/驾驶(`DriveVehicle`) |
| Rig | 7 | 玩家 rig 及其 location 的变换 |
| **Player** | **105** | 最大一类：玩家状态/相机/抓取/工具注册(`RegisterTool`)/弹药/血量/伤害/生成点/颜色 |
| Sound | 22 | `LoadSound/PlaySound/PlayLoop`、音乐通道、3D 音量 |
| Sprite | 2 | `LoadSprite/DrawSprite` |
| **Scene queries** | **28** | `QueryRaycast/QueryShot/QueryClosestPoint/QueryAabb*` + `QueryRequire/QueryInclude/QueryReject*` 过滤器链 + 寻路 `CreatePathPlanner` + 水/风查询 |
| Particles | 15 | 粒子发射器参数(`ParticleType/Gravity/Collide/Sticky`) + `SpawnParticle` |
| Spawn | 3 | `Spawn` / `SpawnLayer` / `SpawnTool`：从 **XML 字符串或文件**实例化 prefab |
| Miscellaneous | 54 | `MakeHole`、`Explosion`、`Shoot`、`Paint`、火焰(`SpawnFire/QueryClosestFire`)、相机、环境/后处理属性、调试绘制、手柄震动、`GetGravity/SetGravity`、`GetFps` |
| **User Interface** | **99** | 立即模式 UI：布局(窗口/裁剪/变换/锚点)、文本、矩形/圆/图片、按钮/滑条、导航焦点系统、帧布局 |

**侧别限制**：42 个函数 **server-only**（写玩家状态、`Shoot/Paint/MakeHole/Explosion/SpawnFire`、`SetGravity`、`SetTimeScale`、`SetEnvironment*` 等），33 个 **client-only**（输入清除、相机、手电/震动、`PlaySoundForUser`、UI 相关、`AddMapMarker`）。
在错的侧调用 = 静默无效（联机下）。离线单机时两者都存在。

---

## 4. 对破坏物理引擎最有参考价值的 API（对照本项目）

本项目（Godot 4 的 2D 像素破坏 + 刚体）与 Teardown 的对应关系：

### 4.1 形状 = 体素集合，破坏 = 连通性分裂

```lua
-- Teardown 的核心破坏循环（简化）
local shapes = SplitShape(shape, true)      -- 按连通性把体素分裂成多个 shape，返回新 handle 表
local offset = TrimShape(shape)             -- 裁掉 AABB 边缘空腔，返回偏移
if IsShapeDisconnected(shape) then ... end  -- 查询：是否已分裂
local n = GetShapeVoxelCount(shape)         -- 体素总数（便于做破坏度/性能预算）
```

- `CreateShape(body, transform, refShape|vox路径)`：把 .vox 数据挂到刚体上成为 shape。
- `SetShapeBody(shape, body, transform)`：把已有 shape 换挂到另一个 body —— **破坏后重组刚体**的关键。
- `MergeShape(shape)`：合并同 body 上的形状（反向优化）。
- `IsStaticShapeDetached(shape)`：静态几何被破坏后是否已与主体脱离（用于"悬空结构掉落"）。
- `ResizeShape(shape, xmi, ymi, zmi, xma, yma, zma)`：以体素为单位裁剪盒。
- `SetShapeCollisionFilter(shape, layer, mask)`：碰撞层/掩码（与 Godot 的 collision_layer/mask 概念一致）。
- 材质/调色板：`GetShapePalette`、`GetShapeMaterial(shape, entry)`（reflectivity/shininess/metallic/emissive）、`SetShapeDensity`、`SetShapeEmissiveScale`。

### 4.2 打洞与爆炸（引擎内建的"破坏原语"）

```lua
MakeHole(pos, r0, r1?, r2?, silent?)   -- 按软/中/硬材料分别给半径，返回受影响体素/形状数
Explosion(pos, size, playerId?)        -- size 0.5~4.0，含冲击波+碎裂
Shoot(origin, dir, type?, strength?, maxDist?, playerId?)  -- 引擎级射线射击
Paint(origin, radius, type?, probability?)  -- 喷涂材质
AddHeat(shape, pos, amount)            -- 火焰蔓延/加热
```

注意 `MakeHole` 的**三档半径**（r0 ≥ r1 ≥ r2，对应 软/中/硬材质）——这是很值得抄的设计：一次打洞对"木头吃满、混凝土只破一点"。

### 4.3 刚体约束（不用建关节也能做"伺服"）

```lua
ConstrainVelocity(bodyA, bodyB, point, dir, relVel, min?, max?)
ConstrainAngularVelocity(bodyA, bodyB, dir, relAngVel, min?, max?)
ConstrainPosition(bodyA, bodyB, pointA, pointB, maxVel?, maxImpulse?)
ConstrainOrientation(bodyA, bodyB, quatA, quatB, maxAngVel?, maxAngImpulse?)
```

这组是**每帧给约束求解器喂目标**（抓取、载具悬挂、电梯、起重机都用它），比物理引擎里预建关节更灵活 —— 对"像素团抓取"很有借鉴意义。

### 4.4 查询与过滤链

```lua
QueryRequire("dynamic")            -- 只接受动态物体
QueryInclude("static, dynamic")    -- 额外包含
QueryRejectPlayer()                -- 排除玩家
local hit, dist, normal, shape = QueryRaycast(origin, dir, maxDist, radius?, rejectTransparent?)
local hit, dist, shape, pid, dmg, normal = QueryShot(origin, dir, maxDist, radius?, playerId?)
local shapes = QueryAabbShapes(min, max)   -- 区域内的所有 shape（爆破碎片收集）
local hit, point, normal, shape = QueryClosestPoint(origin, maxDist)
```

**全局过滤器状态 + 查询**的 API 风格（先设过滤器再查询，而不是把过滤条件当参数传）很省参数，值得借鉴。

### 4.5 体素材质与尺寸

```lua
local type, r, g, b, a, entry = GetShapeMaterialAtPosition(shape, pos, includeUnphysical?)
GetShapeMaterialAtIndex(shape, x, y, z)    -- 直接按体素索引取材质
local xsize, ysize, zsize, scale = GetShapeSize(shape)
```

---

## 5. Mod 工程结构（发布相关）

mod 就是一个文件夹，放在 `Documents/Teardown/Mods/<ModName>`（订阅的 Workshop mod 会被复制到这里或由 Steam 直接挂载）：

```
MyMod/
├─ info.txt       # 必需：name / author / description / tags，联机需 version = 2，可加 preview =
├─ main.lua       # 全局 mod 入口脚本
├─ main.xml       # 有它 => 被判定为 Content mod（可玩关卡）
├─ options.lua    # mod 选项（显示在 mod 选项菜单）
├─ gamemodes.txt  # （联机）声明游戏模式，见下
├─ preview.jpg    # Workshop 缩略图（<1MB）；联机 mod 菜单缩略图 512x292
├─ scripts/  images/  sound/  vox/
└─ id.txt         # 首次发布后由游戏生成，记录 Steam Workshop item id
```

- **Global mod**：对所有游戏生效（改玩法/工具）；**Content mod**：自带可玩关卡（必须有 `main.xml`）。
- 路径引用用关键字 **`MOD`**：如 `Spawn("MOD/prefab/mycar.xml")`、`StartLevel("level1", "MOD/level1.xml")`。
- 文件名/目录建议只用 `a-z 0-9 空格`，否则可能加载失败。
- `info.txt` 的 `tags` 取值：**Map / Gameplay / Asset / Vehicle / Tool**。
- `gamemodes.txt` 定义联机游戏模式：

```ini
[My Game Mode 1]
description = "This game mode will always restart the level when selected"
path = mygamemode1.lua
restart = true

[My Game Mode 2]        ; Content Game Mode 用 layers 代替 path
layers = gamemodelayer1, alwaysActiveLayer
```

同一时刻只能有一个 Game Mode 生效；Global Game Mode 跑在当前关卡上，Content Game Mode 总是从 mod 的 `main.xml` + 指定 layer 启动。

---

## 6. 持久化与脚本间通信

### 6.1 Registry（唯一的内建存储）

层级键值库，值类型为 number/int/bool/string（读取时自动转换）：

| 节点 | 用途 | 权限 |
|---|---|---|
| `options` | 游戏设置 | mod **只读** |
| `game` | 引擎内部信息（大量运行时状态从这里暴露） | 可读，写需谨慎 |
| `savegame` | 存档数据 | mod **只读** |
| `savegame.mod.*` | **mod 持久化数据**（键名只允许字母数字） | 可读写 |
| `level` | 约定给关卡/脚本通信 | 可读写 |

节点名只允许 `a-z 0-9 . - _`。工具函数：`SetInt/SetFloat/SetBool/SetString/SetColor` + 对应 Get、`HasKey`、`ListKeys`、`ClearKey`。

### 6.2 事件系统

```lua
function init() PostEvent("mymod:door_open", {id = 3}) end        -- 触发
RegisterListenerTo("mymod:door_open", "onDoor")                  -- 监听（Miscellaneous 分类）
```
内建事件：**playerhurt / playerdied / explosion（仅服务端）/ projectilehit（仅服务端）**，参数见官方文档。
跨侧调用（目标函数必须存在于发起脚本自身）：

```lua
ServerCall("函数名", ...)                 -- 客户端 -> 服务端
ClientCall(playerId, "函数名", ...)        -- 服务端 -> 指定客户端；playerId = 0 表示广播全体
```

---

## 7. 联机模型要点（2.0+）

- **无独立服务器**：开房间的玩家主机同时是 server 和 client，其他玩家只是 client。
- 权威逻辑写在 `server`，表现写在 `client`，状态经 `shared` 单向同步。
- 42 个 server-only / 33 个 client-only 函数必须在正确的侧调用（见第 3 节）。
- 官方提供 **mplib**（Multiplayer Lua Library）处理刷新点、HUD、工具/掉落、计分、同步等：
  文档 <https://tuxedolabsorg.github.io/mplib/> ，源码 <https://github.com/tuxedolabsorg/mplib> 。
- 关卡标准化标记（Location 节点约定）用于刷新点/工具箱/目标点，社区游戏模式**不强制**但建议遵循以提升兼容性。
- 资源同步：DLC/扩张内容、spawnables、mod 内容在 2.0.x 起支持 mod-sync。

---

## 8. 官方沙箱边界 vs. 社区扩展（重要）

**官方不给的东西**（在 609 个函数里穷举确认）：

- ❌ 文件读写：只有 `HasFile(path)`；没有 `io.*`/`os.*`/`loadfile` 暴露。
- ❌ 网络：无 HTTP/Socket/WebSocket 函数；联机只能走引擎同步通道。
- ❌ 动态代码加载：没有 `LoadScript`/`require` 的官方入口（脚本由 mod 目录静态加载）。
- ❌ 原生扩展：官方**没有** mod DLL/插件加载机制。

**社区绕过方案：TTFH/TDLL（非官方）**

[TTFH/TDLL](https://github.com/ttfh/tdll)（Extended Teardown API）是目前唯一成体系的扩展方案，做法是**把 `winmm.dll`（DLL 代理劫持）放进 Teardown 安装目录**，由 DLL 向引擎的 Lua 虚拟机额外注册函数。

| 项目 | 内容 |
|---|---|
| 安装 | 下载 `winmm.dll` 复制到 Teardown.exe 所在目录；删除即卸载 |
| 版本兼容 | 声明兼容 **Teardown 2.0.4+**，不保证更高版本；**明确警告不要在联机中使用** |
| 选项菜单 | 暂停菜单按 **F1** 打开 DLL 选项 |
| 风险 | 作者标注部分函数未测试、可能崩游戏；非官方、非 Steam 签名 |

它补上的正是官方沙箱**故意不给**的能力（这是判断"官方 API 边界"的最好证据）：

```lua
-- 网络（官方完全没有）
status, response      = HttpRequest(method, endpoint, headers, body, cookies)  -- 同步 HTTP
id                    = HttpAsyncRequest(method, endpoint, headers, body)      -- 异步 HTTP
responses             = FetchHttpResponses()                                  -- [{id, url, status, body}]
SendDatagram(msg) / msgs = FetchDatagrams()                                   -- UDP 数据报

-- 文件 IO（官方只有 HasFile）
SaveToFile(file, str) ／ str = ZlibLoadCompressed(file) ／ ZlibSaveCompressed(file, str)
width, height, pixels = LoadImagePixels(path) ／ SaveImageToFile(path, w, h, pixels)

-- 系统信息与计时
hour, min, sec = GetSystemTime() ／ year, month, day = GetSystemDate()
Tick(i) / Tock(i)（纳秒级计时）

-- 补齐引擎内部状态（官方文档未暴露的字段）
voxels   = GetShapeVoxelMatrix(shape)             -- 直接拿到 [x][y][z] 体素矩阵
palette  = GetShapePaletteId(shape) / SetShapePalette(shape, palette)
type,r,g,b,a,refl,shin,metal,emis = GetPaletteMaterial(palette, index)
texture, weight, blendTexture, blendTextureWeight = GetShapeTexture(shape)（+ Set 版本）
shape, pos = GetFireInfo(index) ／ count = GetHeatCount() ／ shape,pos,amt = GetHeatInfo(index)
pos, rot = GetWaterTransform(water) ／ list = GetWaterVertices(water) ／ SetWaterVertex(water, i, v)
SetJointStrength(joint, strength, size) ／ size = GetJointSize(joint) ／ GetJointParams(joint)
SetShapeScale / SetCollision / SetVehicleMaxSteerAngle / SetSunLength ...
```

> DLL 还暴露了一批**引擎内部函数**（约 110 个），例如 `DeleteShape / SaveShape / SetShapeStrength / GetShapeStrength / NetSession* 系列（建房/加入/踢人）/ CompleteAchievement / Robot*CPP、Tornado*CPP、explosionDebrisCPP` 等；这些需要通过 `AllowInternalFunctions(script)` 打开开关后才可调用，属于纯粹的逆向成果，**稳定性与合规性自负**。

**其它社区资源**：`Teardown-Totally-Documented`、`chipslays/teardown-russian-documentation` 等把未公开/内部函数做了整理归档。

→ 结论：**做"正经"的 Teardown mod，就用官方 609 个函数 + registry + XML/vox 资源**；官方沙箱内**没有网络、没有文件读写**。真要网络/文件，只能装 TDLL（换版本即失效，且不能联机）。

---

## 9. 开发工具链

| 工具 | 用途 |
|---|---|
| 游戏内 Mod 管理器 | 新建 mod、编辑、F5 测试关卡、F4 回编辑器、发布 Workshop |
| 内置 Mod（Make local copy） | 官方示例是最好的模板 |
| `DebugPrint / DebugWatch / DebugLine / DebugCross / DebugTransform` | 引擎内调试输出与 3D 调试绘制 |
| **VS Code 补全** | 官方**未**提供 `.lua` 定义文件。社区方案：[Teardown Intellisense](https://marketplace.visualstudio.com/items?itemName=GhoustUser.teardown-intellisense)（2026-02 版本覆盖 **606 个函数 / 16 别名**，含 `server/client/Vec3/Quat` 类、`#include` 跳转；**仅当工作区根目录有 `info.txt` 时才启用**） |
| **社区 JSON 文档** | [funlennysub/teardown-api-docs-json](https://github.com/funlennysub/teardown-api-docs-json)：`stable_api.json` / `exp_api.json`，结构 = `{version, baseURL, api:[{category, desc, functions:[{name, def, arguments, return, info, example}]}]}`，**但版本停在 0.8.0（仅 277 函数 / 20 分类）**，做 IDE 工具可参考其 schema，数据请以官方 api.xml 为准 |
| 本项目自带 | `docs/teardown_api_research/` 下的 `teardown_api_full.md`（609 函数全参数说明+示例+属性表）与 `api_index.md`（速查）均由官方 api.xml 生成，比社区 JSON 新 |
| 官方视频教程 | 12 集编辑器 + 10 集脚本基础 + 10 集联机脚本（见 [modding index](https://teardowngame.com/modding/index.html)） |

---

## 10. 对本项目（TapTap2026 2D 像素破坏）的可迁移要点

1. **破坏原语要按材质分档**：Teardown `MakeHole(pos, r0, r1, r2)` 按软/中/硬三档半径，本项目可按像素"硬度"分级（软材料全挖、硬材料小坑），比统一半径更有手感。
2. **连通性分裂必须是引擎级函数**：`SplitShape` / `IsShapeDisconnected` 把"破坏后成为新刚体"做成一等公民 —— 与本项目"破坏即物理（按连通性分裂成新刚体）"的设计完全同构，可参考它把分裂、残渣裁剪（`TrimShape`）、合并优化（`MergeShape`）都做成一族 API。
3. **约束不是关节**：`Constrain*` 一族用"每帧喂期望相对速度/位置"实现抓取与机械，避免了在物理世界里动态增删关节，值得用于抓取/拖拽。
4. **查询过滤器做成全局状态**：`QueryRequire/QueryInclude/QueryReject*` 后再 `QueryRaycast/QueryShot/QueryAabbShapes`，能让上层 API 保持简洁。
5. **实体句柄统一为 number（0 = 无效）**：跨语言边界时比对象引用更易序列化，对存档/回放/联机同步友好（本项目若有存档/回放计划可借鉴）。
6. **服务端/客户端标签化 API**：每个函数标注 server-only / client-only，在类型层面防止联机逻辑写错侧 —— 本项目若做联机，可在 GDScript 文档注释里复刻这一约定。

---

## 11. 参考链接

- 官方 Modding 入口（含视频教程表）：<https://teardowngame.com/modding/index.html>
- 官方 Lua API 参考（人类可读）：<https://teardowngame.com/modding/api.html>
- 官方 API 机器可读定义：<https://teardowngame.com/modding/api.xml>
- 联机 Modding 文档：<https://teardowngame.com/modding-mp/index.html>
- 版本更新日志：<https://teardowngame.com/changelog/>
- 官方多人与联机 Lua 库 mplib：<https://tuxedolabsorg.github.io/mplib/> ｜ <https://github.com/tuxedolabsorg/mplib>
- Lua 5.1 手册（脚本语言本体）：<https://www.lua.org/manual/5.1/>
- Steam Workshop：<https://steamcommunity.com/app/1167630/workshop/>
