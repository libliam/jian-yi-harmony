/**
 * 简忆 · 统一视觉常量
 *
 * 与原型 :root 的 CSS 变量、resources/base/element/color.json 三处一一对应。
 * 页面只允许从这里取色，禁止散落十六进制字面量（项目规则 5）。
 */

export class C {
  static readonly paper: string = '#F6F2E9';
  static readonly paper2: string = '#EFE9DC';
  static readonly paper3: string = '#E6DECD';
  static readonly ink: string = '#1B1917';
  static readonly ink2: string = '#4B463F';
  static readonly ink3: string = '#8E8779';
  static readonly cinnabar: string = '#B4432E';
  static readonly cinnabarSoft: string = '#F3E5E0';
  static readonly sage: string = '#6F7B68';
  static readonly gold: string = '#C08B3E';
  static readonly rule: string = '#DED7C9';
  static readonly ruleSoft: string = '#EAE4D8';
  static readonly dark: string = '#232019';
  static readonly darkText: string = '#F3EEE3';
  static readonly darkSub: string = '#9A9185';
  static readonly white: string = '#FFFFFF';
}

/** 卡片 16–20、按钮胶囊 100（项目规则 5） */
export class S {
  static readonly pad: number = 24;
  static readonly cardRadius: number = 18;
  static readonly smallRadius: number = 12;
  static readonly pill: number = 100;
  static readonly tabbarHeight: number = 76;
  static readonly contentBottom: number = 100;
}

/** 标题宋体、正文无衬线；正文行高不低于 1.9 */
export const SERIF: string = 'serif';
export const SANS: string = 'sans-serif';

export const MOOD_LABELS: string[] = ['低落', '疲惫', '平静', '轻快', '明亮'];

export function priorityColor(priority: number): string {
  if (priority === 2) {
    return C.cinnabar;
  }
  if (priority === 1) {
    return C.gold;
  }
  return C.sage;
}

export function priorityLabel(priority: number): string {
  if (priority === 2) {
    return '高';
  }
  if (priority === 1) {
    return '中';
  }
  return '低';
}
