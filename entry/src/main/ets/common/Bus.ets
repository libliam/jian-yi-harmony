/**
 * 轻量状态总线
 *
 * 两层用途：
 * 1. dbRevision —— 任一页面写库后 bump，其他页面用 @StorageLink + @Watch 重拉数据
 * 2. ui* —— 跨页面参数与 UI 状态（tab、录入弹层、二级页类型、计划日期）
 *
 * 导航动作走系统页面栈：openSub / openSearch = pushUrl，closeSub / closeSearch = back。
 * 系统返回键与侧滑返回由系统逐层 pop，不再靠单页条件渲染覆盖层（见 AGENTS.md 第 4 节）。
 *
 * 全部走 AppStorage + UIContext，不引入第三方状态框架，页面之间不互相持有引用（项目规则 2）。
 */

import { router, UIContext } from '@kit.ArkUI';

export const REV_KEY: string = 'dbRevision';

export const TAB_KEY: string = 'uiTab';
export const PANE_KEY: string = 'uiTodoPane';
export const SHEET_KEY: string = 'uiSheet';
export const SUB_KEY: string = 'uiSub';
export const QUOTE_KEY: string = 'uiQuoteId';
export const PLAN_DATE_KEY: string = 'uiPlanDate';

/**
 * 页面栈入口。
 * 静态 router.pushUrl 自 API 18 起废弃，本工程 compatibleSdkVersion 是 24，
 * 所以统一走官方推荐的 UIContext.getRouter()；router 在这里只用于 RouterOptions 类型。
 * 主页面在 onPageShow 里挂一次 UIContext，之后所有页面共用同一个上下文。
 */
let uiContext: UIContext | undefined = undefined;

export function attachUiContext(ctx: UIContext): void {
  uiContext = ctx;
}

function pushPage(url: string): void {
  if (uiContext === undefined) {
    return;
  }
  const options: router.RouterOptions = { url: url };
  uiContext.getRouter().pushUrl(options).catch(() => {
    // 跳转失败就留在当前页，不阻断用户操作
  });
}

function popPage(): void {
  if (uiContext === undefined) {
    return;
  }
  uiContext.getRouter().back();
}

/** 在 Index 启动时调用一次，保证所有 @StorageLink 的 key 都已存在 */
export function ensureUiState(): void {
  const rev: number | undefined = AppStorage.get<number>(REV_KEY);
  if (rev === undefined) {
    AppStorage.setOrCreate<number>(REV_KEY, 0);
  }
  AppStorage.setOrCreate<number>(TAB_KEY, 0);
  AppStorage.setOrCreate<string>(PANE_KEY, 'today');
  AppStorage.setOrCreate<string>(SHEET_KEY, '');
  AppStorage.setOrCreate<string>(SUB_KEY, '');
  AppStorage.setOrCreate<string>(QUOTE_KEY, '');
  AppStorage.setOrCreate<string>(PLAN_DATE_KEY, '');
}

export function bumpRevision(): void {
  let cur: number = 0;
  const got: number | undefined = AppStorage.get<number>(REV_KEY);
  if (got !== undefined) {
    cur = got;
  }
  AppStorage.setOrCreate<number>(REV_KEY, cur + 1);
}

export function switchTab(index: number): void {
  AppStorage.setOrCreate<number>(TAB_KEY, index);
}

export function setTodoPane(pane: string): void {
  AppStorage.setOrCreate<string>(PANE_KEY, pane);
}

/** 搜索是独立页面，压入系统页面栈 */
export function openSearch(): void {
  pushPage('pages/SearchPage');
}

export function closeSearch(): void {
  popPage();
}

/** sheet 类型：more / quote / task / think / mood / habit / event；空串表示关闭 */
export function openSheet(type: string): void {
  AppStorage.setOrCreate<string>(SHEET_KEY, type);
}

export function closeSheet(): void {
  AppStorage.setOrCreate<string>(SHEET_KEY, '');
}

/**
 * 二级页：habits / mood / quote / reader。
 * 先把类型写进 AppStorage 当跨页面参数，再压入系统页面栈；
 * 不清空 SUB_KEY，避免返回时二级页在 pop 动画里闪成空白，下次 openSub 会覆盖。
 */
export function openSub(page: string): void {
  AppStorage.setOrCreate<string>(SUB_KEY, page);
  pushPage('pages/SubPage');
}

export function closeSub(): void {
  popPage();
}

export function openQuote(id: string): void {
  AppStorage.setOrCreate<string>(QUOTE_KEY, id);
  openSub('quote');
}

/** 计划页选中的日期；新增日程要落到这一天，而不是永远落到今天 */
export function setPlanDate(date: string): void {
  AppStorage.setOrCreate<string>(PLAN_DATE_KEY, date);
}
