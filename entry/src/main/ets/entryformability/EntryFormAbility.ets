/**
 * 简忆 · 桌面卡片数据提供方（FormExtensionAbility）
 *
 * 卡片 UI 是独立编译单元，不能 import 业务模块，数据只能靠 formBindingData 注入。
 * onAddForm 必须同步返回，所以先给占位、再异步查库后 formProvider.updateForm 刷新。
 * 卡片进程与主进程是两套模块实例，这里要自己 initDb(this.context)。
 *
 * 点击卡片走 FormLink(router) + params.sheet，复用 NotifyLaunch 的通知直达链路。
 */

import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { initDb } from '../db/JianYiDb';
import { countTodos, todayBrief } from '../db/TodoRepo';
import { TodoBucket } from '../db/Models';

interface CardData {
  heading: string;
  line1: string;
  line2: string;
  line3: string;
  undone: string;
}

const PLACEHOLDER: CardData = {
  heading: '简忆 · 今日',
  line1: '正在整理今天的事…',
  line2: '',
  line3: '',
  undone: ''
};

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const params: Record<string, Object> | undefined = want.parameters;
    let formId: string = '';
    if (params !== undefined) {
      const raw: Object | undefined = params[formInfo.FormParam.IDENTITY_KEY];
      if (raw !== undefined) {
        formId = String(raw);
      }
    }
    this.refresh(formId);
    return formBindingData.createFormBindingData(PLACEHOLDER);
  }

  /** 系统定时刷新（form_config updateDuration）触发 */
  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  /** 异步查库后推送给卡片；查库失败就保留占位，不刷新 */
  private refresh(formId: string): void {
    if (formId.length === 0) {
      return;
    }
    this.load().then((data: CardData): void => {
      formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
        .catch((err: BusinessError): void => {
          // 卡片可能已被移除，忽略更新失败
        });
    }).catch((): void => {
      // 数据库还没就绪时保留占位，下次定时刷新会重试
    });
  }

  private async load(): Promise<CardData> {
    await initDb(this.context);
    const stat = await countTodos(TodoBucket.Today);
    const brief = await todayBrief(3);
    const undone: number = stat.total - stat.done;
    return {
      heading: '简忆 · 今日',
      line1: brief.length > 0 ? brief[0].title : '',
      line2: brief.length > 1 ? brief[1].title : '',
      line3: brief.length > 2 ? brief[2].title : '',
      undone: undone > 0 ? `还有 ${undone} 件事` : '今天都清完了'
    };
  }
}
