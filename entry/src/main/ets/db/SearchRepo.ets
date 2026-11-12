/**
 * 全局搜索：一次搜全部
 *
 * 这一层只做聚合，不写跨表 SQL —— 每个业务域的查询仍归各自的仓库。
 * 原型里「不用记分类，想到什么词就搜什么词」就是这条规则。
 */

import { searchEntries, displayTags } from './EntryRepo';
import { searchTodos } from './TodoRepo';
import { searchThoughts } from './ThoughtRepo';
import { searchBooks } from './BookRepo';
import { EntryRow, TodoRow, ThoughtRow, BookRow, TodoBucket } from './Models';

/** tab 序号与 Index 的五个主视图一致 */
export const TAB_TODAY: number = 0;
export const TAB_QUOTES: number = 1;
export const TAB_TODO: number = 2;
export const TAB_READER: number = 3;
export const TAB_PLAN: number = 4;

export const SEARCH_GROUPS: string[] = ['语录', '待办', '想法', '书'];

export interface SearchHit {
  id: string;
  group: string;
  title: string;
  sub: string;
  tab: number;
  /** 待办页分段：today / later / think */
  pane: string;
}

export async function searchAll(keyword: string): Promise<SearchHit[]> {
  const q: string = keyword.trim();
  if (q.length === 0) {
    return [];
  }

  const entries: EntryRow[] = await searchEntries(q);
  const todos: TodoRow[] = await searchTodos(q);
  const thoughts: ThoughtRow[] = await searchThoughts(q);
  const books: BookRow[] = await searchBooks(q);

  const hits: SearchHit[] = [];

  for (const e of entries) {
    hits.push({
      id: e.id,
      group: '语录',
      title: e.content,
      sub: e.source ? e.source : displayTags(e.tags),
      tab: TAB_QUOTES,
      pane: ''
    });
  }

  for (const t of todos) {
    hits.push({
      id: t.id,
      group: '待办',
      title: t.title,
      sub: t.bucket === TodoBucket.Today ? '今日待办' : '长期清单',
      tab: TAB_TODO,
      pane: t.bucket === TodoBucket.Today ? 'today' : 'later'
    });
  }

  for (const th of thoughts) {
    hits.push({
      id: th.id,
      group: '想法',
      title: th.content,
      sub: '待思清单 · 已想 ' + th.thinkCount + ' 次',
      tab: TAB_TODO,
      pane: 'think'
    });
  }

  for (const b of books) {
    hits.push({
      id: b.id,
      group: '书',
      title: b.title,
      sub: b.author ? b.author : '我的书架',
      tab: TAB_READER,
      pane: ''
    });
  }

  // 按分组顺序排，保证「语录 → 待办 → 想法 → 书」和原型一致
  const ordered: SearchHit[] = [];
  for (const g of SEARCH_GROUPS) {
    for (const h of hits) {
      if (h.group === g) {
        ordered.push(h);
      }
    }
  }
  return ordered;
}

/** 搜不到时给出原型里那句话 */
export function emptySearchTip(q: string): string {
  return `没有找到「${q}」。换个词试试，或者干脆记一条新的。`;
}
