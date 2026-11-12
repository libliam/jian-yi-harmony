/**
 * 简忆 · 本地数据库
 *
 * 只负责三件事：单例连接、建表迁移、生成 UUID。
 * 业务读写一律在 XxxRepo.ets 里，页面不碰 SQL（项目规则 4）。
 *
 * 存放位置：应用沙箱 databases/jianyi.db（由 RDB 自动管理）
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const STORE_NAME: string = 'jianyi.db';

/** 每次改表结构，版本号 +1，并在 migrate() 里追加一段；禁止直接改建表语句 */
const DB_VERSION: number = 1;

/**
 * 建表语句
 *
 * 几个刻意为之的选择：
 * - CHECK 约束把非法状态挡在数据库层，而不是指望 UI 不犯错
 * - 时间戳统一 INTEGER，做范围查询时不用解析字符串
 * - 查询一律先过滤未删除，索引都围绕这个前提建
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
/**
 * 初始化中的 Promise。EntryAbility 与页面可能同时触发 initDb，
 * 用同一个 Promise 保证建表只跑一次，避免「表还没建完就去查」。
 */
let pending: Promise<relationalStore.RdbStore> | null = null;

export async function initDb(context: common.Context): Promise<relationalStore.RdbStore> {
  if (store) {
    return store;
  }
  if (pending) {
    return pending;
  }

  const config: relationalStore.StoreConfig = {
    name: STORE_NAME,
    securityLevel: relationalStore.SecurityLevel.S1
  };

  pending = relationalStore.getRdbStore(context, config).then(
    async (s: relationalStore.RdbStore): Promise<relationalStore.RdbStore> => {
      await migrate(s);
      store = s;
      pending = null;
      return s;
    }
  );
  // 初始化失败要放行重试，否则这个 rejected Promise 会一直卡着
  pending.catch(() => {
    pending = null;
  });
  return pending;
}

export function db(): relationalStore.RdbStore {
  if (!store) {
    throw new Error('数据库未初始化：页面请先在 aboutToAppear 里 await initDb(context)');
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
      const e = err as BusinessError;
      throw new Error(`数据库迁移失败：${e.message}`);
    }
  }

  // 将来加字段的写法示例（不要改建表语句）：
  // if (current < 2) {
  //   await s.executeSql(`ALTER TABLE todo ADD COLUMN remind_at INTEGER`);
  // }

  s.version = DB_VERSION;
}

/** 主键统一 UUID，为跨端同步留路（项目规则 3） */
export function newId(): string {
  return util.generateRandomUUID(true);
}
