/**
 * 简忆 · 本地数据库
 *
 * 存放位置：应用沙箱 databases/jianyi.db（由 RDB 自动管理）
 * 注意：这份代码是「照抄能懂」的参考实现，接口名以你所用 SDK 版本的 d.ts 为准。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { EntryRow, EntryType, TodoRow, TodoBucket, Priority } from './Models';

const STORE_NAME: string = 'jianyi.db';

/** 每次改表结构，版本号 +1，并在 migrate() 里加一段 */
const DB_VERSION: number = 1;

/**
 * 建表语句
 *
 * 几个刻意为之的选择：
 * - CHECK 约束把非法状态挡在数据库层，而不是指望 UI 不犯错
 * - 时间戳统一 INTEGER，做范围查询时不用解析字符串
 * - 所有索引都带 deleted_at 的隐含前提：查询一律先过滤未删除
 */
const DDL_V1: string[] = [
  `CREATE TABLE IF NOT EXISTS entry (
    id          TEXT PRIMARY KEY,
    type        TEXT NOT NULL CHECK (type IN ('quote','snippet','note')),
    content     TEXT NOT NULL,
    source      TEXT,
    url         TEXT,
    tags        TEXT,
    favorite    INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_entry_type ON entry(type, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_entry_alive ON entry(deleted_at)`,

  `CREATE TABLE IF NOT EXISTS todo (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    note        TEXT,
    bucket      TEXT NOT NULL DEFAULT 'today' CHECK (bucket IN ('today','later')),
    due_at      INTEGER,
    priority    INTEGER NOT NULL DEFAULT 1 CHECK (priority BETWEEN 0 AND 2),
    done        INTEGER NOT NULL DEFAULT 0,
    done_at     INTEGER,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_todo_bucket ON todo(bucket, done, priority DESC)`,

  `CREATE TABLE IF NOT EXISTS thought (
    id              TEXT PRIMARY KEY,
    content         TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','archived')),
    think_count     INTEGER NOT NULL DEFAULT 0,
    last_thought_at INTEGER,
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    deleted_at      INTEGER
  )`,

  `CREATE TABLE IF NOT EXISTS habit (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    icon         TEXT,
    period       TEXT NOT NULL DEFAULT 'daily' CHECK (period IN ('daily','weekly')),
    target_times INTEGER NOT NULL DEFAULT 7,
    remind_at    TEXT,
    archived     INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL,
    deleted_at   INTEGER
  )`,

  `CREATE TABLE IF NOT EXISTS habit_record (
    id          TEXT PRIMARY KEY,
    habit_id    TEXT NOT NULL REFERENCES habit(id) ON DELETE CASCADE,
    date        TEXT NOT NULL,
    done        INTEGER NOT NULL DEFAULT 1,
    note        TEXT,
    updated_at  INTEGER NOT NULL
  )`,
  /* 同一习惯同一天只能有一条记录，靠唯一索引兜住，不靠代码自觉 */
  `CREATE UNIQUE INDEX IF NOT EXISTS idx_hr_unique ON habit_record(habit_id, date)`,

  `CREATE TABLE IF NOT EXISTS mood (
    id          TEXT PRIMARY KEY,
    date        TEXT NOT NULL,
    level       INTEGER NOT NULL CHECK (level BETWEEN 1 AND 5),
    note        TEXT,
    tags        TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_mood_date ON mood(date)`,

  `CREATE TABLE IF NOT EXISTS event (
    id          TEXT PRIMARY KEY,
    title       TEXT NOT NULL,
    date        TEXT NOT NULL,
    start_at    INTEGER NOT NULL,
    end_at      INTEGER,
    source      TEXT NOT NULL DEFAULT 'local',
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )`,

  `CREATE TABLE IF NOT EXISTS book (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    author       TEXT,
    file_path    TEXT,
    format       TEXT,
    cover_path   TEXT,
    total_pages  INTEGER NOT NULL DEFAULT 0,
    last_chapter INTEGER NOT NULL DEFAULT 0,
    last_offset  INTEGER NOT NULL DEFAULT 0,
    percent      REAL NOT NULL DEFAULT 0,
    added_at     INTEGER NOT NULL,
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL,
    deleted_at   INTEGER
  )`
];

/** 全局单例：整个应用只开一个 RdbStore，重复打开会锁库 */
let store: relationalStore.RdbStore | null = null;

export async function initDb(context: common.Context): Promise<relationalStore.RdbStore> {
  if (store) {
    return store;
  }

  const config: relationalStore.StoreConfig = {
    name: STORE_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };

  store = await relationalStore.getRdbStore(context, config);
  await migrate(store);
  return store;
}

export function db(): relationalStore.RdbStore {
  if (!store) {
    throw new Error('数据库未初始化，请先在 EntryAbility.onCreate 里 await initDb(this.context)');
  }
  return store;
}

