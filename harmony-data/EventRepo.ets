/**
 * 日程仓库（计划页的时间块）
 *
 * 只存「某天某个时间段要做什么」。不存重复规则——
 * 重复日程是日历的活，交给系统日历，我们只读不写规则。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './InkDb';
import { EventRow } from './Models';
import { str, num, numOrNull } from './RowUtil';

const TABLE: string = 'event';

export async function addEvent(
  title: string,
  date: string,
  startAt: number,
  endAt: number | null,
  source: string
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'title': title,
    'date': date,
    'start_at': startAt,
    'end_at': endAt,
    'source': source,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(TABLE, row);
  return id;
}

export async function listEventsByDate(date: string): Promise<EventRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at').equalTo('date', date);
  predicates.orderByAsc('start_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: EventRow[] = [];
  while (rs.goToNextRow()) {
    list.push(mapEvent(rs));
  }
  rs.close();
  return list;
}

/** 一周视图：按天分组交给调用方，SQL 只负责把区间捞全 */
export async function listEventsInRange(fromDate: string, toDate: string): Promise<EventRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates
    .isNull('deleted_at')
    .greaterThanOrEqualTo('date', fromDate)
    .lessThanOrEqualTo('date', toDate);
  predicates.orderByAsc('date').orderByAsc('start_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: EventRow[] = [];
  while (rs.goToNextRow()) {
    list.push(mapEvent(rs));
  }
  rs.close();
  return list;
}

export async function removeEvent(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

/**
 * 系统日历同步时用：外部日程要按 source + 外部 id 去重，
 * 否则每次同步都会把同一场会议再插一遍。
 * 这里先用 title + date + start_at 做近似判断，接真实日历时换成 Calendar 的事件 id。
 */
export async function existsEvent(date: string, startAt: number, title: string): Promise<boolean> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates
    .isNull('deleted_at')
    .equalTo('date', date)
    .equalTo('start_at', startAt)
    .equalTo('title', title);

  const rs: relationalStore.ResultSet = await db().query(predicates, ['id']);
  const exists: boolean = rs.goToNextRow();
  rs.close();
  return exists;
}

function mapEvent(rs: relationalStore.ResultSet): EventRow {
  return {
    id: str(rs, 'id'),
    title: str(rs, 'title'),
    date: str(rs, 'date'),
    startAt: num(rs, 'start_at'),
    endAt: numOrNull(rs, 'end_at'),
    source: str(rs, 'source'),
    createdAt: num(rs, 'created_at'),
    updatedAt: num(rs, 'updated_at'),
    deletedAt: null
  };
}
