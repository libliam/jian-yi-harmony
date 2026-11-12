/**
 * ResultSet 取值助手
 *
 * getString / getLong 遇到 NULL 会抛异常，所以可空列必须先 isColumnNull。
 * 这层封装不是为了好看，是为了让每个查询里少写六行一模一样的判断。
 */

import { relationalStore } from '@kit.ArkData';

export function str(rs: relationalStore.ResultSet, col: string): string {
  return rs.getString(rs.getColumnIndex(col));
}

export function strOrNull(rs: relationalStore.ResultSet, col: string): string | null {
  const i: number = rs.getColumnIndex(col);
  return rs.isColumnNull(i) ? null : rs.getString(i);
}

export function num(rs: relationalStore.ResultSet, col: string): number {
  return rs.getLong(rs.getColumnIndex(col));
}

export function numOrNull(rs: relationalStore.ResultSet, col: string): number | null {
  const i: number = rs.getColumnIndex(col);
  return rs.isColumnNull(i) ? null : rs.getLong(i);
}
