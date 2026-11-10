/**
 * 简忆 · 数据模型
 *
 * 设计原则：
 * 1. 所有表都有 id / created_at / updated_at / deleted_at —— 为将来的端云同步留位置
 * 2. id 用 UUID，不用自增。两台设备各自生成不会撞
 * 3. 时间是毫秒时间戳（INTEGER）；只有「按天」语义的字段用 'YYYY-MM-DD' 字符串
 * 4. 删除一律软删除（deleted_at 置位），查询时统一过滤 deleted_at IS NULL
 */

/** 记忆条目类型：语录 / 剪藏 / 手记（共用一张表） */
export enum EntryType {
  Quote = 'quote',
  Snippet = 'snippet',
  Note = 'note'
}

/** 待办所在的分段：今日 / 长期 */
export enum TodoBucket {
  Today = 'today',
  Later = 'later'
}

/** 优先级：0 低 / 1 中 / 2 高 */
export enum Priority {
  Low = 0,
  Mid = 1,
  High = 2
}

/** 习惯周期 */
export enum HabitPeriod {
  Daily = 'daily',
  Weekly = 'weekly'
}

/** 想法状态：待想 / 已归档 */
export enum ThoughtStatus {
  Open = 'open',
  Archived = 'archived'
}

/** 所有表的公共字段 */
export interface BaseRow {
  id: string;
  createdAt: number;
  updatedAt: number;
  /** null 表示未删除；有值表示删除时间 */
  deletedAt: number | null;
}

/** 记忆条目：语录、剪藏、手记 */
export interface EntryRow extends BaseRow {
  type: EntryType;
  /** 正文；剪藏时只存前 2000 字摘要 */
  content: string;
  /** 出处，如「梭罗《瓦尔登湖》」 */
  source: string | null;
  /** 原文链接，仅剪藏有 */
  url: string | null;
  /** 逗号分隔的标签，如「哲思,自然」 */
  tags: string | null;
  favorite: number;
}

/** 待办 */
export interface TodoRow extends BaseRow {
  title: string;
  note: string | null;
  bucket: TodoBucket;
  /** 截止时间戳，长期待办可为 null */
  dueAt: number | null;
  priority: Priority;
  done: number;
  doneAt: number | null;
  /** 长期清单定期上浮时用 */
  sortOrder: number;
}

/** 待思 */
export interface ThoughtRow extends BaseRow {
  content: string;
  status: ThoughtStatus;
  /** 点开想过几次 */
  thinkCount: number;
  lastThoughtAt: number | null;
}

/** 习惯 */
export interface HabitRow extends BaseRow {
  name: string;
  icon: string | null;
  period: HabitPeriod;
  /** 每周目标次数；daily 恒为 7 */
  targetTimes: number;
  /** 'HH:mm'，为空表示不提醒 */
  remindAt: string | null;
  archived: number;
}

/**
 * 打卡记录
 * 注意：这里没有「当前连续天数」。连续天数必须查询时现算，
 * 因为一旦落库，漏打/补打就会让它变成错的。
 */
export interface HabitRecordRow {
  id: string;
  habitId: string;
  /** 'YYYY-MM-DD' */
  date: string;
  done: number;
  note: string | null;
  updatedAt: number;
}

/** 心情 */
export interface MoodRow extends BaseRow {
  /** 'YYYY-MM-DD' */
  date: string;
  /** 1 低落 → 5 明亮 */
  level: number;
  note: string | null;
  tags: string | null;
}

/** 日程时间块（计划页） */
export interface EventRow extends BaseRow {
  title: string;
  /** 'YYYY-MM-DD' */
  date: string;
  startAt: number;
  endAt: number | null;
  /** local 手动加 / calendar 系统日历 / ai 由解读生成 */
  source: string;
}

/** 书籍 + 阅读进度（进度直接存在书上，一本书只有一个位置） */
export interface BookRow extends BaseRow {
  title: string;
  author: string | null;
  /** 沙箱内路径，如 files/books/xxx.epub */
  filePath: string | null;
  format: string | null;
  coverPath: string | null;
  totalPages: number;
  lastChapter: number;
  lastOffset: number;
  percent: number;
  addedAt: number;
}
