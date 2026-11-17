# AGENTS.md · 简忆（JIAN YI）

> 给 AI 编码助手 / Agent 的项目速查与踩坑记录。
> **长期约定以 [`.trae/rules/project_rules.md`](./.trae/rules/project_rules.md) 为准**，本文件不重复规则，只写「怎么在这里干活」和「已经踩过的坑」。
> 背景资料：[`README.md`](./README.md)、[`.workbuddy/memory/`](./.workbuddy/memory/)。

---

## 0. 一句话

简忆是**要装到手机上的 HarmonyOS NEXT 原生应用**（ArkTS + ArkUI，Stage 模型），本地优先的个人心智工具：记下值得记住的句子、安排今天要做的事、读完手里的书、攒下一点一滴的成长。

## 1. 产品定位（最高优先级 · 用户 2026-11-12 明确）

- **是原生 App，不是网页，更不是 WebView 套壳。**
  `jianyi-prototype.html` 只是交互原型和设计事实来源，只允许用浏览器打开看效果。禁止把它塞进 `Web` 组件当运行时 UI，禁止为了让效果「像原型」而退回 HTML/CSS/JS。
- UI 必须是 ArkUI 声明式组件；持久化必须走 RelationalStore / Preferences。
  （当前工程没有一行 `Web` 组件，这一点本来是对的，别把它改坏。）
- **系统级操作必须按原生规范接**：系统返回键与侧滑返回、页面与 Ability 生命周期、前后台切换、状态栏与安全区、权限申请、通知、备份、桌面图标与启动窗口。
  凡涉及「用户在手机上的手势或系统行为」，不能只在界面画一个自绘按钮就算完成。
- 导航要有**真实页面栈**，让系统返回自然逐层回退。2026-11-13 已落地：搜索页与二级页是独立 `@Entry` 页面，进 router 系统页面栈；单页条件渲染覆盖层已退役。后续可迁移到官方更推荐的 `Navigation`，见第 4 节。
- 验收标准：断网可用、清后台再进数据还在、系统返回逐层退、切深浅色不闪黑、启动窗口不白屏 —— 行为像系统应用，而不是像浏览器标签页。
- 优先级（沿用 project_rules 1）：**能每天用 > 功能多**，单人本地使用，不做账号、不做社交。

## 2. 工程速查

| 项 | 值 |
|---|---|
| 平台 | HarmonyOS NEXT，`compatibleSdkVersion 6.1.1(24)`，`targetSdkVersion 26.0.1` |
| 编译 | DevEco Studio 5.0+；本机装有 DevEco Studio 26 + `devecocli`，Agent 可 `devecocli build` 真编译（2026-11-16 起可用，见 3.9 附注） |
| 入口 Ability | `entry/src/main/ets/entryability/EntryAbility.ets` → `loadContent('pages/Index')` |
| 页面注册 | `entry/src/main/resources/base/profile/main_pages.json`（4 个页面，Index 第一为启动页） |
| 主页面 | `entry/src/main/ets/pages/Index.ets`（页面栈底） |
| 独立页面 | `pages/SearchPage.ets`（搜索）、`pages/SubPage.ets`（习惯/心情/摘录/阅读）、`pages/GrowthPage.ets`（微光回顾） |
| 五个主视图 | `view/TodayView / QuoteView / TodoView / ReaderView / PlanView` |
| 全局弹层 | `view/QuickSheet`（录入），在 Index / SubPage / GrowthPage 各渲染一份，靠 `uiSheet` 控制 |
| 状态总线 | `common/Bus.ets`，AppStorage：`dbRevision` 与 `uiTab/uiTodoPane/uiSheet/uiSub/uiQuoteId/uiPlanDate`；`bumpRevision()` 是全局刷新总线，各视图 `@Watch('onRev')` 重拉；导航动作走 `UIContext.getRouter()` |
| 数据层 | `entry/src/main/ets/db/`，SQLite `databases/jianyi.db`，DB v2：9 张表 + 9 个仓库 + `Seed.ets` 示例数据 |
| 微光模块 | `db/GrowthRepo.ets` + `common/GrowthTag.ets`（本地推断）+ `common/GrowthAnalysis.ets`（现算统计）+ `view/GrowthCard.ets`（一步录入）+ `view/GrowthView.ets`（回顾），设计取舍见 3.6 |
| 通知提醒 | `common/Reminder.ets`（每晚回顾）+ `common/BizReminder.ets`（待办汇总 / 习惯 / 日程）+ `module.json5` 的 `PUBLISH_AGENT_REMINDER` 权限；reminderId 映射存 Preferences `jianyi_meta` |
| 应用图标 | `design/generate_icon.py` 生成；AppScope 与 entry **两套**分层资源 + `startIcon.png`，见 3.5 |
| 视觉常量 | `common/Theme.ets`（纸墨色板），页面与图标都禁止散落十六进制色值 |
| 参考留档 | `harmony-data/` 是设计参考，**不参与编译**；实际编译的是 `entry/src/main/ets/db/` |

