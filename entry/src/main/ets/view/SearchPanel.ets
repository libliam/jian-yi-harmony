/**
 * 全局搜索 · 路线图第 3 步
 *
 * 一次搜全部：语录 / 剪藏 / 待办 / 待思 / 书架。
 * 聚合在 SearchRepo，这里只负责输入、分组、高亮和点击跳转。
 */

import { searchAll, SEARCH_GROUPS, SearchHit, emptySearchTip } from '../db/SearchRepo';
import { closeSearch, switchTab, setTodoPane, openSheet } from '../common/Bus';
import { C, S } from '../common/Theme';

const RECENT: string[] = ['梭罗', '评审', '双链', '瓦尔登湖'];

@Component
export struct SearchPanel {
  @State keyword: string = '';
  @State hits: SearchHit[] = [];

  private async runSearch(q: string): Promise<void> {
    this.hits = await searchAll(q);
  }

  private groupHits(group: string): SearchHit[] {
    return this.hits.filter((h: SearchHit): boolean => h.group === group);
  }

  private pick(hit: SearchHit): void {
    closeSearch();
    switchTab(hit.tab);
    if (hit.pane.length > 0) {
      setTodoPane(hit.pane);
    }
  }

  private clear(): void {
    this.keyword = '';
    this.hits = [];
  }

  build() {
    Column() {
      // 输入行
      Row() {
        Row() {
          Text('搜')
            .fontSize(12)
            .fontColor(C.ink3)
            .margin({ right: 9 })
          TextInput({ placeholder: '搜索 语录 · 待办 · 想法 · 书', text: this.keyword })
            .layoutWeight(1)
            .fontSize(13.5)
            .fontColor(C.ink)
            .backgroundColor(C.paper2)
            .onChange((value: string) => {
              this.keyword = value;
              this.runSearch(value);
            })
          if (this.keyword.length > 0) {
            Text('×')
              .fontSize(16)
              .fontColor(C.ink3)
              .padding({ left: 6, right: 2 })
              .onClick(() => this.clear())
          }
        }
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 9, bottom: 9 })
        .borderRadius(S.smallRadius)
        .backgroundColor(C.paper2)

        Text('取消')
          .fontSize(12.5)
          .fontColor(C.ink2)
          .margin({ left: 12 })
          .onClick(() => {
            this.clear();
            closeSearch();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      Scroll() {
        Column() {
          if (this.keyword.trim().length === 0) {
            Text('最近')
              .fontSize(10)
              .fontColor(C.ink3)
              .letterSpacing(2)
              .margin({ top: 18, bottom: 10 })
              .alignSelf(ItemAlign.Start)

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(RECENT, (word: string) => {
                Text(word)
                  .fontSize(11.5)
                  .fontColor(C.ink2)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(S.pill)
                  .border({ width: 1, color: C.rule })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.keyword = word;
                    this.runSearch(word);
                  })
              }, (word: string) => word)
            }
            .width('100%')

            Text('一次搜全部：语录、剪藏、待办、待思、书架。\n不用记分类，想到什么词就搜什么词。')
              .fontSize(10.5)
              .lineHeight(21)
              .fontColor(C.ink3)
              .margin({ top: 26, bottom: 26 })
              .padding({ top: 18 })
              .border({ width: { top: 1 }, color: C.rule })
              .width('100%')
          } else if (this.hits.length === 0) {
            Column() {
              Text('?')
                .fontFamily('serif')
                .fontSize(32)
                .fontColor(C.ink3)
                .opacity(0.5)
              Text(emptySearchTip(this.keyword.trim()))
                .fontSize(11.5)
                .lineHeight(22)
                .fontColor(C.ink3)
                .textAlign(TextAlign.Center)
                .margin({ top: 14 })
              Button('记一条新的')
                .fontSize(11)
                .fontColor(C.ink2)
                .backgroundColor(C.paper)
                .border({ width: 1, color: C.rule })
                .borderRadius(S.pill)
                .padding({ left: 18, right: 18, top: 9, bottom: 9 })
                .margin({ top: 18 })
                .onClick(() => {
                  closeSearch();
                  openSheet('quote');
                })
            }
            .width('100%')
            .padding({ top: 40 })
          } else {
            Text(`找到 ${this.hits.length} 条`)
              .fontSize(10.5)
              .fontColor(C.ink3)
              .padding({ top: 14, bottom: 2 })
              .alignSelf(ItemAlign.Start)

            ForEach(SEARCH_GROUPS, (group: string) => {
              if (this.groupHits(group).length > 0) {
                Row() {
                  Text(group)
                    .fontSize(10)
                    .fontColor(C.ink3)
                    .letterSpacing(2)
                  Row()
                    .height(1)
                    .backgroundColor(C.rule)
                    .layoutWeight(1)
                    .margin({ left: 8 })
                }
                .width('100%')
                .margin({ top: 20, bottom: 4 })

                ForEach(this.groupHits(group), (hit: SearchHit) => {
                  Column() {
                    this.highlighted(hit.title, this.keyword.trim())
                    if (hit.sub.length > 0) {
                      Text(hit.sub)
                        .fontSize(10)
                        .fontColor(C.ink3)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 5 })
                    }
                  }
                  .width('100%')
                  .padding({ top: 13, bottom: 13 })
                  .border({ width: { bottom: 1 }, color: C.rule })
                  .alignItems(HorizontalAlign.Start)
                  .onClick(() => this.pick(hit))
                }, (hit: SearchHit) => hit.group + hit.id)
              }
            }, (group: string) => group)
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 60 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.paper)
    .zIndex(30)
  }

  private hlPrefix(text: string, q: string): string {
    return text.substring(0, this.hitIndex(text, q));
  }

  private hlMatch(text: string, q: string): string {
    const i: number = this.hitIndex(text, q);
    return text.substring(i, i + q.length);
  }

  private hlSuffix(text: string, q: string): string {
    return text.substring(this.hitIndex(text, q) + q.length);
  }

  @Builder
  highlighted(text: string, q: string) {
    if (this.hitIndex(text, q) < 0) {
      // 命中发生在副标题而不是正文时不硬凑高亮
      Text(text)
        .fontFamily('serif')
        .fontSize(13.5)
        .lineHeight(22)
        .fontColor(C.ink)
    } else {
      Text() {
        Span(this.hlPrefix(text, q))
        Span(this.hlMatch(text, q))
          .fontColor(C.cinnabar)
          .fontWeight(FontWeight.Bold)
        Span(this.hlSuffix(text, q))
      }
      .fontFamily('serif')
      .fontSize(13.5)
      .lineHeight(22)
      .fontColor(C.ink)
    }
  }

  private hitIndex(text: string, q: string): number {
    return text.toLowerCase().indexOf(q.toLowerCase());
  }
}
