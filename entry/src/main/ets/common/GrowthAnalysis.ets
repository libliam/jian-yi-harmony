/**
 * 微光 · 回顾统计（全部现算，不落库）
 *
 * 只把证据摆整齐，不下判断：没有评分、没有完成率、没有「你进步了百分之多少」。
 * 数据规模是个人记录量级，取全量后在内存里聚合，比写复杂 SQL 更稳也更好改。
 */

import { GrowthRow } from '../db/Models';
import {
  GROWTH_CATEGORIES, HOT_WORDS, categoryLabel
} from './GrowthTag';

export interface CategoryCount {
  name: string;
  count: number;
}

interface WordCount {
  word: string;
  count: number;
}

export interface GrowthSummary {
  total: number;
  monthCount: number;
  prevMonthCount: number;
  streak: number;
  /** 与传入 dates 一一对应的每日条数 */
  days: number[];
  /** 固定维度顺序，便于和上月逐项对比 */
  categories: CategoryCount[];
  prevCounts: number[];
  topWords: string[];
  /** 本月识别到的时长合计（分钟）；识别不到的记录不计入 */
  totalMinutes: number;
  thenRow: GrowthRow | null;
  earliest: GrowthRow | null;
}

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function monthPrefix(date: string): string {
  return date.substring(0, 7);
}

export function prevMonthPrefix(): string {
  const d: Date = new Date();
  d.setDate(1);
  d.setMonth(d.getMonth() - 1);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

/** all 需按 date 升序；dates 为要展示的连续日期（旧 → 新，最后一天是今天） */
export function summarize(
  all: GrowthRow[],
  dates: string[],
  thisMonth: string,
  lastMonth: string,
  thenDate: string
): GrowthSummary {
  const monthRows: GrowthRow[] = [];
  const dateCounts: number[] = [];
  for (const d of dates) {
    let n: number = 0;
    for (const r of all) {
      if (r.date === d) {
        n++;
      }
    }
    dateCounts.push(n);
  }

  let prevMonthCount: number = 0;
  for (const r of all) {
    if (monthPrefix(r.date) === lastMonth) {
      prevMonthCount++;
    }
  }

  const prevCounts: number[] = [];
  for (const name of GROWTH_CATEGORIES) {
    let n: number = 0;
    for (const r of all) {
      if (monthPrefix(r.date) === lastMonth && categoryLabel(r.category) === name) {
        n++;
      }
    }
    prevCounts.push(n);
  }

  const categories: CategoryCount[] = [];
  for (const name of GROWTH_CATEGORIES) {
    let n: number = 0;
    for (const r of all) {
      if (monthPrefix(r.date) === thisMonth && categoryLabel(r.category) === name) {
        n++;
        monthRows.push(r);
      }
    }
    categories.push({ name: name, count: n });
  }

  // 连续的判断允许「今天还没记」：从今天往前，今天空则退到昨天起算
  let streak: number = 0;
  let cursor: number = dateCounts.length - 1;
  if (cursor > 0 && dateCounts[cursor] === 0) {
    cursor--;
  }
  for (let i: number = cursor; i >= 0; i--) {
    if (dateCounts[i] > 0) {
      streak++;
    } else {
      break;
    }
  }

  let totalMinutes: number = 0;
  for (const r of monthRows) {
    if (r.amount !== null && r.unit !== null) {
      if (r.unit === '分钟') {
        totalMinutes += r.amount;
      } else if (r.unit === '小时') {
        totalMinutes += r.amount * 60;
      }
    }
  }

  let thenRow: GrowthRow | null = null;
  for (const r of all) {
    if (r.date <= thenDate) {
      thenRow = r;
    }
  }

  return {
    total: all.length,
    monthCount: monthRows.length,
    prevMonthCount: prevMonthCount,
    streak: streak,
    days: dateCounts,
    categories: categories,
    prevCounts: prevCounts,
    topWords: topWords(monthRows),
    totalMinutes: Math.round(totalMinutes),
    thenRow: thenRow,
    earliest: all.length > 0 ? all[0] : null
  };
}

function topWords(rows: GrowthRow[]): string[] {
  const counts: WordCount[] = [];
  for (const word of HOT_WORDS) {
    let n: number = 0;
    for (const r of rows) {
      if (r.content.indexOf(word) >= 0) {
        n++;
      }
    }
    if (n > 0) {
      counts.push({ word: word, count: n });
    }
  }

  const top: string[] = [];
  for (let pass: number = 0; pass < 3; pass++) {
    let bestIndex: number = -1;
    let best: number = 0;
    for (let i: number = 0; i < counts.length; i++) {
      if (counts[i].count > best) {
        best = counts[i].count;
        bestIndex = i;
      }
    }
    if (bestIndex < 0) {
      break;
    }
    top.push(counts[bestIndex].word);
    counts[bestIndex].count = 0;
  }
  return top;
}

/** 与上月比：只陈述数量变化，不做评价 */
export function compareText(sum: GrowthSummary): string {
  const diff: number = sum.monthCount - sum.prevMonthCount;
  if (sum.prevMonthCount === 0) {
    return sum.monthCount > 0 ? '这个月开始留下记录了' : '还没有记录，写第一点就好';
  }
  if (diff > 0) {
    return `比上月多留下 ${diff} 点`;
  }
  if (diff < 0) {
    return `比上月少 ${0 - diff} 点，慢慢来就好`;
  }
  return '和上月一样多';
}

/** 本月第一次出现的维度——这往往比条数更像「成长」 */
export function newCategoryText(sum: GrowthSummary): string {
  const names: string[] = [];
  for (let i: number = 0; i < sum.categories.length; i++) {
    const item: CategoryCount = sum.categories[i];
    if (item.name !== '未分类' && item.count > 0 && sum.prevCounts[i] === 0) {
      names.push(item.name);
    }
  }
  if (names.length === 0) {
    return '';
  }
  return `这个月第一次记下「${names[0]}」`;
}