三条贯穿全局的数据规则：UUID 主键、软删除（`deleted_at`）、派生数据查询时现算。

## 3. 已经踩过的坑

### 3.1 静态检查不能替代真编译（2026-11-12）

- 本机没有 HarmonyOS SDK（`DEVECO_SDK_HOME` / `hvigorw` 都没有），Agent 只做了括号平衡、相对导入、装饰器字面量、未使用导入的静态检查。
- 用户把工程放进 DevEco Studio 后遇到编译问题，**Studio 端修复后已在手机上看到应用预览**，随后提交为首轮完整编译版本。
- 教训：ArkTS 严格模式下，接口名一律以当前 SDK 的 `.d.ts` 为准；`@StorageLink` / `@Watch` 等装饰器参数用字符串字面量，不要用变量；写完必须明确告诉用户「未编译验证，请在 Studio 里跑一次」。

### 3.2 系统返回键一按就回桌面（诊断结论）

现象：在手机上按返回 / 侧滑返回，应用直接退到桌面，看起来像闪退。

根因（三点同时成立）：

1. `main_pages.json` 只注册了 `pages/Index` **一个页面**；
2. 五个主视图、全局搜索、快速录入弹层、四个二级页，全是 `Index` 内靠 AppStorage `ui*` 状态做的**条件渲染覆盖层**，不是页面 —— 没有页面路由，也没有 `Navigation` 栈；
3. 当时 `Index.ets` 没有 `onBackPress`，没人接管系统返回事件。

于是系统一看「页面栈只有一页、无历史可退」，直接把 UIAbility 送到后台（`onBackground`），屏幕就是桌面。**不是崩溃，进程还活着、本地数据没丢**，点图标回来状态仍在。切 tab 同样不进返回栈，所以按返回也不会回到上一个 tab。

**修法分两步（各算一次提交）**：

1. 2026-11-12：`Index` 加 `onBackPress(): boolean` 逐层消费返回（`录入弹层 → 搜索 → 二级页 → 回今日 → 二次退出`）+ 系统 Toast 提示，先让返回键可用。
2. 2026-11-13：把搜索与二级页拆成独立 `@Entry` 页面并注册，导航改为 push / back，由**系统页面栈**逐层 pop；`Index.onBackPress` 只负责录入弹层、回今日、二次退出。单页覆盖层正式退役。

**真机反馈（2026-11-13 晚）**：用户在手机上确认「返回分别返回到不同的地方，最终退出的时候也有提示」—— 逐层回退与二次退出 Toast 的行为目标已达成，「一按返回就回桌面」的问题解决。本次反馈只覆盖导航与返回；通知提醒、AGC 代理提醒、启动窗口观感未被提及，仍按 3.4 / 第 4 节保持「待真机验证」，不要顺手把整批改动标成已验证。

### 3.3 其他已验证的排错点

- `book.percent` 是 `REAL` 列，`RowUtil` 要走 `getDouble`；用 `getLong` 会把 0.40 读成 0。
- 首次启动示例数据用 Preferences 打标，用户删掉的记录不会在重启后复活；发布前置 `SEED_ENABLED = false`。
- 系统 Toast 若报接口名差异：`promptAction.showToast({...})` 与 `this.getUIContext().getPromptAction().showToast({...})` 二选一，按 SDK `.d.ts` 校正。
- **静态 `router.pushUrl` / `router.back` 自 API 18 起废弃**（官方推荐 `Navigation`）。本工程 API 24，统一改走 `UIContext.getRouter().pushUrl(...) / back()`；`import { router } from '@kit.ArkUI'` 现在只用来取 `router.RouterOptions` 类型。UIContext 由各 `@Entry` 页面的 `onPageShow` 挂到 `Bus.ets` 单例。
- 全局弹层 `QuickSheet` 不是页面：它在 Index 与 SubPage 各渲染一份，靠 `uiSheet` 显隐；SubPage 的 `onBackPress` 必须先关弹层（`return true`），再按一次才让系统 pop 页面。
- 二级页类型 `uiSub` / 摘录 id `uiQuoteId` 是跨页面参数，`openSub` 先写值再 push；**返回时不要提前清空**，否则 pop 动画里会闪成空白，下次打开会覆盖。
- 深色资源与 base 保持一致（纸色主题不随系统深浅模式翻转），避免启动窗口闪黑。

