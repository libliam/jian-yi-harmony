/**
 * 简忆 · 微光回顾页
 *
 * 独立的 @Entry 页面，压入 router 系统页面栈：系统返回键 / 侧滑返回逐层 pop 回主页。
 * 录入弹层 uiSheet 是全局状态，所以这一层也渲染一份 QuickSheet，
 * 在回顾页点「＋ 记一点」时弹层照样能看到；弹层优先于页面出栈。
 */

import { C } from '../common/Theme';
import { attachUiContext, closeSheet } from '../common/Bus';
import { GrowthView } from '../view/GrowthView';
import { QuickSheet } from '../view/QuickSheet';

@Entry
@Component
struct GrowthPage {
  @StorageLink('uiSheet') sheetType: string = '';

  onPageShow(): void {
    attachUiContext(this.getUIContext());
  }

  onBackPress(): boolean {
    if (this.sheetType.length > 0) {
      closeSheet();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      GrowthView()
      if (this.sheetType.length > 0) {
        QuickSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.paper)
  }
}
