/**
 * 习惯仓库
 *
 * 两件事在这里做：
 * 1. 打卡用 UPSERT，靠数据库的唯一索引防重，不靠代码先查后写
 * 2. 连续天数查询时现算，绝不落库
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './JianYiDb';
import { HabitRow, HabitPeriod } from './Models';
import { str, strOrNull, num } from './RowUtil';

const HABIT: string = 'habit';
const RECORD: string = 'habit_record';

export async function addHabit(
  name: string,
  period: HabitPeriod,
  targetTimes: number,
  remindAt: string | null
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'name': name,
    'icon': null,
    'period': period,
    'target_times': targetTimes,
    'remind_at': remindAt,
    'archived': 0,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(HABIT, row);
  return id;
}

export async function listHabits(includeArchived: boolean): Promise<HabitRow[]> {
  const predicates = new relationalStore.RdbPredicates(HABIT);
  predicates.isNull('deleted_at');
  if (!includeArchived) {
    predicates.equalTo('archived', 0);
  }
  predicates.orderByAsc('created_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: HabitRow[] = [];

  while (rs.goToNextRow()) {
    list.push({
      id: str(rs, 'id'),
      name: str(rs, 'name'),
      icon: strOrNull(rs, 'icon'),
      period: str(rs, 'period') as HabitPeriod,
      targetTimes: num(rs, 'target_times'),
      remindAt: strOrNull(rs, 'remind_at'),
      archived: num(rs, 'archived'),
      createdAt: num(rs, 'created_at'),
      updatedAt: num(rs, 'updated_at'),
      deletedAt: null
    });
  }
  rs.close();
  return list;
}

/**
 * 打卡。同一天重复点不会产生两条记录。
 *
 * ON CONFLICT 依赖 idx_hr_unique(habit_id, date)。
 * 如果用「先查再插」，两个快速点击并发时仍可能插重——数据库约束才是唯一可靠的防线。
 */
export async function checkIn(habitId: string, date: string, done: boolean): Promise<void> {
  const now: number = Date.now();
  await db().executeSql(
    `INSERT INTO habit_record (id, habit_id, date, done, note, updated_at)
     VALUES (?, ?, ?, ?, NULL, ?)
     ON CONFLICT(habit_id, date) DO UPDATE SET done = excluded.done, updated_at = excluded.updated_at`,
    [newId(), habitId, date, done ? 1 : 0, now]
  );
}

/** 某段时间内已打卡的日期，热力图和 7 天点阵都用它 */
export async function listDoneDates(habitId: string, fromDate: string, toDate: string): Promise<string[]> {
  const predicates = new relationalStore.RdbPredicates(RECORD);
  predicates
    .equalTo('habit_id', habitId)
    .equalTo('done', 1)
    .greaterThanOrEqualTo('date', fromDate)
    .lessThanOrEqualTo('date', toDate);
  predicates.orderByDesc('date');

  const rs: relationalStore.ResultSet = await db().query(predicates, ['date']);
  const dates: string[] = [];
  while (rs.goToNextRow()) {
    dates.push(str(rs, 'date'));
  }
  rs.close();
  return dates;
}

/**
 * 连续天数：现算。
 *
 * 今天还没打卡不算断——从昨天往前数。
 * 这是习惯类应用的通行规则，写错会让人一大早打开就发现「连续 0 天」，非常挫败。
 */
export async function habitStreak(habitId: string, today: string): Promise<number> {
  const predicates = new relationalStore.RdbPredicates(RECORD);
  predicates.equalTo('habit_id', habitId).equalTo('done', 1).lessThanOrEqualTo('date', today);
  predicates.orderByDesc('date').limitAs(90);

  const rs: relationalStore.ResultSet = await db().query(predicates, ['date']);
  const dates: string[] = [];
  while (rs.goToNextRow()) {
    dates.push(str(rs, 'date'));
  }
  rs.close();

  if (dates.length === 0) {
    return 0;
  }

  let cursor: Date = parseDay(today);
  let i: number = 0;

  // 今天没打，就从昨天开始比
  if (dates[0] !== today) {
    cursor = addDays(cursor, -1);
  }

  let streak: number = 0;
  while (i < dates.length && dates[i] === formatDay(cursor)) {
    streak++;
    cursor = addDays(cursor, -1);
    i++;
  }
  return streak;
}

export async function archiveHabit(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'archived': 1, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(HABIT);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function removeHabit(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(HABIT);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

function parseDay(day: string): Date {
  const parts: string[] = day.split('-');
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
}

function formatDay(d: Date): string {
  const m: string = String(d.getMonth() + 1).padStart(2, '0');
  const day: string = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

function addDays(d: Date, n: number): Date {
  const next: Date = new Date(d.getTime());
  next.setDate(next.getDate() + n);
  return next;
}
