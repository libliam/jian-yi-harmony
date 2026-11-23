/**
 * 简忆 · 通知点击直达录入
 *
 * 代理提醒的 wantAgent 是纯数据对象（pkgName / abilityName / parameters），
 * 点通知时系统拉起 EntryAbility 并把 parameters 带进 onCreate / onNewWant。
 * 这里统一负责：构造 wantAgent、解析 Want、暂存与消费点击意图。
 *
 * 时序：
 * - 冷启动：onCreate 写 uiNotifySheet → Index.aboutToAppear 就绪后消费
 * - 热启动：onNewWant 写 uiNotifySheet → Index 的 @StorageLink @Watch 或 onPageShow 消费
 *
 * 注意：uiNotifySheet 用 @StorageLink 绑定，装饰器参数只能写字符串字面量，
 * 不要直接引用 NOTIFY_KEY（见 AGENTS.md 3.1）。
 */

import { Want } from '@kit.AbilityKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';

export const NOTIFY_KEY: string = 'uiNotifySheet';

const BUNDLE_NAME: string = 'com.example.harmonyjianyi';
const ABILITY_NAME: string = 'EntryAbility';

/** 白名单：只认本应用四类提醒，防止 Want 参数被伪造出未知 sheet */
const SHEETS: string[] = ['task', 'habit', 'event', 'growth'];

/** 提醒请求里带上的点击跳转参数。sheet 为录入弹层类型，见 Bus.openSheet */
export function sheetWantAgent(sheet: string): reminderAgentManager.WantAgent {
  const params: Record<string, Object> = { 'sheet': sheet };
  const agent: reminderAgentManager.WantAgent = {
    pkgName: BUNDLE_NAME,
    abilityName: ABILITY_NAME,
    parameters: params
  };
  return agent;
}

/** 从 Want 里解析通知附带的 sheet；非白名单或缺失返回空串 */
export function sheetFromWant(want: Want): string {
  const params: Record<string, Object> | undefined = want.parameters;
  if (params === undefined) {
    return '';
  }
  const raw: Object | undefined = params['sheet'];
  if (raw === undefined) {
    return '';
  }
  const sheet: string = String(raw);
  return SHEETS.indexOf(sheet) >= 0 ? sheet : '';
}

/** 暂存点击意图，等 Index 数据就绪后再打开弹层 */
export function stashNotifySheet(sheet: string): void {
  if (sheet.length === 0) {
    return;
  }
  AppStorage.setOrCreate<string>(NOTIFY_KEY, sheet);
}

/** 取走并清空点击意图，避免重复消费同一条通知 */
export function takeNotifySheet(): string {
  const got: string | undefined = AppStorage.get<string>(NOTIFY_KEY);
  AppStorage.setOrCreate<string>(NOTIFY_KEY, '');
  return got === undefined ? '' : got;
}

/** sheet → 主页 tab：待办 2、计划 4、习惯 / 微光 0（今日） */
export function tabForNotifySheet(sheet: string): number {
  if (sheet === 'task') {
    return 2;
  }
  if (sheet === 'event') {
    return 4;
  }
  return 0;
}
