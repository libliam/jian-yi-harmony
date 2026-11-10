/**
 * 书籍仓库
 *
 * 阅读进度直接存在 book 表上，不单开一张进度表。
 * 理由：一个人同一本书只有一个阅读位置，开表反而多一次 join。
 * 如果将来要做「多端各自位置」，再拆不迟。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './JianYiDb';
import { BookRow } from './Models';
import { str, strOrNull, num } from './RowUtil';

const TABLE: string = 'book';

export async function addBook(
  title: string,
  author: string | null,
  filePath: string | null,
  format: string | null,
  coverPath: string | null,
  totalPages: number
): Promise<string> {
  const now: number = Date.now();
  const id: string = newId();

  const row: relationalStore.ValuesBucket = {
    'id': id,
    'title': title,
    'author': author,
    'file_path': filePath,
    'format': format,
    'cover_path': coverPath,
    'total_pages': totalPages,
    'last_chapter': 0,
    'last_offset': 0,
    'percent': 0,
    'added_at': now,
    'created_at': now,
    'updated_at': now
  };

  await db().insert(TABLE, row);
  return id;
}

export async function listBooks(): Promise<BookRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at').orderByDesc('updated_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: BookRow[] = [];
  while (rs.goToNextRow()) {
    list.push(mapBook(rs));
  }
  rs.close();
  return list;
}

/**
 * 「继续阅读」那张卡用哪个？
 * 取最近读过、但没读完的一本。读完了就不该再占首页。
 */
export async function currentReading(): Promise<BookRow | null> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at').greaterThan('percent', 0).lessThan('percent', 1);
  predicates.orderByDesc('updated_at').limitAs(1);

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const row: BookRow | null = rs.goToNextRow() ? mapBook(rs) : null;
  rs.close();
  return row;
}

/** 每次翻页后调用。注意不要每滑一屏就写库，节流到 1–2 秒一次 */
export async function updateProgress(
  bookId: string,
  chapter: number,
  offset: number,
  percent: number
): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = {
    'last_chapter': chapter,
    'last_offset': offset,
    'percent': percent,
    'updated_at': now
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', bookId);
  await db().update(row, predicates);
}

/**
 * 删书要同时删文件，但文件删除是文件系统的事，不归仓库管。
 * 这里只负责把数据库记录标掉，返回 filePath 让调用方去删文件。
 */
export async function removeBook(bookId: string): Promise<string | null> {
  const now: number = Date.now();
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', bookId);

  let filePath: string | null = null;
  const rs: relationalStore.ResultSet = await db().query(predicates, ['file_path']);
  if (rs.goToNextRow()) {
    filePath = strOrNull(rs, 'file_path');
  }
  rs.close();

  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const updatePredicates = new relationalStore.RdbPredicates(TABLE);
  updatePredicates.equalTo('id', bookId);
  await db().update(row, updatePredicates);

  return filePath;
}

function mapBook(rs: relationalStore.ResultSet): BookRow {
  return {
    id: str(rs, 'id'),
    title: str(rs, 'title'),
    author: strOrNull(rs, 'author'),
    filePath: strOrNull(rs, 'file_path'),
    format: strOrNull(rs, 'format'),
    coverPath: strOrNull(rs, 'cover_path'),
    totalPages: num(rs, 'total_pages'),
    lastChapter: num(rs, 'last_chapter'),
    lastOffset: num(rs, 'last_offset'),
    percent: num(rs, 'percent'),
    addedAt: num(rs, 'added_at'),
    createdAt: num(rs, 'created_at'),
    updatedAt: num(rs, 'updated_at'),
    deletedAt: null
  };
}