async function migrate(s: relationalStore.RdbStore): Promise<void> {
  const current: number = s.version;

  if (current < 1) {
    s.beginTransaction();
    try {
      for (const sql of DDL_V1) {
        await s.executeSql(sql);
      }
      s.commit();
    } catch (err) {
      s.rollBack();
      throw err;
    }
  }

  // 将来加字段的写法示例：
  // if (current < 2) {
  //   await s.executeSql(`ALTER TABLE todo ADD COLUMN remind_at INTEGER`);
  // }

  s.version = DB_VERSION;
}

/* ============================ 记忆条目 ============================ */

export function newId(): string {
  return util.generateRandomUUID(true);
}

export async function addEntry(
  type: EntryType,
  content: string,
  source: string | null,
  url: string | null,
  tags: string | null
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'type': type,
    'content': content,
    'source': source,
    'url': url,
    'tags': tags,
    'favorite': 0,
    'created_at': now,
    'updated_at': now
  };

  await db().insert('entry', row);
  return id;
}

/** 按类型 + 标签取列表；tag 传 null 表示不过滤 */
export async function listEntries(type: EntryType | null, tag: string | null): Promise<EntryRow[]> {
  const predicates = new relationalStore.RdbPredicates('entry');
  predicates.isNull('deleted_at');

  if (type) {
    predicates.equalTo('type', type);
  }
  if (tag) {
    // tags 是逗号分隔字符串，用 LIKE 近似匹配，两端补逗号避免子串误命中
    predicates.like('tags', `%,${tag},%`);
  }
  predicates.orderByDesc('created_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: EntryRow[] = [];

  while (rs.goToNextRow()) {
    list.push({
      id: rs.getString(rs.getColumnIndex('id')),
      type: rs.getString(rs.getColumnIndex('type')) as EntryType,
      content: rs.getString(rs.getColumnIndex('content')),
      source: rs.isColumnNull(rs.getColumnIndex('source')) ? null : rs.getString(rs.getColumnIndex('source')),
      url: rs.isColumnNull(rs.getColumnIndex('url')) ? null : rs.getString(rs.getColumnIndex('url')),
      tags: rs.isColumnNull(rs.getColumnIndex('tags')) ? null : rs.getString(rs.getColumnIndex('tags')),
      favorite: rs.getLong(rs.getColumnIndex('favorite')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at')),
      deletedAt: null
    });
  }
  rs.close();
  return list;
}

/** 软删除：留痕，方便将来同步时把「删除」这个动作也同步出去 */
export async function removeEntry(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates('entry');
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

/* ============================== 待办 ============================== */

export async function addTodo(
  title: string,
  bucket: TodoBucket,
  priority: Priority,
  dueAt: number | null
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'title': title,
    'bucket': bucket,
    'priority': priority,
    'due_at': dueAt,
    'done': 0,
    'sort_order': 0,
    'created_at': now,
    'updated_at': now
  };

  await db().insert('todo', row);
  return id;
}

export async function setTodoDone(id: string, done: boolean): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = {
    'done': done ? 1 : 0,
    'done_at': done ? now : null,
    'updated_at': now
  };
  const predicates = new relationalStore.RdbPredicates('todo');
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

/**
 * 首页摘要：今天必须让人看到的三条
 *
 * 排序刻意先按优先级、再按截止时间。
 * 因为 SQLite 里 NULL 在 ASC 时排最前，若只按 due_at 排，
 * 那些「没有截止时间」的反而会顶到最上面，正好和意图相反。
 */
export async function todayBrief(limit: number): Promise<TodoRow[]> {
  const predicates = new relationalStore.RdbPredicates('todo');
  predicates.isNull('deleted_at').equalTo('done', 0).equalTo('bucket', TodoBucket.Today);
  predicates.orderByDesc('priority').orderByAsc('due_at').limitAs(limit);

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: TodoRow[] = [];

  while (rs.goToNextRow()) {
    list.push({
      id: rs.getString(rs.getColumnIndex('id')),
      title: rs.getString(rs.getColumnIndex('title')),
      note: null,
      bucket: rs.getString(rs.getColumnIndex('bucket')) as TodoBucket,
      dueAt: rs.isColumnNull(rs.getColumnIndex('due_at')) ? null : rs.getLong(rs.getColumnIndex('due_at')),
      priority: rs.getLong(rs.getColumnIndex('priority')) as Priority,
      done: rs.getLong(rs.getColumnIndex('done')),
      doneAt: null,
      sortOrder: rs.getLong(rs.getColumnIndex('sort_order')),
      createdAt: rs.getLong(rs.getColumnIndex('created_at')),
      updatedAt: rs.getLong(rs.getColumnIndex('updated_at')),
      deletedAt: null
    });
  }
  rs.close();
  return list;
}
