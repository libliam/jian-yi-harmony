/**
 * 简忆 · 通知与后台代理提醒
 *
 * 「每晚回顾提醒」是系统级定时通知：即使应用被清后台，到点仍由系统代理发出。
 * 三道开关缺一不可：
 * 1. module.json5 声明 ohos.permission.PUBLISH_AGENT_REMINDER
 * 2. 用户在系统弹窗里允许通知（isNotificationEnabledSync / requestEnableNotification）
 * 3. AGC 项目里开通「代理提醒」能力 + 手动签名重签 Profile（否则 publishReminder 报 1700002）
 *
 * 提醒开关与 reminderId 落在 Preferences（jianyi_meta），卸载重装后不会残留。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'Reminder';
const PREF_NAME: string = 'jianyi_meta';
const KEY_REMINDER_ID: string = 'review_reminder_id';
const KEY_REVIEW_ENABLED: string = 'review_enabled';
const REVIEW_NOTIFICATION_ID: number = 1001;

export const REVIEW_HOUR: number = 20;
export const REVIEW_MINUTE: number = 30;

async function pref(context: common.Context): Promise<preferences.Preferences> {
  const opts: preferences.Options = { name: PREF_NAME };
  return preferences.getPreferences(context, opts);
}

/**
 * 通知授权。用户明确拒绝后系统不会再弹窗，只能由用户去系统设置里打开，
 * 所以这里返回 false，由 UI 给出文字引导，不反复打扰。
 */
export async function ensureNotificationEnabled(context: common.UIAbilityContext): Promise<boolean> {
  try {
    if (notificationManager.isNotificationEnabledSync()) {
      return true;
    }
    await notificationManager.requestEnableNotification(context);
    return notificationManager.isNotificationEnabledSync();
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'request notification failed: %{public}d %{public}s', e.code, e.message);
    return false;
  }
}

export async function isReviewEnabled(context: common.Context): Promise<boolean> {
  const p: preferences.Preferences = await pref(context);
  return p.getSync(KEY_REVIEW_ENABLED, false) === true;
}

/** 开一个每天固定时刻重复的系统代理提醒；重复开启会先取消旧的，避免叠多条 */
export async function enableReview(context: common.UIAbilityContext): Promise<boolean> {
  const allowed: boolean = await ensureNotificationEnabled(context);
  if (!allowed) {
    return false;
  }
  await disableReview(context);

  const req: reminderAgentManager.ReminderRequestAlarm = {
    reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
    hour: REVIEW_HOUR,
    minute: REVIEW_MINUTE,
    daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
    title: '该回头看看今天了',
    content: '记一句今天的话，顺手看看还没做完的事。',
    expiredContent: '今天的回顾还没写',
    notificationId: REVIEW_NOTIFICATION_ID
  };

  try {
    const id: number = await reminderAgentManager.publishReminder(req);
    const p: preferences.Preferences = await pref(context);
    await p.put(KEY_REMINDER_ID, id);
    await p.put(KEY_REVIEW_ENABLED, true);
    await p.flush();
    return true;
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    hilog.error(DOMAIN, TAG, 'publish reminder failed: %{public}d %{public}s', e.code, e.message);
    return false;
  }
}

export async function disableReview(context: common.Context): Promise<void> {
  const p: preferences.Preferences = await pref(context);
  const stored: preferences.ValueType = p.getSync(KEY_REMINDER_ID, -1);
  const id: number = Number(stored);
  if (id >= 0) {
    try {
      await reminderAgentManager.cancelReminder(id);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'cancel reminder failed: %{public}d %{public}s', e.code, e.message);
    }
  }
  await p.put(KEY_REMINDER_ID, -1);
  await p.put(KEY_REVIEW_ENABLED, false);
  await p.flush();
}