### 3.4 后台代理提醒：三道开关缺一不可（2026-11-13）

`reminderAgentManager.publishReminder` 运行时报 1700001 / 1700002，通常不是代码错，而是下面某一步没做：

1. `module.json5` 声明 `ohos.permission.PUBLISH_AGENT_REMINDER`（配 `$string:reminder_permission_reason`）；
2. 用户通知授权：`notificationManager.isNotificationEnabledSync()` 检查、`requestEnableNotification(context)` 弹窗。**用户拒绝后系统不会再弹窗**，只能文字引导去系统设置，别反复调用；
3. **AGC 项目设置 → 开放能力管理 → 勾选「代理提醒」→ 重新生成 Profile → 手动签名**。自动签名不带这个管控能力，权限不生效、配额为 0，表现就是 `publishReminder` 报 1700002。真机调试前一定要先确认这一步。

接口已核对（本工程 API 24）：`notificationManager` 从 `@kit.NotificationKit` 导入，`reminderAgentManager` 从 `@kit.BackgroundTasksKit` 导入；`ReminderRequestAlarm` 用 `hour/minute/daysOfWeek[1..7]` 做每日重复，`ReminderRequestCalendar` 用 `dateTime` 做一次性提醒；`publishReminder(req).then((id: number) => ...)` 返回 reminderId，**`cancelReminder(id)` 有 Promise 重载**（官方 V14 指南已确认，可直接 `await`）。
`actionButton` 在不同资料里有 `actionButton` / `actionButtons` 单复数差异，本项目暂不使用这个可选字段，避免卡在字段名上。
**通知失败绝不能阻断写库**，调用方 `.catch()` 记日志即可。

**业务提醒（2026-11-16 接入，`common/BizReminder.ets`）**：待办 / 习惯 / 日程三类已接代理提醒，设计取舍——

- **待办是「汇总提醒」不是每条一条**：快速录入给今日待办的截止时间默认都是当天 18:00，按条发会在同一时刻弹一串通知。汇总只发一条（`todo_summary_reminder_id` 单 key）：最迫近的未来 `dueAt` 时刻 + 剩余数量，新增 / 勾选 / 取消勾选后重算，清空自动取消。调用点：`QuickSheet` 存今日待办后、`TodoView.toggle` 勾选后。
- **习惯是每日 ALARM**（`habit_rem_<habitId>`）：每天 `remindAt` 时刻响；**打卡后当日不会静音**（alarm 型做不到跳过单日，已知取舍）；**每周习惯不发**（表里没有「周几」字段）。
- **日程是一次性 CALENDAR**（`event_rem_<eventId>`）：`startAt` 时刻响，已过不发。
- **授权策略**：只在通知**已授权**时静默发布（`isNotificationEnabledSync`），写库路径绝不调 `requestEnableNotification` 弹窗——授权入口仍是今日页「每晚回顾提醒」开关；被拒过就静默跳过。
- reminderId 映射存 Preferences `jianyi_meta`，不动表结构（P1 说的「字段已就绪」即指无需 DB v3）。
- 待办 / 习惯 / 日程目前**没有删除 UI**（`removeTodo` / `removeHabit` / `removeEvent` 仓库接口在但无人调用），所以「删除时取消提醒」的钩子等删除 UI 落地时再接，别漏。

**真机怎么验证（2026-11-13）**：代理提醒由系统到点发出，不在 App 内弹窗，光看界面看不出来。按顺序做：

