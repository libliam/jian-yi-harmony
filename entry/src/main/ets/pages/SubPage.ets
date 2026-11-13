/**
 * 简忆 · 二级页面（习惯 / 心情 / 摘录详情 / 阅读）
 *
 * 独立的 @Entry 页面，进入 router 系统页面栈：系统返回键与侧滑返回由系统逐层 pop 回主页面。
 * 录入弹层 uiSheet 是全局状态，所以这一层也渲染一份 QuickSheet，
 * 保证在二级页点「新增习惯 / 记心情 / 记一条」时弹层照样能看到。
 */

import { C } from '../common/Theme';
import { attachUiContext, closeSheet } from '../common/Bus';
import { SubPages } from '../view/SubPages';
import { QuickSheet } from '../view/QuickSheet';

@Entry
@Component
struct SubPage {
  @StorageLink('uiSheet') sheetType: string = '';

  onPageShow(): void {
    attachUiContext(this.getUIContext());
  }

  /** 弹层优先于页面出栈：先关弹层，再按一次才由系统返回主页面 */
  onBackPress(): boolean {
    if (this.sheetType.length > 0) {
      closeSheet();
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      SubPages()
      if (this.sheetType.length > 0) {
        QuickSheet()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.paper)
  }
}
