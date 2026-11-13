/**
 * 微光 · 本地推断规则
 *
 * 设计前提：录入只能要求「一句话」，所以维度与数值都由这段纯本地逻辑后置推断，
 * 用户不确认也能存（未分类落 NULL），日后在回顾页还能补标。
 * 不联网、不接模型、不做中文分词；全部是 ArkTS 里最稳的字符串操作。
 */

import { GrowthRow } from '../db/Models';

/** 六个成长维度 + 兜底；顺序也是回顾页分布的默认顺序 */
export const GROWTH_CATEGORIES: string[] = [
  '自律', '身体', '学习', '关系', '心性', '尝试', '未分类'
];
export const GROWTH_UNCATEGORIZED: string = '未分类';

interface CategoryRule {
  category: string;
  words: string[];
}

/** 命中词最多的维度胜出；平手时取靠前的维度；一个都没命中就是未分类 */
const RULES: CategoryRule[] = [
  {
    category: '自律',
    words: ['没刷', '没有刷', '少刷', '忍住', '没浪费', '没有浪费', '按时', '准时',
      '提前', '不拖延', '专注', '戒', '控制住', '放下手机', '早点', '按计划']
  },
  {
    category: '身体',
    words: ['健身', '跑步', '走路', '散步', '运动', '瑜伽', '拉伸', '游泳', '骑车',
      '俯卧撑', '锻炼', '早睡', '睡够', '喝水', '步数', '公里']
  },
  {
    category: '学习',
    words: ['读完', '读书', '看书', '学习', '背', '单词', '上课', '笔记', '练习',
      '弄懂', '学会', '复盘', '研究', '写完了', '整理了']
  },
  {
    category: '关系',
    words: ['陪', '聊天', '打电话', '家人', '朋友', '同事', '沟通', '道谢',
      '道歉', '倾听', '帮了', '主动联系']
  },
  {
    category: '心性',
    words: ['没生气', '平静', '耐心', '不焦虑', '稳住', '接受了', '放过', '想开',
      '冷静', '不再纠结', '允许', '不急', '没慌']
  },
  {
    category: '尝试',
    words: ['第一次', '试着', '尝试', '主动', '鼓起', '报名', '开口', '开始做',
      '新学', '第一次用']
  }
];

const AMOUNT_UNITS: string[] = [
  '分钟', '小时', '页', '公里', '千米', '次', '本', '组', '圈', '天'
];

/** 高频词只从这张白名单里数，避免引入分词器；用于回顾页「这个月常提到」 */
export const HOT_WORDS: string[] = [
  '第一次', '健身', '读完', '没刷', '提前', '专注', '跑步', '散步', '早睡',
  '主动', '耐心', '复盘', '尝试', '背单词', '陪', '学会', '整理', '忍住',
  '没生气', '写完', '看书', '早睡', '沟通', '没浪费'
];

export interface GrowthAmount {
  amount: number;
  unit: string;
}

export function guessCategory(content: string): string {
  let best: string = GROWTH_UNCATEGORIZED;
  let bestScore: number = 0;
  for (const rule of RULES) {
    let score: number = 0;
    for (const word of rule.words) {
      if (content.indexOf(word) >= 0) {
        score++;
      }
    }
    if (score > bestScore) {
      bestScore = score;
      best = rule.category;
    }
  }
  return best;
}

/** 从「健身了 30 分钟」这类正文里抓第一个「数字 + 单位」；抓不到返回 null */
export function parseAmount(text: string): GrowthAmount | null {
  let i: number = 0;
  while (i < text.length) {
    if (!isDigit(text, i)) {
      i++;
      continue;
    }
    let j: number = i;
    while (j < text.length && (isDigit(text, j) || text.charAt(j) === '.')) {
      j++;
    }
    const value: number = Number(text.substring(i, j));
    let k: number = j;
    while (k < text.length && text.charAt(k) === ' ') {
      k++;
    }
    if (value > 0) {
      for (const unit of AMOUNT_UNITS) {
        if (text.substring(k, k + unit.length) === unit) {
          const found: GrowthAmount = { amount: value, unit: unit };
          return found;
        }
      }
    }
    i = j;
  }
  return null;
}

function isDigit(text: string, index: number): boolean {
  const code: number = text.charCodeAt(index);
  return code >= 48 && code <= 57;
}

/** 未分类落 NULL：推断结果不等于用户确认过的事实，别污染数据 */
export function categoryForDb(label: string): string | null {
  return label === GROWTH_UNCATEGORIZED ? null : label;
}

export function categoryLabel(value: string | null): string {
  return value === null || value.length === 0 ? GROWTH_UNCATEGORIZED : value;
}

export function amountLabel(row: GrowthRow): string {
  if (row.amount === null || row.unit === null) {
    return '';
  }
  return `${row.amount}${row.unit}`;
}