1. 今日页下滑找到「每晚回顾提醒」卡片，打开开关。**开关能保持打开、且卡片没出现「没能开启」红字 = `publishReminder` 返回了 reminderId**，说明权限 + AGC 能力 + 签名三道全通 —— 这一步已经排除绝大多数问题。
2. DevEco Studio 的 HiLog 过滤 `Reminder`：正常应无输出；`publish reminder failed: 1700002` = AGC「代理提醒」没开通或 Profile 没重签；`request notification failed` = 用户拒绝过授权，只能去「系统设置 → 应用 → 简忆 → 通知」手动打开。
3. 想看到通知真的弹出，三选一：等到 20:30；把手机系统时间调到 20:29 等一分多钟（需先关「自动确定时间」）；或临时把 `REVIEW_HOUR` / `REVIEW_MINUTE` 改成当前时刻 +2 分钟，重新编译安装一次，验完改回 `20` / `30`。
4. 打开开关后**把 App 从后台划掉**，到点仍应收到 —— 这一步才验证「系统代理」而不是 App 自己弹的。
5. 杀进程重进，开关应保持开启（Preferences `jianyi_meta` 持久化）。

### 3.5 应用图标：分层资源与两处引用（2026-11-13）

HarmonyOS 的桌面图标是**分层资源**，不是一张图：

- `background.png`：1024×1024 **RGB 纯色不透明**，无文字、无透明像素、无手动圆角、无内边距。
- `foreground.png`：1024×1024 RGBA，只保留核心图形，其余区域 100% 透明。当前图形边界 `(259,221)-(765,803)`（简牍方案），中心 `(512,512)`，居中留足安全区。
- 系统会自动套圆形 / 圆角方形遮罩并裁切，**不要自己给资源裁圆角**。智能穿戴另有 152×152 单层规范，本工程暂未适配。
- `startIcon.png`（152×152，启动窗口中央）是**独立资源**，也要一起换；`startWindowBackground = #F6F2E9` 与图标底色相同，启动不闪色。

工程里 `AppScope/resources/base/media/` 与 `entry/src/main/resources/base/media/` **各有一套**同名文件，各自被 `layered_image.json` 引用；`app.json5` 和 `module.json5` 的 `icon` 都写 `$media:layered_image`。**module.json5 的 icon 优先级高于 app.json5**，只换一套会出现「桌面是新图标、应用列表还是旧图标」，上架审核也会以「未配置前景图/背景图」驳回。生成脚本已保证两套哈希一致。

设计落地在 `design/generate_icon.py`（Pillow，仅构建期依赖，不进 App），色值抄自 `Theme.ets` / `color.json`；三个方案一条命令切换，运行后同时刷新两套工程资源、`startIcon.png`、`design/icon-preview.png`、`design/icon-full.png`：

```bash
python design/generate_icon.py                  # slips 简牍·三简一绳（当前落地，用户 11-13 选定）
python design/generate_icon.py --scheme seal   # seal  朱印·白文「简」
python design/generate_icon.py --scheme page   # page  墨页·一页记录
```

2026-11-13 用户看过三方案预览后选定「**简牍**」为落地方案，脚本默认值已同步改为 `slips`；无参数重跑不会退回朱印。`make_preview()` 的底部尺寸样例跟着 `--scheme` 走，不会出现「卡片是 A 方案、效果展示是 B 方案」。

朱印方案的「简」字用 `STZHONGS.TTF`（华文中宋）：宋体横细竖粗最接近白文印，且比普通宋体耐缩小；脚本内置多平台字体 fallback。**换机器重新生成时若命中不同字体，字形会变**，`design/icon-full.png` 必须一起更新；简牍 / 墨页是纯几何图形，不受字体影响。图标资源是 PNG，不参与 ArkTS 编译，也不受「本机无 SDK」限制。

### 3.6 微光模块：结构后置，别把成本转嫁给录入（2026-11-13）

