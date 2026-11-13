/**
 * 简忆 · 全局搜索页
 *
 * 独立的 @Entry 页面，进入 router 系统页面栈。
 * 点搜索结果会 closeSearch() 回主页面并切到对应 tab，按系统返回键同样回到主页面。
 */

import { C } from '../common/Theme';
import { attachUiContext } from '../common/Bus';
import { SearchPanel } from '../view/SearchPanel';

@Entry
@Component
struct SearchPage {
  onPageShow(): void {
    attachUiContext(this.getUIContext());
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      SearchPanel()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(C.paper)
  }
}
