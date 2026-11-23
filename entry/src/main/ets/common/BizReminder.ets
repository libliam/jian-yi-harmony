/**
 * 简忆 · 业务提醒（待办 / 习惯 / 日程）
 *
 * 与「每晚回顾提醒」（Reminder.ets）同一套系统代理能力，三道开关同样缺一不可：
 * module.json5 权限 + 通知授权 + AGC「代理提醒」能力，见 AGENTS.md 3.4。
 *
 * 设计取舍：
 * 1. 待办是「汇总提醒」而不是每条一条——快速录入给今日待办的截止时间默认都是当天 18:00，
 *    按条提醒会在同一时刻弹一串通知。汇总只发一条：最迫近的截止时刻 + 剩余数量，清空即取消。
 * 2. 只在通知「已授权」时静默发布（isNotificationEnabledSync），写库路径绝不弹授权窗；
 *    授权入口是今日页「每晚回顾提醒」开关。用户拒绝过授权，这里就静默跳过，不反复打扰。
 * 3. 习惯是每日 ALARM：打卡后当日不会静音（alarm 型做不到跳过单日）；每周习惯没有「周几」字段，不发。
 * 4. 通知失败绝不阻断写库：异常在本模块内部消化，只记日志；调用方再 .catch() 兜底即可。
 * 5. 删除即取消：removeHabit / removeEvent 后必须调 cancelHabitReminder / cancelEventReminder；
 *    编辑走「先取消再重发」，时间改到过去时旧提醒同样被取消。
 *
 * reminderId 映射落在 Preferences（jianyi_meta），与 DB 行不绑表结构：
 * todo_summary_reminder_id（汇总单条）/ habit_rem_<habitId> / event_rem_<eventId>。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sheetWantAgent } from './NotifyLaunch';
import { listTodos } from '../db/TodoRepo';
import { TodoRow, TodoBucket, HabitPeriod } from '../db/Models';

const DOMAIN: number = 0x0000;
const TAG: string = 'BizReminder';
const PREF_NAME: string = 'jianyi_meta';
const KEY_TODO_SUMMARY: string = 'todo_summary_reminder_id';
const TODO_NOTIFICATION_ID: number = 2001;

function logError(action: string, err: BusinessError): void {
  hilog.error(DOMAIN, TAG, '%{public}s failed: %{public}d %{public}s', action, err.code, err.message);
}

/** 授权入口只在今日页开关那里；这里只查状态，绝不发起授权弹窗 */
function notificationEnabled(): boolean {
  try {
    return notificationManager.isNotificationEnabledSync();
  } catch (err) {
    logError('check notification', err as BusinessError);
    return false;
  }
}

async function pref(context: common.Context): Promise<preferences.Preferences> {
  const opts: preferences.Options = { name: PREF_NAME };
  return preferences.getPreferences(context, opts);
}

async function cancelQuietly(reminderId: number): Promise<void> {
  if (reminderId < 0) {
    return;
  }
  try {
    await reminderAgentManager.cancelReminder(reminderId);
  } catch (err) {
    logError('cancelReminder', err as BusinessError);
  }
}

