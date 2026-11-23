/**
 * 简忆 · 电子书导入与解析
 *
 * 系统文件选择器选本地书 → 复制到应用沙箱 files/books/ → bookParser 解析书名/作者/章节 → 入库。
 * 仓库层不碰文件系统（项目规则 4），文件操作集中在这里，业务模块可用 @kit.ReaderKit / @kit.CoreFileKit。
 *
 * bookParser.getDefaultHandler 需要真实沙箱路径（不是 file:// URI），所以必须先复制。
 * 支持格式以 Reader Kit 为准（epub / txt 等），这里用 fileSuffixFilters 限定常见电子书后缀。
 */

import { picker, fileIo } from '@kit.CoreFileKit';
import { bookParser } from '@kit.ReaderKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { addBook, listBooks } from '../db/BookRepo';
import { BookRow } from '../db/Models';

const BOOKS_DIR: string = 'books';
const SUFFIXES: string[] = ['.epub', '.txt', '.pdf', '.mobi'];

export interface ImportResult {
  bookId: string;
  title: string;
  author: string | null;
  chapters: number;
}

/**
 * 选一本本地书并入库。返回 null 表示用户取消或解析失败。
 * context 用 UIAbilityContext.filesDir 定位沙箱目录。
 */
export async function importLocalBook(context: common.UIAbilityContext): Promise<ImportResult | null> {
  const options: picker.DocumentSelectOptions = {
    fileSuffixFilters: SUFFIXES,
    maxSelectNumber: 1
  };
  let uris: string[];
  try {
    const viewPicker = new picker.DocumentViewPicker(context);
    uris = await viewPicker.select(options);
  } catch (err) {
    return null; // 用户取消
  }
  if (uris.length === 0) {
    return null;
  }

  const uri: string = uris[0];
  const dir: string = `${context.filesDir}/${BOOKS_DIR}`;
  try {
    fileIo.mkdirSync(dir, true);
  } catch (err) {
    // 目录已存在，忽略
  }

  // 目标文件名：时间戳 + 原后缀，避免重名覆盖
  const suffix: string = extractSuffix(uri);
  const dest: string = `${dir}/book_${Date.now()}${suffix}`;
  let srcFile: fileIo.File | null = null;
  try {
    srcFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    fileIo.copyFileSync(srcFile.fd, dest);
  } catch (err) {
    if (srcFile !== null) {
      fileIo.closeSync(srcFile);
    }
    return null;
  }
  fileIo.closeSync(srcFile);

  // 用沙箱路径解析元信息
  try {
    const handler: bookParser.BookParserHandler = await bookParser.getDefaultHandler(dest);
    const info: bookParser.BookInfo = handler.getBookInfo();
    const spines: bookParser.SpineItem[] = handler.getSpineList();
    const title: string = info.bookTitle.length > 0 ? info.bookTitle : stripSuffix(uri);
    const author: string | null = info.bookCreator !== undefined && info.bookCreator.length > 0
      ? info.bookCreator : null;
    const format: string = suffix.replace('.', '').toUpperCase();
    const id: string = await addBook(title, author, dest, format, null, spines.length);
    return { bookId: id, title: title, author: author, chapters: spines.length };
  } catch (err) {
    // 解析失败：文件已复制进沙箱，但没入库，留着无害（下次导入会用新时间戳）
    return null;
  }
}

/** 获取某本书的解析器（阅读页用）；路径取不到返回 null */
export async function handlerFor(book: BookRow): Promise<bookParser.BookParserHandler | null> {
  if (book.filePath === null || book.filePath.length === 0) {
    return null;
  }
  try {
    return await bookParser.getDefaultHandler(book.filePath);
  } catch (err) {
    const e: BusinessError = err as BusinessError;
    return null;
  }
}

function extractSuffix(uri: string): string {
  const clean: string = uri.split('?')[0];
  const dot: number = clean.lastIndexOf('.');
  return dot >= 0 ? clean.substring(dot).toLowerCase() : '.epub';
}

function stripSuffix(uri: string): string {
  const clean: string = uri.split('?')[0];
  const slash: number = clean.lastIndexOf('/');
  const name: string = slash >= 0 ? clean.substring(slash + 1) : clean;
  const dot: number = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
