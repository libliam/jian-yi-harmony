/**
 * 记忆条目仓库：语录 / 剪藏 / 手记共用一张表
 *
 * tags 落库统一存成 ",哲思,自然," —— 两端补逗号，
 * 这样按标签过滤用 LIKE '%,哲思,%' 时不会把开头/结尾的标签漏掉，
 * 也不会让「自然」误命中「自然科学」。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './JianYiDb';
import { EntryRow, EntryType } from './Models';
import { str, strOrNull, num } from './RowUtil';

const TABLE: string = 'entry';

/** 页面上的分类标签，与原型 .chips 一一对应 */
export const ENTRY_CHIPS: string[] = ['全部', '哲思', '写作', '剪藏', '生活', '未分类'];

export function formatTags(input: string): string {
  const cleaned: string[] = input.split(/[,，]/)
    .map((s: string): string => s.trim())
    .filter((s: string): boolean => s.length > 0);
  return cleaned.length === 0 ? '' : `,${cleaned.join(',')},`;
}

/** 把 ",哲思,自然," 还原成可展示的「哲思 · 自然」 */
export function displayTags(raw: string | null): string {
  if (!raw) {
    return '';
  }
  return raw.split(',').filter((s: string): boolean => s.length > 0).join(' · ');
}

export async function addEntry(
  type: EntryType,
  content: string,
  source: string | null,
  url: string | null,
  tags: string
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'type': type,
    'content': content,
    'source': source,
    'url': url,
    'tags': formatTags(tags),
    'favorite': 0,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(TABLE, row);
  return id;
}

/** 按分类取列表；chip 传 '全部' 表示不过滤 */
export async function listEntriesByChip(chip: string): Promise<EntryRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at');

  if (chip === '剪藏') {
    predicates.equalTo('type', EntryType.Snippet);
  } else if (chip === '未分类') {
    // RdbPredicates 表达不了 IS NULL OR = ''，这一支直接走 SQL
    const rs: relationalStore.ResultSet = await db().querySql(
      `SELECT * FROM entry WHERE deleted_at IS NULL AND (tags IS NULL OR tags = '')
       ORDER BY created_at DESC`
    );
    return collect(rs);
  } else if (chip !== '全部') {
    predicates.like('tags', `%,${chip},%`);
  }

  predicates.orderByDesc('created_at');
  const rs: relationalStore.ResultSet = await db().query(predicates);
  return collect(rs);
}

/** 全局搜索用：正文 / 出处 / 标签三处都可以命中 */
export async function searchEntries(keyword: string): Promise<EntryRow[]> {
  const like: string = `%${keyword}%`;
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT * FROM entry
     WHERE deleted_at IS NULL
       AND (content LIKE ? OR source LIKE ? OR tags LIKE ?)
     ORDER BY created_at DESC LIMIT 30`,
    [like, like, like]
  );
  return collect(rs);
}

/** 语录详情页按 id 取一条 */
export async function getEntry(id: string): Promise<EntryRow | null> {
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT * FROM entry WHERE id = ? AND deleted_at IS NULL`,
    [id]
  );
  const row: EntryRow | null = rs.goToNextRow() ? mapEntry(rs) : null;
  rs.close();
  return row;
}

export async function toggleFavorite(id: string, favorite: boolean): Promise<void> {
  const row: relationalStore.ValuesBucket = {
    'favorite': favorite ? 1 : 0,
    'updated_at': Date.now()
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function updateEntry(id: string, content: string, source: string | null, tags: string): Promise<void> {
  const row: relationalStore.ValuesBucket = {
    'content': content,
    'source': source,
    'tags': formatTags(tags),
    'updated_at': Date.now()
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

/** 软删除：留痕，方便将来同步时把「删除」这个动作也同步出去 */
export async function removeEntry(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function countEntries(): Promise<number> {
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT COUNT(*) AS c FROM entry WHERE deleted_at IS NULL`
  );
  const value: number = rs.goToNextRow() ? num(rs, 'c') : 0;
  rs.close();
  return value;
}

function collect(rs: relationalStore.ResultSet): EntryRow[] {
  const list: EntryRow[] = [];
  while (rs.goToNextRow()) {
    list.push(mapEntry(rs));
  }
  rs.close();
  return list;
}

function mapEntry(rs: relationalStore.ResultSet): EntryRow {
  return {
    id: str(rs, 'id'),
    type: str(rs, 'type') as EntryType,
    content: str(rs, 'content'),
    source: strOrNull(rs, 'source'),
    url: strOrNull(rs, 'url'),
    tags: strOrNull(rs, 'tags'),
    favorite: num(rs, 'favorite'),
    createdAt: num(rs, 'created_at'),
    updatedAt: num(rs, 'updated_at'),
    deletedAt: null
  };
}