/** 'HH:mm' → [hour, minute]；解析失败或越界返回 null */
function parseHM(text: string): number[] | null {
  const parts: string[] = text.split(':');
  if (parts.length !== 2) {
    return null;
  }
  const hour: number = Number(parts[0]);
  const minute: number = Number(parts[1]);
  if (Number.isNaN(hour) || Number.isNaN(minute) || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return [hour, minute];
}

/** 用业务 id 派生稳定的 notificationId（2002 起），避免不同提醒在通知面板互相顶掉 */
function notificationIdOf(key: string, salt: number): number {
  let hash: number = salt;
  for (let i = 0; i < key.length; i++) {
    hash = (hash * 31 + key.charCodeAt(i)) % 1000000007;
  }
  return 2002 + hash % 20000;
}

/** 删除习惯 / 日程时按 Preferences key 取消对应提醒。函数永不抛错。 */
async function cancelByKey(context: common.Context, key: string): Promise<void> {
  try {
    const p: preferences.Preferences = await pref(context);
    const stored: preferences.ValueType = p.getSync(key, -1);
    await cancelQuietly(Number(stored));
    await p.delete(key);
    await p.flush();
  } catch (err) {
    logError('cancelReminder by key', err as BusinessError);
  }
}

/** 删除习惯时取消其每日提醒（删除 UI 落地后由视图调用）。函数永不抛错。 */
export async function cancelHabitReminder(context: common.Context, habitId: string): Promise<void> {
  await cancelByKey(context, `habit_rem_${habitId}`);
}

/** 删除日程时取消其一次性提醒。函数永不抛错。 */
export async function cancelEventReminder(context: common.Context, eventId: string): Promise<void> {
  await cancelByKey(context, `event_rem_${eventId}`);
}

/**
 * 待办汇总提醒。新增 / 勾选 / 取消勾选今日待办后都调它：
 * 还有未完成且有未来截止时间的待办 → 在最迫近的截止时刻发一条；清空 → 自动取消。
 * 函数永不抛错。
 */
export async function syncTodoSummaryReminder(context: common.Context): Promise<void> {
  if (!notificationEnabled()) {
    return;
  }
  try {
    const undone: TodoRow[] = await listTodos(TodoBucket.Today, false);
    const now: number = Date.now();
    let earliest: number | null = null;
    for (let i = 0; i < undone.length; i++) {
      const due: number | null = undone[i].dueAt;
      if (due !== null && due > now && (earliest === null || due < earliest)) {
        earliest = due;
      }
    }

    const p: preferences.Preferences = await pref(context);
    const stored: preferences.ValueType = p.getSync(KEY_TODO_SUMMARY, -1);
    const oldId: number = Number(stored);

    if (earliest === null) {
      await cancelQuietly(oldId);
      await p.delete(KEY_TODO_SUMMARY);
      await p.flush();
      return;
    }

    // 先取消旧的再发布，刷新时刻与数量，避免叠多条
    await cancelQuietly(oldId);
    const d: Date = new Date(earliest);
    const dateTime: reminderAgentManager.LocalDateTime = {
      year: d.getFullYear(),
      month: d.getMonth() + 1,
      day: d.getDate(),
      hour: d.getHours(),
      minute: d.getMinutes(),
      second: 0
    };
    const req: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: '今天还有事没做完',
      content: `还有 ${undone.length} 件今天的事，回头看看吧。`,
      expiredContent: '今天的待办还没清完',
      notificationId: TODO_NOTIFICATION_ID,
      // 点通知直达待办录入（task）
      wantAgent: sheetWantAgent('task')
    };
    const id: number = await reminderAgentManager.publishReminder(req);
    await p.put(KEY_TODO_SUMMARY, id);
    await p.flush();
  } catch (err) {
    logError('syncTodoSummaryReminder', err as BusinessError);
  }
}

/**
 * 习惯每日提醒。remindAt 为空、period 非每天（每周没有「周几」字段）、通知未授权 → 不发，
 * 并顺手清掉可能存在的旧提醒。重复调用会先取消旧的。函数永不抛错。
 */
export async function syncHabitReminder(
  context: common.Context,
  habitId: string,
  name: string,
  period: HabitPeriod,
  remindAt: string
): Promise<void> {
  const key: string = `habit_rem_${habitId}`;
  const hm: number[] | null = remindAt.length > 0 ? parseHM(remindAt) : null;
  const enabled: boolean = hm !== null && period === HabitPeriod.Daily && notificationEnabled();

  try {
    const p: preferences.Preferences = await pref(context);
    const stored: preferences.ValueType = p.getSync(key, -1);
    await cancelQuietly(Number(stored));

    if (!enabled || hm === null) {
      await p.delete(key);
      await p.flush();
      return;
    }

    const req: reminderAgentManager.ReminderRequestAlarm = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM,
      hour: hm[0],
      minute: hm[1],
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: name,
      content: '到打卡时间了，点开记一下。',
      expiredContent: '还没打卡',
      notificationId: notificationIdOf(habitId, 11),
      // 点通知直达习惯录入（habit）
      wantAgent: sheetWantAgent('habit')
    };
    const id: number = await reminderAgentManager.publishReminder(req);
    await p.put(key, id);
    await p.flush();
  } catch (err) {
    logError('syncHabitReminder', err as BusinessError);
  }
}

/**
 * 日程开始提醒（一次性 CALENDAR）。startAt 已过或通知未授权 → 不发。
 * 同一日程重复调用会先取消旧的。函数永不抛错。
 */
export async function publishEventReminder(
  context: common.Context,
  eventId: string,
  title: string,
  startAt: number
): Promise<void> {
  const key: string = `event_rem_${eventId}`;
  try {
    // 先取消旧的再决定是否重发：编辑把时间改到过去 / 通知被关时，旧提醒也必须取消
    const p: preferences.Preferences = await pref(context);
    const stored: preferences.ValueType = p.getSync(key, -1);
    await cancelQuietly(Number(stored));
    await p.delete(key);
    await p.flush();

    if (startAt <= Date.now() || !notificationEnabled()) {
      return;
    }

    const d: Date = new Date(startAt);
    const dateTime: reminderAgentManager.LocalDateTime = {
      year: d.getFullYear(),
      month: d.getMonth() + 1,
      day: d.getDate(),
      hour: d.getHours(),
      minute: d.getMinutes(),
      second: 0
    };
    const req: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: dateTime,
      title: title,
      content: '安排的时间到了。',
      expiredContent: '这段安排开始了',
      notificationId: notificationIdOf(eventId, 23),
      // 点通知直达日程录入（event）
      wantAgent: sheetWantAgent('event')
    };
    const id: number = await reminderAgentManager.publishReminder(req);
    await p.put(key, id);
    await p.flush();
  } catch (err) {
    logError('publishEventReminder', err as BusinessError);
  }
}
