/**
 * 待思仓库
 *
 * 待思和待办最大的区别：它没有「完成」。只有「想清楚了」和「还在想」。
 * 所以状态只有 open / archived，归档动作由用户自己判断。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './InkDb';
import { ThoughtRow, ThoughtStatus } from './Models';
import { str, num, numOrNull } from './RowUtil';

const TABLE: string = 'thought';

export async function addThought(content: string): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'content': content,
    'status': ThoughtStatus.Open,
    'think_count': 0,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(TABLE, row);
  return id;
}

export async function listThoughts(status: ThoughtStatus): Promise<ThoughtRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at').equalTo('status', status);
  predicates.orderByDesc('created_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: ThoughtRow[] = [];

  while (rs.goToNextRow()) {
    list.push({
      id: str(rs, 'id'),
      content: str(rs, 'content'),
      status: str(rs, 'status') as ThoughtStatus,
      thinkCount: num(rs, 'think_count'),
      lastThoughtAt: numOrNull(rs, 'last_thought_at'),
      createdAt: num(rs, 'created_at'),
      updatedAt: num(rs, 'updated_at'),
      deletedAt: null
    });
  }
  rs.close();
  return list;
}

/**
 * 点开想过一次：「已想 5 次」就是这么来的。
 * 这个计数看着没用，其实是在帮你发现哪些念头反复出现、值得认真对待。
 */
export async function bumpThought(id: string): Promise<void> {
  const now: number = Date.now();
  await db().executeSql(
    `UPDATE thought SET think_count = think_count + 1, last_thought_at = ?, updated_at = ?
     WHERE id = ?`,
    [now, now, id]
  );
}

export async function updateThoughtContent(id: string, content: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'content': content, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function archiveThought(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = {
    'status': ThoughtStatus.Archived,
    'updated_at': now
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function removeThought(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}