- 「多小的事都算」与「以后能分析」天然冲突。解法：**录入只收一句话**，维度与数值由 `common/GrowthTag.ets` 本地推断，用户不选也能存（未分类落 NULL），回顾页还能补标；统计全部由 `common/GrowthAnalysis.ets` 现算，不落库。
- 不做评分、目标、断签提醒、排行榜，也不写「你进步了 X%」这类评判。App 只把证据摆整齐，判断留给本人。
- 数据库从 v1 升到 v2：`JianYiDb.ets` 追加 `DDL_V2` 并在 `migrate()` 里按 `current < 2` 执行，**不要改建表语句**；REAL 可空列必须 `getDouble`（已加 `RowUtil.realOrNull`），用 `getLong` 会把小数读成 0。
- 示例数据用**独立标记** `growth_seeded_v1`：老用户升级只补微光，不会因为动 `demo_seeded_v1` 而重复灌入语录 / 待办。
- 回顾页是第 4 个 `@Entry` 页面；搜索结果点「微光」时不 pop 搜索页、直接 push 回顾页，返回时回到刚才的搜索结果，符合系统页面栈语义。
- 二期（未做）：桌面服务卡片 / 长按图标快捷方式实现真正的「随时随地」、通知点击直达录入、数值累计展示。这些都是**系统能力**，别用自绘按钮糊弄过去。

### 3.7 ForEach 的 key 必须带上展示字段与交互状态（2026-11-16 真机反馈）

**现象**：微光回顾页点维度标签没反应，补标选了新维度后那一行还显示旧标签。写库是成功的（`updateGrowthCategory` 正常），`load()` 也重拉了数据，HiLog 一条错都没有。

**根因**：`ForEach(arr, itemBuilder, keyGenerator)` 非首次渲染时**只按 key 判断能否复用组件**。原实现 key 只有不变的 `row.id` / `group.date`：

- key 相同 → 复用旧组件 → itemBuilder 不重跑 → `if (this.editingId === row.id)` 不重新求值，补标面板压根不展开；
- 改了 `category` 但 id 不变 → 复用旧组件 → 标签文本还是闭包里旧 `row` 的值。

这就是华为开发者博客描述的「数据改了、列表不刷新，而且一条报错都不产生」。`@State` 只观察第一层也救不了：即使 `groups` 整个换成新数组，key 没变照样复用。**界面没变但库里变了，先查 ForEach 第三个参数，别去改数据层。**

**第一版修法（不够，当天被真机否掉）**：加了 `@State listVersion` 并把它拼进 keyGenerator。用户反馈「切换标签不是实时变，要返回重进才看到」——**keyGenerator 里读组件状态变量不建立可靠依赖**，框架未必重算 key；只有返回重进触发首次渲染才拿到新数据。

**正解：keyGenerator 必须是纯函数，只读 item 自身字段；把变化信息编进数据源对象。**

- `GrowthView` 用 `GrowthItem { row, viewKey }` / `GrowthDayGroup { date, items, viewKey }` 包装数据。`itemKey = ${id}|${categoryLabel(category)}|${updatedAt}|${展开状态}` —— 补标会写 `updated_at`，所以维度一改 key 必变；`group.viewKey` 再汇总组内所有行，任一行变化整组换 key → 外层重建 → 内层拿到新数据。
- `load()` 缓存 `allRows`；点标签时 `this.groups = this.makeGroups(this.allRows)` **同步重算 viewKey、不读库**，展开/收起立即生效。
- 维度分布 / 热力 / 补标选项的 key 全部改成纯 item 字段（`name|count`、`index|count`、`line.join(',')`），不再引用任何 `this.*`。
- 补标选项给当前维度加深色高亮；`QuickSheet.miniChips` 的 key 从 `kind + opt` 改成 `${kind}|${opt}|${current}`，录入弹层 chips 选中态才会变。

**两条官方约束**：keyGenerator 是纯函数，**不要读组件状态变量、更不能改变组件状态**；itemGenerator 与 keyGenerator 是否声明 `index` 必须一致，否则框架会在返回值后自动拼 index。本项目几处 ForEach 两边对称。key 里不要塞与渲染无关的字段，会导致每帧重建。

**排查顺序**：界面没变但库里变了 → 先查 ForEach 第三个参数是不是纯函数、有没有带展示字段，别去改数据层；确认数据没重拉，再查 `dbRevision` 总线。

### 3.8 页面刷新机制：自动总线 + 原生下拉手势

- **全局自动刷新**：任何写库成功后调 `bumpRevision()`（`common/Bus.ets`），各视图的 `@StorageLink('dbRevision') @Watch('onRev')` 自动重拉数据；`Index.onPageShow` 回前台也会 bump 一次。**正常情况下用户不需要手动刷新**。
- **显式刷新**：回顾页用 ArkUI 原生 `Refresh` 组件包住 `Scroll`，`@State refreshing` 走 `$$` 双向绑定，`onRefreshing` 里 `load()` 结束后复位（成功/失败都要复位，否则刷新头收不回去）。这是系统手势，不是自绘按钮。
- 下拉刷新目前只在 `GrowthView` 落地；其它视图根组件结构不一（TodayView 是 `Scroll`，其余多为 `List` / 自定义容器），推广时逐个套，别一次性批量替换。

