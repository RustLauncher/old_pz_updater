# Expanded Storage（扩展储物）

这是一个用于统一调整 Project Zomboid Build 42 各类储物容器容量的 Mod。

当前版本包含：

- 一级木箱（Shoddy Wooden Crate）：40 → 60
- 二级木箱（Wooden Crate）：60 → 80
- 两种军用箱的全部朝向和堆叠高度：容量设为 100
- 军用储物柜的四个朝向：容量设为 100
- 绿色壁挂储物柜的四个朝向：40 → 60
- 小型金属箱的四个朝向：10 → 20
- 大型双格金属货架的全部组成贴图：每格容量设为 100
- Greene’s 可堆叠小木箱：25 → 50
- 简陋高立柜的全部朝向/变体：40 → 80
- 金属立柜的四个朝向：容量设为 100
- 简陋壁柜的四个朝向：30 → 50
- 橡木高货架的四个朝向：40 → 60
- 白色精致高货架的四个朝向：40 → 60
- 大型壁式货架的普通四个朝向：30 → 60
- 大型壁式转角货架的四个朝向：30 → 100
- 制作型木质货架的四个朝向：30 → 40
- 高树枝货架的四个朝向：20 → 30
- 支持木箱堆叠后的低、中、高三种贴图。
- 新建容器和旧存档中已经放置的对应容器都会应用新容量。

后续可以继续加入军用箱、金属柜、厨房柜和其他储物家具。

## 新增建造配方

当前增加两种独立的军用箱建造配方：

- 绿色军用箱
- 灰色军用箱

两种配方均无需杂志解锁，要求金工 9，材料相同：

- 喷灯消耗 4
- 小金属板 2
- 金属板 2
- 废金属 1
- 焊条消耗 4

配方位于家具建造分类，两种军用箱均可旋转、堆叠和加挂锁。

同时增加大型双格金属货架配方，无需杂志解锁：

- 金工等级 5
- 喷灯消耗 4
- 金属板 4
- 金属管 4
- 废金属 2
- 焊条消耗 4

该货架作为两格家具整体建造，每格容量 100，合计相当于 200。

## 本地安装

把整个 `ExpandedStorage` 文件夹复制到：

`C:\Users\你的用户名\Zomboid\mods\`

然后在游戏的“模组”菜单中启用 `Expanded Storage`。

## 多人服务器

服务端和所有客户端都需要安装并启用本 Mod。服务器配置中的 Mod ID 是：

`ExpandedStorage`

如果使用创意工坊发布，还需要把发布后得到的 Workshop ID 加入服务器配置。

## 兼容性说明

当前版本修改以下原版贴图对应容器的容量：

- `carpentry_01_16` ～ `carpentry_01_18`：80
- `carpentry_01_19` ～ `carpentry_01_21`：60
- `location_military_generic_01_0` ～ `location_military_generic_01_5`：100
- `location_military_generic_01_8` ～ `location_military_generic_01_13`：100
- `location_military_generic_01_22`、`23`、`30`、`31`：100
- `furniture_storage_02_8` ～ `furniture_storage_02_11`：60
- `furniture_storage_02_28` ～ `furniture_storage_02_31`：20
- `furniture_shelving_01_24` ～ `furniture_shelving_01_27`：每格 100
- `location_shop_greenes_01_35` ～ `location_shop_greenes_01_36`：50
- `crafted_05_16` ～ `crafted_05_19`：80
- `furniture_storage_02_0` ～ `furniture_storage_02_3`：100
- `crafted_05_20` ～ `crafted_05_23`：50
- `furniture_shelving_01_40` ～ `furniture_shelving_01_43`：60
- `furniture_shelving_01_44` ～ `furniture_shelving_01_47`：60
- `furniture_shelving_01_9` ～ `furniture_shelving_01_12`：60
- `furniture_shelving_01_8`、`13`、`14`、`15`：100
- `carpentry_02_64` ～ `carpentry_02_67`：40
- `crafted_04_92` ～ `crafted_04_95`：30

其他同样修改这些贴图容量的 Mod 可能与本 Mod 冲突；最终数值取决于加载顺序。
