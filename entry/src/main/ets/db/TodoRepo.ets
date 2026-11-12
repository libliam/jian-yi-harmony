/**
 * 待办仓库
 *
 * 派生数据（今日数量、已完成、已顺延）一律查询时现算，不落库。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './JianYiDb';
import { TodoRow, TodoBucket, Priority } from './Models';
import { str, strOrNull, num, numOrNull } from './RowUtil';

const TABLE: string = 'todo';

export interface TodoStat {
  total: number;
  done: number;
  overdue: number;
}

export async function addTodo(
  title: string,
  bucket: TodoBucket,
  priority: Priority,
  dueAt: number | null,
  note: string | null
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'title': title,
    'note': note,
    'bucket': bucket,
    'priority': priority,
    'due_at': dueAt,
    'done': 0,
    'sort_order': 0,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(TABLE, row);
  return id;
}

/**
 * 分段列表。
 * ORDER BY 里的 (due_at IS NULL) 是关键：SQLite 的 NULL 在 ASC 时排最前，
 * 若只按 due_at 排，「没有截止时间」的任务反而会顶到最上面，正好和意图相反。
 */
export async function listTodos(bucket: TodoBucket, includeDone: boolean): Promise<TodoRow[]> {
  const doneClause: string = includeDone ? '' : ' AND done = 0';
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT * FROM todo
     WHERE deleted_at IS NULL AND bucket = ?${doneClause}
     ORDER BY done ASC, priority DESC, (due_at IS NULL) ASC, due_at ASC, created_at DESC`,
    [bucket]
  );
  return collect(rs);
}

/** 首页摘要：今天最该让人看到的三条 */
export async function todayBrief(limit: number): Promise<TodoRow[]> {
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT * FROM todo
     WHERE deleted_at IS NULL AND done = 0 AND bucket = 'today'
     ORDER BY priority DESC, (due_at IS NULL) ASC, due_at ASC
     LIMIT ${limit}`
  );
  return collect(rs);
}

export async function setTodoDone(id: string, done: boolean): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = {
    'done': done ? 1 : 0,
    'done_at': done ? now : null,
    'updated_at': now
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function removeTodo(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

/** 统计数字现算，页面顶部的「7 / 3 / 1」就是它 */
export async function countTodos(bucket: TodoBucket): Promise<TodoStat> {
  const now: number = Date.now();
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT
       COUNT(*) AS total,
       SUM(CASE WHEN done = 1 THEN 1 ELSE 0 END) AS done_count,
       SUM(CASE WHEN done = 0 AND due_at IS NOT NULL AND due_at < ${now} THEN 1 ELSE 0 END) AS overdue_count
     FROM todo WHERE deleted_at IS NULL AND bucket = ?`,
    [bucket]
  );
  const stat: TodoStat = { total: 0, done: 0, overdue: 0 };
  if (rs.goToNextRow()) {
    const total: number | null = numOrNull(rs, 'total');
    const doneCount: number | null = numOrNull(rs, 'done_count');
    const overdueCount: number | null = numOrNull(rs, 'overdue_count');
    if (total !== null) {
      stat.total = total;
    }
    if (doneCount !== null) {
      stat.done = doneCount;
    }
    if (overdueCount !== null) {
      stat.overdue = overdueCount;
    }
  }
  rs.close();
  return stat;
}

/** 全局搜索用 */
export async function searchTodos(keyword: string): Promise<TodoRow[]> {
  const like: string = `%${keyword}%`;
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT * FROM todo
     WHERE deleted_at IS NULL AND (title LIKE ? OR note LIKE ?)
     ORDER BY created_at DESC LIMIT 30`,
    [like, like]
  );
  return collect(rs);
}

function collect(rs: relationalStore.ResultSet): TodoRow[] {
  const list: TodoRow[] = [];
  while (rs.goToNextRow()) {
    list.push({
      id: str(rs, 'id'),
      title: str(rs, 'title'),
      note: strOrNull(rs, 'note'),
      bucket: str(rs, 'bucket') as TodoBucket,
      dueAt: numOrNull(rs, 'due_at'),
      priority: num(rs, 'priority') as Priority,
      done: num(rs, 'done'),
      doneAt: numOrNull(rs, 'done_at'),
      sortOrder: num(rs, 'sort_order'),
      createdAt: num(rs, 'created_at'),
      updatedAt: num(rs, 'updated_at'),
      deletedAt: null
    });
  }
  rs.close();
  return list;
}
