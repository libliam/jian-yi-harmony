/**
 * 微光仓库
 *
 * 除正文与日期外的字段都允许为 NULL：录入时推断不出来、用户也没确认，
 * 就老老实实空着，之后在回顾页补标即可。派生统计不在这里，见 common/GrowthAnalysis.ets。
 */

import { relationalStore } from '@kit.ArkData';
import { db, newId } from './JianYiDb';
import { GrowthRow } from './Models';
import { str, strOrNull, num, realOrNull } from './RowUtil';

const TABLE: string = 'growth';

/** createdAt 只给示例数据用来铺开时间线，正常录入一律用当前时间 */
export async function addGrowth(
  content: string,
  date: string,
  category: string | null,
  amount: number | null,
  unit: string | null,
  createdAt?: number
): Promise<string> {
  let now: number = Date.now();
  if (createdAt !== undefined) {
    now = createdAt;
  }
  const id: string = newId();
  const row: relationalStore.ValuesBucket = {
    'id': id,
    'date': date,
    'content': content,
    'category': category,
    'amount': amount,
    'unit': unit,
    'created_at': now,
    'updated_at': now
  };
  await db().insert(TABLE, row);
  return id;
}

/** 一段日期内的微光，旧 → 新，便于按日分组或直接聚合 */
export async function listGrowth(fromDate: string, toDate: string): Promise<GrowthRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at')
    .greaterThanOrEqualTo('date', fromDate)
    .lessThanOrEqualTo('date', toDate);
  predicates.orderByAsc('date').orderByAsc('created_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: GrowthRow[] = collect(rs);
  return list;
}

/** 全部未删除记录，旧 → 新；个人记录量级，回顾页一次取完再内存聚合 */
export async function listAllGrowth(): Promise<GrowthRow[]> {
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.isNull('deleted_at');
  predicates.orderByAsc('date').orderByAsc('created_at');

  const rs: relationalStore.ResultSet = await db().query(predicates);
  const list: GrowthRow[] = collect(rs);
  return list;
}

/** 全局搜索：正文和维度都能命中 */
export async function searchGrowth(keyword: string): Promise<GrowthRow[]> {
  const like: string = `%${keyword}%`;
  const rs: relationalStore.ResultSet = await db().querySql(
    `SELECT * FROM growth
     WHERE deleted_at IS NULL AND (content LIKE ? OR category LIKE ?)
     ORDER BY date DESC, created_at DESC LIMIT 30`,
    [like, like]
  );
  const list: GrowthRow[] = collect(rs);
  return list;
}

/** 回顾页补标维度；传 null 表示改回「未分类」 */
export async function updateGrowthCategory(id: string, category: string | null): Promise<void> {
  const row: relationalStore.ValuesBucket = {
    'category': category,
    'updated_at': Date.now()
  };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

export async function removeGrowth(id: string): Promise<void> {
  const now: number = Date.now();
  const row: relationalStore.ValuesBucket = { 'deleted_at': now, 'updated_at': now };
  const predicates = new relationalStore.RdbPredicates(TABLE);
  predicates.equalTo('id', id);
  await db().update(row, predicates);
}

function collect(rs: relationalStore.ResultSet): GrowthRow[] {
  const list: GrowthRow[] = [];
  while (rs.goToNextRow()) {
    list.push(mapGrowth(rs));
  }
  rs.close();
  return list;
}

function mapGrowth(rs: relationalStore.ResultSet): GrowthRow {
  return {
    id: str(rs, 'id'),
    date: str(rs, 'date'),
    content: str(rs, 'content'),
    category: strOrNull(rs, 'category'),
    amount: realOrNull(rs, 'amount'),
    unit: strOrNull(rs, 'unit'),
    createdAt: num(rs, 'created_at'),
    updatedAt: num(rs, 'updated_at'),
    deletedAt: null
  };
}
