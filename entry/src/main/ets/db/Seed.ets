/**
 * 开发期示例数据
 *
 * 路线图第 2 步要「验证数据层」，空库看不出页面是否正确，所以首次启动灌一份
 * 与原型一致的示例。只在 Preferences 里没打过标记时执行一次，用户删掉的数据
 * 不会被重启复活。正式发布把 SEED_ENABLED 置为 false 即可。
 */

import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { addEntry } from './EntryRepo';
import { addTodo } from './TodoRepo';
import { addThought } from './ThoughtRepo';
import { addHabit, checkIn } from './HabitRepo';
import { addMood } from './MoodRepo';
import { addBook, updateProgress } from './BookRepo';
import { addEvent } from './EventRepo';
import { bumpRevision } from '../common/Bus';
import { EntryType, TodoBucket, Priority, HabitPeriod } from './Models';

const SEED_ENABLED: boolean = true;
const PREF_NAME: string = 'jianyi_meta';
const PREF_KEY: string = 'demo_seeded_v1';

function day(offset: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offset);
  const m: string = String(d.getMonth() + 1).padStart(2, '0');
  const dd: string = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${dd}`;
}

function atHour(hour: number, minute: number): number {
  const d: Date = new Date();
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

export async function seedDemoDataIfEmpty(context: common.Context): Promise<void> {
  if (!SEED_ENABLED) {
    return;
  }

  const opts: preferences.Options = { name: PREF_NAME };
  const pref: preferences.Preferences = await preferences.getPreferences(context, opts);
  const seeded: boolean = pref.getSync(PREF_KEY, false) === true;
  if (seeded) {
    return;
  }

  // —— 语录（原型里的三句 + 一条剪藏）
  await addEntry(EntryType.Quote,
    '我步入丛林，因为我希望活得有意义，我希望活得深刻，汲取生命中所有的精华。',
    '梭罗　《瓦尔登湖》', null, '哲思,自然');
  await addEntry(EntryType.Quote,
    '我们读书，然后才知道自己并不孤单。',
    '罗曼·罗兰　读书笔记', null, '阅读,写作');
  await addEntry(EntryType.Quote,
    '凡是过往，皆为序章。',
    '莎士比亚　《暴风雨》', null, '哲思');
  await addEntry(EntryType.Snippet,
    '大多数人把收藏当成学习，但收藏只完成了「存」，没有完成「取」。知识不是堆积起来的，是在重逢时生长出来的。',
    '公众号　好的笔记系统', 'https://mp.weixin.qq.com/', '剪藏,笔记');

  // —— 待办
  await addTodo('晨间阅读 20 分钟', TodoBucket.Today, Priority.Low,
    atHour(8, 30), '《瓦尔登湖》');
  await addTodo('写第三季度周报，重点是增长数据', TodoBucket.Today, Priority.Mid,
    atHour(9, 30), '工作');
  await addTodo('准备产品评审会材料 · 补最后一页结论', TodoBucket.Today, Priority.High,
    atHour(14, 30), '15:00 开会前');
  await addTodo('把书架上那本《沉思录》读完', TodoBucket.Later, Priority.Low, null, '阅读');
  await addTodo('整理手机里散落的语录，统一归档', TodoBucket.Later, Priority.Low, null, '生活');

  // —— 待思
  await addThought('阅读笔记要不要做成双链，还是保持按时间顺序就好？');
  await addThought('明年的学习计划，是继续横向铺开，还是收窄到一件事？');
  await addThought('为什么我在晚上反而更容易进入状态？这是习惯还是环境？');

  // —— 习惯 + 近七天打卡（连续天数由 habitStreak 现算，不落库）
  const h1: string = await addHabit('晨间阅读 20 分钟', HabitPeriod.Daily, 7, '08:30');
  const h2: string = await addHabit('背 10 个单词', HabitPeriod.Daily, 7, null);
  const h3: string = await addHabit('睡前不碰手机', HabitPeriod.Daily, 7, '23:00');
  for (let i: number = -6; i <= 0; i++) {
    const d: string = day(i);
    await checkIn(h1, d, true);
    await checkIn(h2, d, i % 3 !== 0);
    await checkIn(h3, d, i !== 0);
  }

  // —— 心情（近七天，1 低落 → 5 明亮）
  const levels: number[] = [3, 4, 2, 5, 3, 4, 5];
  const notes: string[] = [
    '平平常常的一天。', '把周报写完了，心里踏实。', '加班到九点，有点累。',
    '在公园读了一下午书。', '一个人吃了顿很慢的晚饭。', '没有刷手机，只是看着窗外发呆。',
    '今天想留下点什么。'
  ];
  for (let i: number = -6; i <= 0; i++) {
    const idx: number = i + 6;
    await addMood(day(i), levels[idx], notes[idx], null);
  }

  // —— 书架
  const walden: string = await addBook('瓦尔登湖', '亨利·戴维·梭罗', null, 'epub', null, 320);
  await updateProgress(walden, 5, 0, 0.40);
  const meditations: string = await addBook('沉思录', '马可·奥勒留', null, 'epub', null, 256);
  await updateProgress(meditations, 1, 0, 0.12);
  await addBook('人类简史', '尤瓦尔·赫拉利', null, 'epub', null, 440);
  const garden: string = await addBook('小径分岔的花园', '博尔赫斯', null, 'epub', null, 192);
  await updateProgress(garden, 3, 0, 0.68);

  // —— 今日安排
  await addEvent('晨间阅读', day(0), atHour(8, 30), atHour(9, 0), 'local');
  await addEvent('深度工作 · 写周报', day(0), atHour(9, 30), atHour(11, 0), 'local');
  await addEvent('产品评审会', day(0), atHour(15, 0), atHour(15, 45), 'local');
  await addEvent('整理今日语录', day(0), atHour(20, 30), null, 'local');

  await pref.put(PREF_KEY, true);
  await pref.flush();
  bumpRevision();
}
