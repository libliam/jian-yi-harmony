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
- 导航要有**真实页面栈**（`Navigation` 或 router），让系统返回自然逐层回退。当前用单页 + 条件渲染覆盖层的做法是**过渡实现，不是终态**，见第 4 节。
- 验收标准：断网可用、清后台再进数据还在、系统返回逐层退、切深浅色不闪黑、启动窗口不白屏 —— 行为像系统应用，而不是像浏览器标签页。
- 优先级（沿用 project_rules 1）：**能每天用 > 功能多**，单人本地使用，不做账号、不做社交。

## 2. 工程速查

| 项 | 值 |
|---|---|
| 平台 | HarmonyOS NEXT，`compatibleSdkVersion 6.1.1(24)`，`targetSdkVersion 26.0.1` |
| 编译 | DevEco Studio 5.0+；**本机没有 SDK / hvigorw，Agent 无法真编译** |
| 入口 Ability | `entry/src/main/ets/entryability/EntryAbility.ets` → `loadContent('pages/Index')` |
| 页面注册 | `entry/src/main/resources/base/profile/main_pages.json` |
| 主页面 | `entry/src/main/ets/pages/Index.ets`（目前唯一 `@Entry`） |
| 五个主视图 | `view/TodayView / QuoteView / TodoView / ReaderView / PlanView` |
| 覆盖层 | `view/SearchPanel`（搜索）、`view/QuickSheet`（录入）、`view/SubPages`（习惯/心情/摘录/阅读） |
| 状态总线 | `common/Bus.ets`，AppStorage：`dbRevision` 与 `uiTab/uiSearch/uiSheet/uiSub/uiQuoteId/uiPlanDate/uiTodoPane` |
| 数据层 | `entry/src/main/ets/db/`，SQLite `databases/jianyi.db`，7 张表 + 9 个仓库 + `Seed.ets` 示例数据 |
| 视觉常量 | `common/Theme.ets`（纸墨色板），页面禁止散落十六进制色值 |
| 参考留档 | `harmony-data/` 是设计参考，**不参与编译**；实际编译的是 `entry/src/main/ets/db/` |

三条贯穿全局的数据规则：UUID 主键、软删除（`deleted_at`）、派生数据查询时现算。

## 3. 已经踩过的坑（2026-11-12 · 真机预览这一轮）

### 3.1 静态检查不能替代真编译

- 本机没有 HarmonyOS SDK（`DEVECO_SDK_HOME` / `hvigorw` 都没有），Agent 只做了括号平衡、相对导入、装饰器字面量、未使用导入的静态检查。
- 用户把工程放进 DevEco Studio 后遇到编译问题，**Studio 端修复后已在手机上看到应用预览**。
- 教训：ArkTS 严格模式下，接口名一律以当前 SDK 的 `.d.ts` 为准；`@StorageLink` / `@Watch` 等装饰器参数用字符串字面量，不要用变量；写完必须明确告诉用户「未编译验证，请在 Studio 里跑一次」。

### 3.2 系统返回键一按就回桌面（诊断结论）

现象：在手机上按返回 / 侧滑返回，应用直接退到桌面，看起来像闪退。

根因（三点同时成立）：

1. `main_pages.json` 只注册了 `pages/Index` **一个页面**；
2. 五个主视图、全局搜索、快速录入弹层、四个二级页，全是 `Index` 内靠 AppStorage `ui*` 状态做的**条件渲染覆盖层**，不是页面 —— 没有 `router.pushUrl`，也没有 `Navigation` 栈；
3. 当时 `Index.ets` 没有 `onBackPress`，没人接管系统返回事件。

于是系统一看「页面栈只有一页、无历史可退」，直接把 UIAbility 送到后台（`onBackground`），屏幕就是桌面。**不是崩溃，进程还活着、本地数据没丢**，点图标回来状态仍在。切 tab 同样不进返回栈，所以按返回也不会回到上一个 tab。

应用内当时只能靠界面控件返回：二级页左上角 `‹`（`closeSub()`）、搜索框「取消」（`closeSearch()`）、录入弹层点遮罩或「取消」（`closeSheet()`）。

