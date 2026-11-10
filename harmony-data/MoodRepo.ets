/**
 * 心情仓库
 *
 * 一天允许多条，今日页只显示最新一条，周视图取每天的「最后一条」。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './InkDb';
import { MoodRow } from './Models';
import { str, strOrNull, num } from './RowUtil';

const TABLE: string = 'mood';

export async function addMood(
  date: string,
  level: number,
  note: string | null,
  tags: string | null
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'date': date,
    'level': level,
    'note': note,
    'tags': tags,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(TABLE, row);
  return id;
}

/** 当天最新一条；没有则返回 null */
export async function latestMood(date: string): Promise<MoodRow | null> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at').equalTo('date', date);
  predicates.orderByDesc('created_at').limitAs(1);

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const row: MoodRow | null = rs.goToNextRow() ? mapMood(rs) : null;
  rs.close();
  return row;
}

/** 一段日期内全部记录，给周视图用；同一天多条时由调用方取最后一条 */
export async function listMoods(fromDate: string, toDate: string): Promise<MoodRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates
    .isNull('deleted_at')
    .greaterThanOrEqualTo('date', fromDate)
    .lessThanOrEqualTo('date', toDate);
  predicates.orderByAsc('date').orderByAsc('created_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: MoodRow[] = [];
  while (rs.goToNextRow()) {
    list.push(mapMood(rs));
  }
  rs.close();
  return list;
}

export async function removeMood(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

function mapMood(rs: relationalStore.ResultSet): MoodRow {
  return {
    id: str(rs, 'id'),
    date: str(rs, 'date'),
    level: num(rs, 'level'),
    note: strOrNull(rs, 'note'),
    tags: strOrNull(rs, 'tags'),
    createdAt: num(rs, 'created_at'),
    updatedAt: num(rs, 'updated_at'),
    deletedAt: null
  };
}
