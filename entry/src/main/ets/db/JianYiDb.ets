/**
 * 简忆 · 本地数据库
 *
 * 只负责三件事：单例连接、建表迁移、生成 UUID。
 * 业务读写一律在 XxxRepo.ets 里，页面不碰 SQL（项目规则 4）。
 *
 * 存放位置：应用沙箱 databases/jianyi.db（由 RDB 自动管理）
 */

import { relationalStore, preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const STORE_NAME: string = 'jianyi.db';
/** 加密升级标记：与提醒开关共用 jianyi_meta，卸载即清，不会出现「标记在库不在」 */
const META_PREF: string = 'jianyi_meta';
const ENC_FLAG_KEY: string = 'db_encrypted_v1';

/** 每次改表结构，版本号 +1，并在 migrate() 里追加一段；禁止直接改建表语句 */
const DB_VERSION: number = 2;

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

/**
 * v2：微光（成长点滴）。
 * DDL_V1 保持原样，老用户从 version 1 升上来时只执行这一段，
 * 不重建任何已有表，也不碰已记录的数据。
 */
const DDL_V2: string[] = [
  `CREATE TABLE IF NOT EXISTS growth (
    id          TEXT PRIMARY KEY,
    date        TEXT NOT NULL,
    content     TEXT NOT NULL,
    category    TEXT,
    amount      REAL,
    unit        TEXT,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL,
    deleted_at  INTEGER
  )`,
  `CREATE INDEX IF NOT EXISTS idx_growth_date ON growth(date DESC, created_at DESC)`,
  `CREATE INDEX IF NOT EXISTS idx_growth_alive ON growth(deleted_at)`
];

/** 全局单例：整个应用只开一个 RdbStore，重复打开会锁库 */
let store: relationalStore.RdbStore | null = null;
/**
 * 初始化中的 Promise。EntryAbility 与页面可能同时触发 initDb，
 * 用同一个 Promise 保证建表只跑一次，避免「表还没建完就去查」。
 */
let pending: Promise<relationalStore.RdbStore> | null = null;

/**
 * 数据库是否已升级为加密。标记与库同生命周期（都在应用沙箱，卸载一并清除），
 * 所以不存在「标记说加密、库其实是明文」的错位。
 */
async function isEncrypted(context: common.Context): Promise<boolean> {
  const opts: preferences.Options = { name: META_PREF };
  const p: preferences.Preferences = await preferences.getPreferences(context, opts);
  return p.getSync(ENC_FLAG_KEY, false) === true;
}

async function markEncrypted(context: common.Context): Promise<void> {
  const opts: preferences.Options = { name: META_PREF };
  const p: preferences.Preferences = await preferences.getPreferences(context, opts);
  await p.put(ENC_FLAG_KEY, true);
  await p.flush();
}

/**
 * 打开数据库。安全策略（2026-11-23）：
 * - 新装：直接以 encrypt:true + S4 建库，从第一张表起就是密文；
 * - 老用户：旧库是明文，先以 encrypt:false 打开，用官方 rekeyEx() 原地加密，
 *   数据一行不丢，成功后写标记，后续都用 encrypt:true 打开；
 * - 降级：rekeyEx 万一失败（设备不支持等），保持明文可用，不锁死用户数据，
 *   标记不写，下次启动会再试一次。绝不为了加密把数据库弄成打不开。
 *
 * securityLevel 是敏感度标记（影响备份/同步策略），encrypt 才是文件级 AES 加密，
 * 两者独立：加密库统一设 S4。
 */
export async function initDb(context: common.Context): Promise<relationalStore.RdbStore> {
  if (store) {
    return store;
  }
  if (pending) {
    return pending;
  }

  pending = (async (): Promise<relationalStore.RdbStore> => {
    const encrypted: boolean = await isEncrypted(context);
    const config: relationalStore.StoreConfig = {
      name: STORE_NAME,
      securityLevel: encrypted
        ? relationalStore.SecurityLevel.S4
        : relationalStore.SecurityLevel.S1,
      encrypt: encrypted
    };

    let s: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);

    // 老库升级：明文打开 → rekeyEx 原地加密 → 以加密方式重开 → 写标记
    if (!encrypted) {
      try {
        // 不给自定义 key，让系统生成并托管密钥；空 key 数组即「由 RDB 管理」
        const cryptoParam: relationalStore.CryptoParam = {
          encryptionKey: new Uint8Array()
        };
        await s.rekeyEx(cryptoParam);
        s = await relationalStore.getRdbStore(context, {
          name: STORE_NAME,
          securityLevel: relationalStore.SecurityLevel.S4,
          encrypt: true
        });
        await markEncrypted(context);
      } catch (err) {
        // 降级：保持明文库可用，绝不因加密失败阻断应用
        hilog.error(0x0000, 'JianYiDb', 'rekeyEx failed, keep plaintext: %{public}s', JSON.stringify(err));
      }
    }

    await migrate(s);
    store = s;
    return s;
  })();

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

  if (current < 2) {
    s.beginTransaction();
    try {
      for (const sql of DDL_V2) {
        await s.executeSql(sql);
      }
      s.commit();
    } catch (err) {
      s.rollBack();
      const e = err as BusinessError;
      throw new Error(`数据库迁移到 v2 失败：${e.message}`);
    }
  }

  s.version = DB_VERSION;
}

/** 主键统一 UUID，为跨端同步留路（项目规则 3） */
export function newId(): string {
  return util.generateRandomUUID(true);
}
