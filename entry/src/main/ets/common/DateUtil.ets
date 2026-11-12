/** 日期工具：毫秒时间戳 ↔ 'YYYY-MM-DD'，以及原型里的各种展示格式 */

const CN_MONTH: string[] = ['一月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '十一月', '十二月'];
const CN_WEEK: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
const DOW_SHORT: string[] = ['日', '一', '二', '三', '四', '五', '六'];

export interface DayCell {
  date: string;
  dow: string;
  num: string;
  isToday: boolean;
}

function pad(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function toDay(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function today(): string {
  return toDay(new Date());
}

export function todayBig(): string {
  return `${new Date().getDate()}`;
}

export function monthLabel(): string {
  return CN_MONTH[new Date().getMonth()];
}

export function weekdayLabel(): string {
  return CN_WEEK[new Date().getDay()];
}

export function yearLabel(): string {
  return `${new Date().getFullYear()}`;
}

export function formatTime(ts: number): string {
  const d: Date = new Date(ts);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function formatDotDate(ts: number): string {
  const d: Date = new Date(ts);
  return `${d.getFullYear()}.${pad(d.getMonth() + 1)}.${pad(d.getDate())}`;
}

export function formatShortDate(ts: number): string {
  const d: Date = new Date(ts);
  return `${pad(d.getMonth() + 1)}.${pad(d.getDate())}`;
}

export function shortWeekdayOf(dateStr: string): string {
  const parts: string[] = dateStr.split('-');
  const d: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  return DOW_SHORT[d.getDay()];
}

/** 以周一为首的当前一周，计划页的周条和心情周视图都用它 */
export function currentWeek(): DayCell[] {
  const now: Date = new Date();
  const shift: number = (now.getDay() + 6) % 7;
  const cells: DayCell[] = [];
  for (let i: number = 0; i < 7; i++) {
    const d: Date = new Date(now.getTime());
    d.setDate(now.getDate() - shift + i);
    cells.push({
      date: toDay(d),
      dow: DOW_SHORT[d.getDay()],
      num: `${d.getDate()}`,
      isToday: toDay(d) === today()
    });
  }
  return cells;
}

/** 从 n-1 天前到今天的日期字符串，旧 → 新 */
export function lastNDays(n: number): string[] {
  const now: Date = new Date();
  const days: string[] = [];
  for (let i: number = n - 1; i >= 0; i--) {
    const d: Date = new Date(now.getTime());
    d.setDate(now.getDate() - i);
    days.push(toDay(d));
  }
  return days;
}

/** 最近七天，最后一天是今天：首页习惯点阵与心情小柱都用它 */
export function lastSevenDays(): DayCell[] {
  const now: Date = new Date();
  const cells: DayCell[] = [];
  for (let i: number = 6; i >= 0; i--) {
    const d: Date = new Date(now.getTime());
    d.setDate(now.getDate() - i);
    cells.push({
      date: toDay(d),
      dow: DOW_SHORT[d.getDay()],
      num: `${d.getDate()}`,
      isToday: i === 0
    });
  }
  return cells;
}

export function isOverdue(dueAt: number | null): boolean {
  if (dueAt === null) {
    return false;
  }
  return dueAt < Date.now();
}

export function dueLabel(dueAt: number | null): string {
  if (dueAt === null) {
    return '不限时间';
  }
  return formatTime(dueAt);
}

/** 时间戳转成当天的 'HH:mm' 毫秒值，录入弹层里选时间用 */
export function atToday(hour: number, minute: number): number {
  const d: Date = new Date();
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

/** 指定 'YYYY-MM-DD' 那天的某个时刻，计划页选非今天时用 */
export function atDay(dateStr: string, hour: number, minute: number): number {
  const parts: string[] = dateStr.split('-');
  const d: Date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), hour, minute, 0, 0);
  return d.getTime();
}