### 3.9 状态栏与安全区：组件级背景沉浸（2026-11-16）

**问题**：窗口默认非沉浸式，状态栏 / 手势条避让区由系统上色，与纸色页面割裂；且窗口默认底色在系统深色模式下是 `#FF1A1A1A`，页面转场 / 首帧可能闪黑（违反「切深浅色不闪黑」验收标准）。

**方案**（官方最佳实践「组件设置背景沉浸」，全工程 4 个页面根组件 + EntryAbility 各改一处，零手动避让计算）：

- 页面根组件用 `.background(C.paper)` 而非 `.backgroundColor(C.paper)`——`background()` 的 ResourceColor 重载自 API 20 起支持，且背景会**自动延伸进状态栏 / 手势条避让区**，内容仍留在安全区内，刘海 / 手势条 / 折叠屏 / 横竖屏全部自动适配。前提是组件与安全区边界重合（4 个页面根都是 100%×100%，满足）。**别顺手把它改回 `backgroundColor`**，那会退回「避让区系统上色」的割裂效果。
- `EntryAbility.onWindowStageCreate` 里 `getMainWindowSync()` 后：`setWindowBackgroundColor(C.paper)`（堵深色模式转场闪黑）+ `setWindowSystemBarProperties({ statusBarContentColor: C.ink, navigationBarContentColor: C.ink })`（状态栏时间 / 电量图标墨色压在纸底上可读）。
- **签名核对过本机 SDK `.d.ts`**：`setWindowBackgroundColor` 是同步 `void`（不能 `.catch`），`setWindowSystemBarProperties` 返回 `Promise<void>`。

**没选窗口级全屏（`setWindowLayoutFullScreen` + 手动 `getWindowAvoidArea` 避让）的原因**：纯色背景页面两种方案视觉效果完全一致，组件级改动小、无 inset 插值、无 `avoidAreaChange` 监听，风险低得多。以后若要「内容滚动到状态栏底下」的效果再升级。

**真机验证清单**：状态栏时间 / 电量呈墨色且底色为纸色无缝；底部手势条区域纸色、tab 标签不被遮挡；系统切深色模式后启动 / 页面转场不闪黑；录入弹层（QuickSheet）键盘弹出正常。`devecocli build` 已通过，效果待真机确认。

**3.1 附注（2026-11-16）**：本机 Agent 环境已装 DevEco Studio 26.0（`DEVECO_HOME=D:\Program Files\Huawei\DevEco Studio`）与 `devecocli`，`arkts_check` + `devecocli build` 全流程可用，3.1「本机无法真编译」的说法已过时；但「接口名以 SDK `.d.ts` 为准」的教训仍然有效。

## 4. 系统能力清单（当前状态）

