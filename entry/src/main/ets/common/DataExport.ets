/**
 * 简忆 · 数据导出
 *
 * 两块能力：
 * 1. 月度成长小结导出：把 GrowthSummary 排成一份纯文本，存成 .txt
 * 2. 全量数据备份导出：各表原始行导成结构化 JSON，存成 .json
 *
 * 都用系统 DocumentViewPicker.save() 让用户选保存位置（不依赖 ShareKit，标准 SDK 可用）。
 * 流程：内容写应用沙箱临时文件 → picker.save 拿目标 URI → copyFile 过去。
 * 导出只读不写业务数据，用户拿到的文件含全部原文，隐私由用户自己保管。
 */

import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { relationalStore } from '@kit.ArkData';
import { db } from '../db/JianYiDb';
import { GrowthSummary } from './GrowthAnalysis';
import { compareText, newCategoryText } from './GrowthAnalysis';
import { categoryLabel } from './GrowthTag';
import { GrowthRow } from '../db/Models';

export interface ExportResult {
  ok: boolean;
  message: string;
}

/** 全量备份 JSON 结构：按表名分组的原始行 */
interface BackupPayload {
  entry: Object[];
  todo: Object[];
  thought: Object[];
  habit: Object[];
  habit_record: Object[];
  mood: Object[];
  event: Object[];
  book: Object[];
  growth: Object[];
}

/** 导出月度成长小结（纯文本 .txt） */
export async function exportMonthlySummary(
  context: common.UIAbilityContext,
  summary: GrowthSummary,
  month: string,
  rows: GrowthRow[]
): Promise<ExportResult> {
  const lines: string[] = [];
  lines.push('简忆 · 月度成长小结');
  lines.push(`${month}`);
  lines.push('========================');
  lines.push('');
  lines.push(`本月留下 ${summary.monthCount} 点，${compareText(summary)}。`);
  lines.push(`连续记录 ${summary.streak} 天，累计 ${summary.total} 点。`);
  if (summary.totalMinutes > 0) {
    lines.push(`这个月记下的时长，合起来约 ${summary.totalMinutes} 分钟。`);
  }
  const fresh: string = newCategoryText(summary);
  if (fresh.length > 0) {
    lines.push(fresh + '。');
  }
  lines.push('');
  lines.push('—— 维度分布 ——');
  for (const item of summary.categories) {
    lines.push(`${item.name}：${item.count} 点`);
  }
  if (summary.topWords.length > 0) {
    lines.push('');
    lines.push('—— 常提到的 ——');
    lines.push(summary.topWords.join('、'));
  }
  lines.push('');
  lines.push('—— 本月记录 ——');
  for (const r of rows) {
    if (r.date.substring(0, 7) !== month) {
      continue;
    }
    const cat: string = categoryLabel(r.category);
    const amount: string = r.amount !== null && r.unit !== null ? `（${r.amount}${r.unit}）` : '';
    lines.push(`[${r.date}] ${cat}${amount}：${r.content}`);
  }
  lines.push('');
  lines.push('只把证据摆整齐，其余的留给你自己看。');
  return saveText(context, lines.join('\n'), `简忆-月度小结-${month}.txt`, '.txt');
}

/** 导出全量数据备份（JSON） */
export async function exportAllData(context: common.UIAbilityContext): Promise<ExportResult> {
  try {
    const payload: BackupPayload = {
      entry: await queryAll('entry'),
      todo: await queryAll('todo'),
      thought: await queryAll('thought'),
      habit: await queryAll('habit'),
      habit_record: await queryAll('habit_record'),
      mood: await queryAll('mood'),
      event: await queryAll('event'),
      book: await queryAll('book'),
      growth: await queryAll('growth')
    };
    const stamp: string = new Date().toISOString().substring(0, 10);
    return saveText(context, JSON.stringify(payload), `简忆-数据备份-${stamp}.json`, '.json');
  } catch (err) {
    return { ok: false, message: '读取数据时出错，导出取消。' };
  }
}

/** 读一张表的所有列（导出场景只读，不改业务数据） */
async function queryAll(table: string): Promise<Object[]> {
  const rs: relationalStore.ResultSet = await db().querySql(`SELECT * FROM ${table}`);
  const rows: Object[] = [];
  while (rs.goToNextRow()) {
    const row: Record<string, Object | null> = {};
    const cols: string[] = rs.getColumnNames();
    for (const col of cols) {
      const idx: number = rs.getColumnIndex(col);
      const type: relationalStore.ColumnType = rs.getColumnTypeSync(idx);
      if (type === relationalStore.ColumnType.INTEGER) {
        row[col] = rs.getLong(idx);
      } else if (type === relationalStore.ColumnType.REAL) {
        row[col] = rs.getDouble(idx);
      } else if (type === relationalStore.ColumnType.NULL) {
        row[col] = null;
      } else {
        row[col] = rs.getString(idx);
      }
    }
    rows.push(row);
  }
  rs.close();
  return rows;
}

/** 写沙箱临时文件 → 系统保存选择器 → 复制到用户选的位置 */
async function saveText(
  context: common.UIAbilityContext,
  content: string,
  fileName: string,
  suffix: string
): Promise<ExportResult> {
  const tmpDir: string = `${context.filesDir}/export`;
  try {
    fileIo.mkdirSync(tmpDir, true);
  } catch (err) {
    // 目录已存在
  }
  const tmp: string = `${tmpDir}/export_${Date.now()}${suffix}`;
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(tmp, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, content);
  } catch (err) {
    if (file !== null) {
      fileIo.closeSync(file);
    }
    return { ok: false, message: '写入临时文件失败。' };
  }
  fileIo.closeSync(file);

  try {
    const options: picker.DocumentSaveOptions = {
      newFileNames: [fileName],
      fileSuffixChoices: [suffix]
    };
    const savePicker = new picker.DocumentViewPicker(context);
    const uris: string[] = await savePicker.save(options);
    if (uris.length === 0) {
      return { ok: false, message: '没有选择保存位置。' };
    }
    const src: fileIo.File = fileIo.openSync(tmp, fileIo.OpenMode.READ_ONLY);
    const dst: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    fileIo.copyFileSync(src.fd, dst.fd);
    fileIo.closeSync(src);
    fileIo.closeSync(dst);
    return { ok: true, message: '已保存到你选的位置。' };
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    return { ok: false, message: '保存失败，请换个位置重试。' };
  }
}
