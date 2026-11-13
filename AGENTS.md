# AGENTS.md · 简忆（JIAN YI）

> 给 AI 编码助手 / Agent 的项目速查与踩坑记录。
> **长期约定以 [`.trae/rules/project_rules.md`](./.trae/rules/project_rules.md) 为准**，本文件不重复规则，只写「怎么在这里干活」和「已经踩过的坑」。
> 背景资料：[`README.md`](./README.md)、[`.workbuddy/memory/`](./.workbuddy/memory/)。

---

## 0. 一句话

简忆是**要装到手机上的 HarmonyOS NEXT 原生应用**（ArkTS + ArkUI，Stage 模型），本地优先的个人心智工具：记下值得记住的句子、安排今天要做的事、读完手里的书。

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
| 编译 | DevEco Studio 5.0+；**本机没有 SDK / hvigorw，Agent 无法真编译** |
| 入口 Ability | `entry/src/main/ets/entryability/EntryAbility.ets` → `loadContent('pages/Index')` |
| 页面注册 | `entry/src/main/resources/base/profile/main_pages.json`（3 个页面，Index 第一为启动页） |
| 主页面 | `entry/src/main/ets/pages/Index.ets`（页面栈底） |
| 独立页面 | `pages/SearchPage.ets`（搜索）、`pages/SubPage.ets`（习惯/心情/摘录/阅读） |
| 五个主视图 | `view/TodayView / QuoteView / TodoView / ReaderView / PlanView` |
| 全局弹层 | `view/QuickSheet`（录入），在 Index 与 SubPage 各渲染一份，靠 `uiSheet` 控制 |
| 状态总线 | `common/Bus.ets`，AppStorage：`dbRevision` 与 `uiTab/uiTodoPane/uiSheet/uiSub/uiQuoteId/uiPlanDate`；导航动作走 `UIContext.getRouter()` |
| 数据层 | `entry/src/main/ets/db/`，SQLite `databases/jianyi.db`，7 张表 + 9 个仓库 + `Seed.ets` 示例数据 |
| 通知提醒 | `common/Reminder.ets` + `module.json5` 的 `PUBLISH_AGENT_REMINDER` 权限；开关与 reminderId 存 Preferences `jianyi_meta` |
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
**通知失败绝不能阻断写库**，调用方 `.catch()` 记日志即可。本轮只做了「每晚回顾提醒」一个闭环，待办 `dueAt` / 习惯 `remindAt` / 日程 `startAt` 的业务提醒留到下一轮（字段已就绪）。

### 3.5 应用图标：分层资源与两处引用（2026-11-13）

HarmonyOS 的桌面图标是**分层资源**，不是一张图：

- `background.png`：1024×1024 **RGB 纯色不透明**，无文字、无透明像素、无手动圆角、无内边距。
- `foreground.png`：1024×1024 RGBA，只保留核心图形，其余区域 100% 透明。当前图形边界 `(199,199)-(825,825)`，居中留足安全区。
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

## 4. 系统能力清单（当前状态）

| 能力 | 状态 | 说明 |
|---|---|---|
| 系统返回键 / 侧滑返回 | ✅ 已接 | 搜索页 / 二级页由系统页面栈自动 pop；`Index.onBackPress` 管录入弹层、回今日、二次退出 Toast |
| 真实页面栈与系统转场 | ✅ 已做（router） | 3 个 `@Entry` 页面 + `main_pages.json`；`UIContext.getRouter()` push / back |
| 前后台 / 页面生命周期 | 🟡 部分 | `EntryAbility` 有 onForeground/onBackground、onCreate 预热 DB；三个页面 `onPageShow` 挂 UIContext，Index 回来刷新数据 |
| 本地持久化 | ✅ | RelationalStore + Preferences，断网可用 |
| 迁移 Navigation / NavPathStack | ⬜ 待做 | router 体系官方已不推荐；`Navigation` 支持分栏、路由拦截、引用传参 |
| 状态栏 / 安全区 / 沉浸式 | ⬜ 未做 | 目前依赖默认非沉浸式窗口，需按真机刘海与手势条验证 |
| 通知提醒 | 🟡 已实现，待真机验证 | `common/Reminder.ets`：每晚 20:30 系统代理提醒 + 今日页开关 + 通知授权；真机前需 AGC 开通能力，见 3.4 |
| 桌面图标 / 启动窗口 | ✅ 已做 | 分层图标两层 1024² + `startIcon` 152²，纸墨风三方案可切换，见 3.5 |
| 电子书正文 | 🟡 | 书架与进度已接库，正文解析待 Reader Kit |
| 云备份与导出 | ⬜ | `EntryBackupAbility` 骨架已有，导出逻辑待写 |

**下一步优先级**：P0 迁移 `Navigation` + `NavPathStack`（把 router 页面栈换成官方推荐的组件导航，顺带处理弹层的路由拦截与分栏适配）；P1 状态栏与安全区、把定时提醒接到待办 `dueAt` / 习惯 `remindAt` / 日程 `startAt`（数据字段已就绪，关闭待办时 `cancelReminder`）；P2 Reader Kit 正文、备份导出。
（11-12 定的 P0「真实页面栈」已于 11-13 用 router 方案先落地，行为已达标，剩下是 API 现代化；按 project_rules 7「一次提交只做一件事」留作单独一轮。）

## 5. 给 Agent 的工作准则

1. **改文件前先重新 Read**。用户会在 DevEco Studio 里手动修代码（已经发生过一次），不要拿记忆里的旧内容去 `Edit`；`old_string` 一律以磁盘现状为准。改完顺手看 `git status` 确认没碰到用户自己的工作。
2. 不引入第三方 UI 框架、npm 运行时依赖，不引入 WebView 承载业务 UI（project_rules 2 + 本文第 1 节）。
3. 做交互前先问一句：**这是系统能力还是界面自绘？** 系统能力优先用 Kit / 生命周期 / 路由栈，别习惯性画个按钮了事。
4. 本机不做编译；交付前做静态自检：括号平衡、相对导入路径、装饰器参数为字面量、无未使用导入、可空类型处理、新增页面是否同步 `main_pages.json`。并在回复里明确标注「未编译验证」。
5. 改数据层遵守 `DB_VERSION + 1` 与 `migrate()`，禁止改建表语句；页面里不出现 SQL。
6. 原型与代码不一致时以 `jianyi-prototype.html` 为准并同步代码（project_rules 6），但**原型只是设计参考，不是运行时**。
7. 完成实质工作后把结论追加到 `.workbuddy/memory/YYYY-MM-DD.md`；用户表达的长期偏好另写 `.workbuddy/memory/MEMORY.md`。**不要删除 `.workbuddy/` 目录**。
8. 提交信息沿用 `feat: / fix: / refactor: / docs:`，一次提交只做一件事。
9. **提交后直接推送远程**（用户 2026-11-13 明确）：commit 完紧接着 `git push origin main`，不要只留本地提交等用户来问。远端 `https://github.com/libliam/jian-yi-harmony.git`，分支 `main`。推送前确认 `.sign` / `local.properties` / build 产物已被 `.gitignore` 排除；若因网络或凭据失败，如实报告，不要擅自换协议或 force push。
