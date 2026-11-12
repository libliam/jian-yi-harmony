/**
 * 语录页 · 路线图第 3 步
 *
 * 分类筛选、收藏、点开详情、记一句 / 剪藏，全部落到 entry 表。
 * tags 的规范化在 EntryRepo 里做，页面只负责展示。
 */

import { EntryRow, EntryType } from '../db/Models';
import { ENTRY_CHIPS, listEntriesByChip, toggleFavorite, countEntries, displayTags } from '../db/EntryRepo';
import { bumpRevision, openSheet, openQuote } from '../common/Bus';
import { C, S, SERIF } from '../common/Theme';
import { formatDotDate } from '../common/DateUtil';
import { PageHead, EmptyState } from './Parts';

@Component
export struct QuoteView {
  @StorageLink('dbRevision') @Watch('onRev') revision: number = 0;
  @State entries: EntryRow[] = [];
  @State total: number = 0;
  @State chip: string = '全部';

  async aboutToAppear(): Promise<void> {
    await this.load();
  }

  onRev(): void {
    this.load();
  }

  private async load(): Promise<void> {
    this.entries = await listEntriesByChip(this.chip);
    this.total = await countEntries();
  }

  private async pickChip(chip: string): Promise<void> {
    this.chip = chip;
    await this.load();
  }

  private async star(item: EntryRow): Promise<void> {
    await toggleFavorite(item.id, item.favorite === 0);
    bumpRevision();
    await this.load();
  }

  build() {
    Column() {
      PageHead({ eyebrow: 'Memory', title: '语录', meta: `${this.total} 句 · 已记` })

      Scroll() {
        Row() {
          ForEach(ENTRY_CHIPS, (chip: string) => {
            Text(chip)
              .fontSize(11.5)
              .fontColor(this.chip === chip ? C.paper : C.ink2)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(S.pill)
              .border({ width: 1, color: this.chip === chip ? C.ink : C.rule })
              .backgroundColor(this.chip === chip ? C.ink : C.paper)
              .margin({ right: 8 })
              .onClick(() => this.pickChip(chip))
          }, (chip: string) => chip)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ bottom: 18 })

      Scroll() {
        Column() {
          if (this.entries.length === 0) {
            EmptyState({
              mark: '“',
              text: '这个分类下还没有句子。\n遇到打动你的话，就记下来吧。',
              action: '记一句',
              sheet: 'quote'
            })
          } else {
            ForEach(this.entries, (item: EntryRow) => {
              if (item.type === EntryType.Snippet) {
                this.snippetCard(item)
              } else {
                this.quoteCard(item)
              }
            }, (item: EntryRow) => item.id)
          }

          Button('＋　记下一句话 / 粘贴一条剪藏')
            .fontSize(12)
            .fontColor(C.ink3)
            .backgroundColor(C.paper)
            .border({ width: 1, color: C.rule, style: BorderStyle.Dashed })
            .borderRadius(14)
            .width('100%')
            .padding({ top: 14, bottom: 14 })
            .margin({ top: 6 })
            .onClick(() => openSheet('quote'))
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
  quoteCard(item: EntryRow) {
    Column() {
      Text('“')
        .fontFamily(SERIF)
        .fontSize(30)
        .fontColor(C.cinnabar)
        .opacity(0.5)
        .height(30)
        .alignSelf(ItemAlign.Start)

      Text(item.content)
        .fontFamily(SERIF)
        .fontSize(16.5)
        .lineHeight(32)
        .fontColor(C.ink)
        .textAlign(TextAlign.JUSTIFY)
        .margin({ top: 2 })

      Row() {
        Text(item.source ? item.source : displayTags(item.tags))
          .fontSize(11)
          .fontColor(C.ink3)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(item.favorite === 1 ? '★' : '☆')
            .fontSize(12)
            .fontColor(item.favorite === 1 ? C.cinnabar : C.ink3)
          Text('收藏')
            .fontSize(10.5)
            .fontColor(item.favorite === 1 ? C.cinnabar : C.ink3)
            .margin({ left: 4 })
        }
        .onClick(() => this.star(item))
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding({ top: 20, bottom: 22 })
    .border({ width: { top: 1 }, color: C.rule })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => openQuote(item.id))
  }

  @Builder
  snippetCard(item: EntryRow) {
    Column() {
      Row() {
        Text('剪藏')
          .fontSize(9.5)
          .fontColor(C.ink2)
          .border({ width: 1, color: C.rule })
          .borderRadius(3)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        Text(formatDotDate(item.createdAt))
          .fontSize(9.5)
          .fontColor(C.ink3)
          .margin({ left: 8 })
      }
      .width('100%')

      Text(item.source ? item.source : '网页剪藏')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(C.ink)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 10 })

      Text(item.content)
        .fontSize(12)
        .lineHeight(23)
        .fontColor(C.ink2)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      if (item.url !== null) {
        Text('阅读原文 →')
          .fontSize(10)
          .fontColor(C.cinnabar)
          .margin({ top: 11 })
      }
    }
    .width('100%')
    .padding({ top: 18, bottom: 20 })
    .border({ width: { top: 1 }, color: C.rule })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => openQuote(item.id))
  }
}