**本轮修法**：在 `Index` 实现 `onBackPress(): boolean`，按 `录入弹层 → 搜索 → 二级页 → 非今日 tab 回今日 → 2 秒内二次返回才退出` 逐层消费事件（返回 `true` 拦截、`false` 交给系统），并用系统 Toast 提示。这是过渡方案；终态仍是真实页面栈。

### 3.3 其他已验证的排错点

- `book.percent` 是 `REAL` 列，`RowUtil` 要走 `getDouble`；用 `getLong` 会把 0.40 读成 0。
- 首次启动示例数据用 Preferences 打标，用户删掉的记录不会在重启后复活；发布前置 `SEED_ENABLED = false`。
- 系统 Toast 若报接口名差异：`promptAction.showToast({...})` 与 `this.getUIContext().getPromptAction().showToast({...})` 二选一，按 SDK `.d.ts` 校正。
- 深色资源与 base 保持一致（纸色主题不随系统深浅模式翻转），避免启动窗口闪黑。

## 4. 系统能力清单（当前状态）

| 能力 | 状态 | 说明 |
|---|---|---|
| 系统返回键 / 侧滑返回 | ✅ 已接（过渡） | `Index.onBackPress` 逐层退出 + 二次确认；终态换成真实页面栈 |
| 前后台 / 页面生命周期 | 🟡 部分 | `EntryAbility` 有 onForeground/onBackground、onCreate 预热 DB；`Index.onPageShow` 回来刷新数据 |
| 本地持久化 | ✅ | RelationalStore + Preferences，断网可用 |
| 真实页面栈与系统转场 | ⬜ 未做 | 下一步用 `Navigation` + `NavPathStack` 替换覆盖层，或 router + 独立 `@Entry` 页面 |
| 状态栏 / 安全区 / 沉浸式 | ⬜ 未做 | 目前依赖默认非沉浸式窗口，需按真机刘海与手势条验证 |
| 通知提醒 | ⬜ | `notificationManager`，路线图第 5 步，需真机 |
| 电子书正文 | 🟡 | 书架与进度已接库，正文解析待 Reader Kit |
| 云备份与导出 | ⬜ | `EntryBackupAbility` 骨架已有，导出逻辑待写 |

**下一步优先级**：P0 真实页面栈（连带把覆盖层的打开/关闭改成 push/pop，同步 `main_pages.json` 或 `Navigation` 映射）；P1 状态栏与安全区、通知；P2 Reader Kit 正文、备份导出。

## 5. 给 Agent 的工作准则

1. **改文件前先重新 Read**。用户会在 DevEco Studio 里手动修代码（已经发生过一次），不要拿记忆里的旧内容去 `Edit`；`old_string` 一律以磁盘现状为准。
2. 不引入第三方 UI 框架、npm 运行时依赖，不引入 WebView 承载业务 UI（project_rules 2 + 本文第 1 节）。
3. 做交互前先问一句：**这是系统能力还是界面自绘？** 系统能力优先用 Kit / 生命周期 / 路由栈，别习惯性画个按钮了事。
4. 本机不做编译；交付前做静态自检：括号平衡、相对导入路径、装饰器参数为字面量、无未使用导入、可空类型处理、新增页面是否同步 `main_pages.json`。并在回复里明确标注「未编译验证」。
5. 改数据层遵守 `DB_VERSION + 1` 与 `migrate()`，禁止改建表语句；页面里不出现 SQL。
6. 原型与代码不一致时以 `jianyi-prototype.html` 为准并同步代码（project_rules 6），但**原型只是设计参考，不是运行时**。
7. 完成实质工作后把结论追加到 `.workbuddy/memory/YYYY-MM-DD.md`；用户表达的长期偏好另写 `.workbuddy/memory/MEMORY.md`。**不要删除 `.workbuddy/` 目录**。
8. 提交信息沿用 `feat: / fix: / refactor: / docs:`，一次提交只做一件事。
