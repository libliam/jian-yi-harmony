/**
 * 轻量状态总线
 *
 * 两层用途：
 * 1. dbRevision —— 任一页面写库后 bump，其他页面用 @StorageLink + @Watch 重拉数据
 * 2. ui* —— 页面间的导航状态（切 tab、开搜索、开弹层、开二级页）
 *
 * 全部走 AppStorage，不引入第三方状态框架，也不让页面互相持有引用（项目规则 2）。
 */

export const REV_KEY: string = 'dbRevision';

export const TAB_KEY: string = 'uiTab';
export const PANE_KEY: string = 'uiTodoPane';
export const SEARCH_KEY: string = 'uiSearch';
export const SHEET_KEY: string = 'uiSheet';
export const SUB_KEY: string = 'uiSub';
export const QUOTE_KEY: string = 'uiQuoteId';
export const PLAN_DATE_KEY: string = 'uiPlanDate';

/** 在 Index 启动时调用一次，保证所有 @StorageLink 的 key 都已存在 */
export function ensureUiState(): void {
  const rev: number | undefined = AppStorage.get<number>(REV_KEY);
  if (rev === undefined) {
    AppStorage.setOrCreate<number>(REV_KEY, 0);
  }
  AppStorage.setOrCreate<number>(TAB_KEY, 0);
  AppStorage.setOrCreate<string>(PANE_KEY, 'today');
  AppStorage.setOrCreate<boolean>(SEARCH_KEY, false);
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

export function openSearch(): void {
  AppStorage.setOrCreate<boolean>(SEARCH_KEY, true);
}

export function closeSearch(): void {
  AppStorage.setOrCreate<boolean>(SEARCH_KEY, false);
}

/** sheet 类型：more / quote / task / think / mood / habit / event；空串表示关闭 */
export function openSheet(type: string): void {
  AppStorage.setOrCreate<string>(SHEET_KEY, type);
}

export function closeSheet(): void {
  AppStorage.setOrCreate<string>(SHEET_KEY, '');
}

/** 二级页：habits / mood / quote / reader；空串表示关闭 */
export function openSub(page: string): void {
  AppStorage.setOrCreate<string>(SUB_KEY, page);
}

export function closeSub(): void {
  AppStorage.setOrCreate<string>(SUB_KEY, '');
}

export function openQuote(id: string): void {
  AppStorage.setOrCreate<string>(QUOTE_KEY, id);
  openSub('quote');
}

/** 计划页选中的日期；新增日程要落到这一天，而不是永远落到今天 */
export function setPlanDate(date: string): void {
  AppStorage.setOrCreate<string>(PLAN_DATE_KEY, date);
}
