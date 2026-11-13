/**
 * 今日页 · 微光卡片
 *
 * 一步录入：打完点「记下」或按回车即存，不弹层、不选类型、不填时长。
 * 维度与数值由 GrowthTag 后置推断，用户一个字段都不用多填。
 */

import { GrowthRow } from '../db/Models';
import { addGrowth, listGrowth } from '../db/GrowthRepo';
import {
  guessCategory, parseAmount, categoryForDb, categoryLabel, GrowthAmount
} from '../common/GrowthTag';
import { bumpRevision, openGrowth } from '../common/Bus';
import { C, S, SERIF } from '../common/Theme';
import { today, formatTime } from '../common/DateUtil';

@Component
export struct GrowthCard {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @State text: string = '';
  @State todayCount: number = 0;
  @State recent: GrowthRow[] = [];
  @State hint: string = '';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const day: string = today();
    const rows: GrowthRow[] = await listGrowth(day, day);
    const latest: GrowthRow[] = [];
    for (let i: number = rows.length - 1; i >= 0 && latest.length < 2; i--) {
      latest.push(rows[i]);
    }
    this.todayCount = rows.length;
    this.recent = latest;
  }

  private async save(): Promise<void> {
    const content: string = this.text.trim();
    if (content.length === 0) {
      this.hint = '写一句就好，多小的事都算。';
      return;
    }
    const label: string = guessCategory(content);
    const amount: GrowthAmount | null = parseAmount(content);
    await addGrowth(
      content,
      today(),
      categoryForDb(label),
      amount === null ? null : amount.amount,
      amount === null ? null : amount.unit
    );
    this.text = '';
    this.hint = '';
    bumpRevision();
    await this.load();
  }

  build() {
    Column() {
      Row() {
        Text('今日微光')
          .fontFamily(SERIF)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(C.ink)
        Blank()
        Text(`${this.todayCount} 点`)
          .fontSize(10.5)
          .fontColor(C.ink3)
      }
      .width('100%')

      Text('今天哪一点比昨天好？多小的事都算。')
        .fontSize(10.5)
        .fontColor(C.ink3)
        .margin({ top: 6, bottom: 12 })

      Row() {
        TextInput({ placeholder: '比如：中午没刷短视频', text: this.text })
          .layoutWeight(1)
          .fontSize(12.5)
          .fontColor(C.ink)
          .backgroundColor(C.paper)
          .padding({ top: 8, bottom: 8, left: 10, right: 10 })
          .borderRadius(S.smallRadius)
          .onChange((value: string) => {
            this.text = value;
            this.hint = '';
          })
          .onSubmit(() => {
            this.save();
          })
        Text('记下')
          .fontSize(11.5)
          .fontColor(C.paper)
          .backgroundColor(C.ink)
          .borderRadius(S.pill)
          .padding({ left: 15, right: 15, top: 9, bottom: 9 })
          .margin({ left: 8 })
          .onClick(() => this.save())
      }
      .width('100%')

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(10.5)
          .fontColor(C.cinnabar)
          .margin({ top: 9 })
          .alignSelf(ItemAlign.Start)
      }

      if (this.recent.length === 0) {
        Text('今天还没记下什么。写第一点就好。')
          .fontSize(11)
          .fontColor(C.ink3)
          .margin({ top: 14 })
          .alignSelf(ItemAlign.Start)
      } else {
        Column() {
          ForEach(this.recent, (row: GrowthRow) => {
            Row() {
              Row()
                .width(5)
                .height(5)
                .borderRadius(3)
                .backgroundColor(C.cinnabar)
                .margin({ right: 9, top: 5 })
              Text(row.content)
                .fontSize(11.5)
                .fontColor(C.ink2)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${formatTime(row.createdAt)} · ${categoryLabel(row.category)}`)
                .fontSize(9.5)
                .fontColor(C.ink3)
            }
            .width('100%')
            .padding({ top: 9, bottom: 9 })
            .alignItems(VerticalAlign.Top)
            .border({ width: { top: 1 }, color: C.ruleSoft })
          }, (row: GrowthRow) => row.id)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      Text('看看这段日子 →')
        .fontSize(11)
        .fontColor(C.cinnabar)
        .margin({ top: 14 })
        .alignSelf(ItemAlign.Start)
        .onClick(() => openGrowth())
    }
    .width('100%')
    .margin({ top: 18 })
    .padding({ left: 16, right: 16, top: 14, bottom: 16 })
    .borderRadius(16)
    .border({ width: 1, color: C.rule })
    .backgroundColor(C.paper2)
  }
}