| 能力 | 状态 | 说明 |
|---|---|---|
| 系统返回键 / 侧滑返回 | ✅ 已接，行为已真机确认 | 搜索页 / 二级页由系统页面栈自动 pop；`Index.onBackPress` 管录入弹层、回今日、二次退出 Toast；11-13 真机确认逐层返回与退出提示 |
| 真实页面栈与系统转场 | ✅ 已做并真机确认（router） | 3 个 `@Entry` 页面 + `main_pages.json`；`UIContext.getRouter()` push / back |
| 前后台 / 页面生命周期 | 🟡 部分 | `EntryAbility` 有 onForeground/onBackground、onCreate 预热 DB；三个页面 `onPageShow` 挂 UIContext，Index 回来刷新数据 |
| 本地持久化 | ✅ | RelationalStore + Preferences，断网可用 |
| 页面数据刷新 | ✅ 全局自动；下拉刷新部分 | 写库 → `bumpRevision()` → 各视图 `@Watch('onRev')` 重拉；回顾页另有原生 `Refresh` 下拉手势，其它页面待推广，见 3.8 |
| 迁移 Navigation / NavPathStack | ⬜ 待做 | router 体系官方已不推荐；`Navigation` 支持分栏、路由拦截、引用传参 |
| 状态栏 / 安全区 / 沉浸式 | 🟡 已做（组件级背景沉浸），待真机验证 | 4 个页面根 `.background(C.paper)` + EntryAbility 窗口底色 / 状态栏墨色图标，见 3.9 |
| 通知提醒 | 🟡 已实现（每晚回顾 + 业务提醒），待真机验证 | `Reminder.ets`：每晚 20:30 代理提醒 + 今日页开关；`BizReminder.ets`：待办汇总 / 习惯每日 / 日程一次性，见 3.4；真机前需 AGC 开通能力 |
| 桌面图标 / 启动窗口 | ✅ 已做，真机已确认 | 分层图标两层 1024² + `startIcon` 152²，纸墨风三方案可切换；11-13 用户确认桌面图标已变成简牍方案，见 3.5 |
| 电子书正文 | 🟡 | 书架与进度已接库，正文解析待 Reader Kit |
| 云备份与导出 | ⬜ | `EntryBackupAbility` 骨架已有，导出逻辑待写 |
| 微光 · 随手记与回顾 | 🟡 真机已能运行，补标待复验 | `growth` 表 + 今日页一步录入 + 独立回顾页 + 搜索接入；11-16 用户真机确认 DB v2 迁移、页面跳转、录入都正常，仅回顾页补标无反应（ForEach key，见 3.7，已修未复验）。设计取舍见 3.6 |
| 桌面服务卡片 / 图标快捷方式 | ⬜ 未做 | 微光二期的「随时随地」入口，需 `FormExtensionAbility` / shortcuts，属系统能力 |

**下一步优先级**：P1 微光二期（桌面卡片 + 通知点击直达录入）；P2 Reader Kit 正文、备份导出、月度成长小结导出、待办/习惯/日程的删除 UI（落地时记得接「删除取消提醒」钩子，见 3.4）；P3 迁移 `Navigation` + `NavPathStack`（router 已真机验证，只是 API 现代化，不急）。
（11-12 定的 P0「真实页面栈」已于 11-13 用 router 方案落地，**11-13 晚真机确认行为达标**；迁移 `Navigation` 因此只是 API 现代化，不再紧急，别在功能还没铺完时急着动它。按 project_rules 7「一次提交只做一件事」留作单独一轮。）

## 5. 给 Agent 的工作准则

1. **改文件前先重新 Read**。用户会在 DevEco Studio 里手动修代码（已经发生过一次），不要拿记忆里的旧内容去 `Edit`；`old_string` 一律以磁盘现状为准。改完顺手看 `git status` 确认没碰到用户自己的工作。
2. 不引入第三方 UI 框架、npm 运行时依赖，不引入 WebView 承载业务 UI（project_rules 2 + 本文第 1 节）。
3. 做交互前先问一句：**这是系统能力还是界面自绘？** 系统能力优先用 Kit / 生命周期 / 路由栈，别习惯性画个按钮了事。
4. 本机可用 `arkts_check` + `devecocli build` 编译验证（见 3.1 附注）；改完先 `arkts_check` 再 `devecocli build`。静态自检仍要看：相对导入路径、装饰器参数为字面量、无未使用导入、可空类型处理、新增页面是否同步 `main_pages.json`。
5. 改数据层遵守 `DB_VERSION + 1` 与 `migrate()`，禁止改建表语句；页面里不出现 SQL。
6. 原型与代码不一致时以 `jianyi-prototype.html` 为准并同步代码（project_rules 6），但**原型只是设计参考，不是运行时**。
7. 完成实质工作后把结论追加到 `.workbuddy/memory/YYYY-MM-DD.md`；用户表达的长期偏好另写 `.workbuddy/memory/MEMORY.md`。**不要删除 `.workbuddy/` 目录**。
8. 提交信息沿用 `feat: / fix: / refactor: / docs:`，一次提交只做一件事。
9. **提交后直接推送远程**（用户 2026-11-13 明确）：commit 完紧接着 `git push origin main`，不要只留本地提交等用户来问。远端 `https://github.com/libliam/jian-yi-harmony.git`，分支 `main`。推送前确认 `.sign` / `local.properties` / build 产物已被 `.gitignore` 排除；若因网络或凭据失败，如实报告，不要擅自换协议或 force push。
