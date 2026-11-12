/**
 * 待办页 · 路线图第 2 步
 *
 * 列表 + 新增 + 勾选，全部走 RelationalStore，用来验证数据层确实跑通。
 * 三个分段与原型一致：今日 / 长期 / 待思。
 */

import { TodoRow, ThoughtRow, TodoBucket, ThoughtStatus } from '../db/Models';
import { listTodos, setTodoDone, countTodos, TodoStat } from '../db/TodoRepo';
import { listThoughts, bumpThought } from '../db/ThoughtRepo';
import { bumpRevision, setTodoPane, openSheet } from '../common/Bus';
import { C, S, SERIF, priorityColor, priorityLabel } from '../common/Theme';
import { dueLabel, isOverdue, formatShortDate } from '../common/DateUtil';
import { PageHead, EmptyState } from './Parts';

@Component
export struct TodoView {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @StorageLink('uiTodoPane') pane: string = 'today';
  @State todayList: TodoRow[] = [];
  @State laterList: TodoRow[] = [];
  @State thoughts: ThoughtRow[] = [];
  @State todayStat: TodoStat = { total: 0, done: 0, overdue: 0 };
  @State laterStat: TodoStat = { total: 0, done: 0, overdue: 0 };

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.todayList = await listTodos(TodoBucket.Today, true);
    this.laterList = await listTodos(TodoBucket.Later, true);
    this.thoughts = await listThoughts(ThoughtStatus.Open);
    this.todayStat = await countTodos(TodoBucket.Today);
    this.laterStat = await countTodos(TodoBucket.Later);
  }

  private visibleTodos(): TodoRow[] {
    return this.pane === 'later' ? this.laterList : this.todayList;
  }

  private async toggle(item: TodoRow): Promise<void> {
    await setTodoDone(item.id, item.done === 0);
    bumpRevision();
    await this.load();
  }

  private async think(id: string): Promise<void> {
    await bumpThought(id);
    await this.load();
  }

  build() {
    Column() {
      PageHead({ eyebrow: 'Tasks', title: '待办' })

      // 分段
      Row() {
        this.segButton('今日', this.todayStat.total, 'today')
        this.segButton('长期', this.laterStat.total, 'later')
        this.segButton('待思', this.thoughts.length, 'think')
      }
      .width('100%')
      .padding(3)
      .borderRadius(10)
      .backgroundColor(C.paper2)
      .margin({ bottom: 8 })

      Scroll() {
        Column() {
          if (this.pane === 'think') {
            this.thinkPane()
          } else {
            this.todoPane()
          }
        }
        .width('100%')
        .padding({ bottom: S.contentBottom })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ left: S.pad, right: S.pad })
  }

  @Builder
  segButton(label: string, count: number, key: string) {
    Text(`${label} ${count}`)
      .fontSize(11.5)
      .fontColor(this.pane === key ? C.ink : C.ink3)
      .fontWeight(this.pane === key ? FontWeight.Bold : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 8, bottom: 8 })
      .borderRadius(8)
      .backgroundColor(this.pane === key ? C.paper : C.paper2)
      .onClick(() => setTodoPane(key))
  }

  @Builder
  todoPane() {
    // 统计数字查询时现算，不落库（项目规则 3）
    Row() {
      this.statBox(`${this.todayStat.total}`, '本段待办')
      this.statBox(`${this.todayStat.done}`, '已完成')
      this.statBox(`${this.todayStat.overdue}`, '已顺延')
    }
    .width('100%')
    .padding({ top: 2, bottom: 20 })

    this.groupLabel(this.pane === 'today' ? '今天' : '长期 · 有空再做')

    if (this.visibleTodos().length === 0) {
      EmptyState({
        mark: '○',
        text: '这一段还没有事情。\n先记下一件，就不必一直放在脑子里。',
        action: '加个待办',
        sheet: 'task'
      })
    } else {
      ForEach(this.visibleTodos(), (item: TodoRow) => {
        this.taskRow(item)
      }, (item: TodoRow) => item.id)
    }

    Button(`＋　${this.pane === 'today' ? '加一件今天要做的事' : '往长期清单里加一件'}`)
      .fontSize(12)
      .fontColor(C.ink3)
      .backgroundColor(C.paper)
      .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
      .borderRadius(14)
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .margin({ top: 14 })
      .onClick(() => this.openTaskSheet())
  }

  @Builder
  thinkPane() {
    this.groupLabel('待思 · 想到了先放着')

    if (this.thoughts.length === 0) {
      EmptyState({
        mark: '·',
        text: '还没有搁着的念头。\n不急着想清楚，先放进待思吧。',
        action: '存一个想法',
        sheet: 'think'
      })
    } else {
      ForEach(this.thoughts, (item: ThoughtRow) => {
        Row() {
          Row()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(C.cinnabarSoft)
            .border({ width: 1, color: C.cinnabar })
            .margin({ top: 8, right: 12 })
          Column() {
            Text(item.content)
              .fontFamily(SERIF)
              .fontSize(14.5)
              .lineHeight(27)
              .fontColor(C.ink)
            Text(`记于 ${formatShortDate(item.createdAt)} · 已想 ${item.thinkCount} 次`)
              .fontSize(9.5)
              .fontColor(C.ink3)
              .margin({ top: 8 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .border({ width: { bottom: 1 }, color: C.ruleSoft })
        .alignItems(VerticalAlign.Top)
        .onClick(() => this.think(item.id))
      }, (item: ThoughtRow) => item.id)
    }

    Button('＋　存一个想法')
      .fontSize(12)
      .fontColor(C.ink3)
      .backgroundColor(C.paper)
      .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
      .borderRadius(14)
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .margin({ top: 22 })
      .onClick(() => this.openTaskSheet())
  }

  @Builder
  taskRow(item: TodoRow) {
    Row() {
      Row() {
        if (item.done === 1) {
          Text('✓').fontSize(11).fontColor(C.paper)
        }
      }
      .width(19)
      .height(19)
      .borderRadius(10)
      .border({ width: 1.4, color: item.done === 1 ? C.sage : C.ink3 })
      .backgroundColor(item.done === 1 ? C.sage : C.paper)
      .justifyContent(FlexAlign.Center)
      .margin({ top: 1, right: 13 })
      .onClick(() => this.toggle(item))

      Column() {
        Text(item.title)
          .fontSize(13.5)
          .lineHeight(21)
          .fontColor(item.done === 1 ? C.ink3 : C.ink)
          .decoration({
            type: item.done === 1 ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: C.ink3
          })
        Row() {
          Row()
            .width(5)
            .height(5)
            .borderRadius(3)
            .backgroundColor(priorityColor(item.priority))
            .margin({ right: 8 })
          Text(`${dueLabel(item.dueAt)} · ${priorityLabel(item.priority)}优先`)
            .fontSize(10.5)
            .fontColor(C.ink3)
          if (isOverdue(item.dueAt) && item.done === 0) {
            Text('已顺延')
              .fontSize(9.5)
              .fontColor(C.cinnabar)
              .border({ width: 1, color: C.rule })
              .borderRadius(3)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .margin({ left: 8 })
          }
        }
        .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: C.ruleSoft })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  statBox(value: string, label: string) {
    Column() {
      Text(value)
        .fontFamily(SERIF)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.ink)
      Text(label)
        .fontSize(11)
        .fontColor(C.ink3)
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .margin({ right: 22 })
  }

  @Builder
  groupLabel(text: string) {
    Row() {
      Text(text)
        .fontSize(10.5)
        .fontColor(C.ink3)
        .letterSpacing(2)
      Row()
        .height(1)
        .backgroundColor(C.ruleSoft)
        .layoutWeight(1)
        .margin({ left: 10 })
    }
    .width('100%')
    .margin({ top: 22, bottom: 6 })
  }

  /** 待思段走「存个想法」，其余走「新建待办」 */
  private openTaskSheet(): void {
    openSheet(this.pane === 'think' ? 'think' : 'task');
  }
}
