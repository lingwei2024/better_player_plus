/**
 * BetterPlayer 缓存管理
 * 使用鸿蒙系统的缓存机制管理视频缓存
 */
import fileIo from '@ohos.file.fs';
import { Context } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';
import hilog from '@ohos.hilog';

const TAG = 'BetterPlayerCache';
const DOMAIN = 0x0001;

export class CacheConfig {
  cacheFileSize: number = 100 * 1024 * 1024; // 默认100MB
  cacheDirName: string = 'betterPlayerCache';
}

export class BetterPlayerCache {
  private static instance: BetterPlayerCache | null = null;
  private cacheDir: string = '';
  private cacheSize: number = 0;
  private maxCacheSize: number = 0;
  private cacheMap: Map<string, CacheEntry> = new Map();

  private constructor() {}

  /**
   * 创建或获取缓存实例
   */
  static createCache(context: Context, cacheFileSize: number): BetterPlayerCache | null {
    if (BetterPlayerCache.instance === null) {
      BetterPlayerCache.instance = new BetterPlayerCache();
      BetterPlayerCache.instance.initialize(context, cacheFileSize);
    }
    return BetterPlayerCache.instance;
  }

  /**
   * 初始化缓存目录
   */
  private initialize(context: Context, cacheFileSize: number): void {
    try {
      // 获取应用缓存目录
      this.cacheDir = context.cacheDir + '/betterPlayerCache';
      this.maxCacheSize = cacheFileSize;

      // 创建缓存目录
      if (!fileIo.accessSync(this.cacheDir)) {
        fileIo.mkdirSync(this.cacheDir);
        hilog.info(DOMAIN, TAG, 'Cache directory created: ' + this.cacheDir);
      }

      // 加载已有缓存信息
      this.loadCacheInfo();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Initialize cache failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 加载缓存信息
   */
  private loadCacheInfo(): void {
    try {
      if (!fileIo.accessSync(this.cacheDir)) {
        return;
      }

      const files = fileIo.listFileSync(this.cacheDir);
      this.cacheSize = 0;

      files.forEach((fileName: string) => {
        const filePath = `${this.cacheDir}/${fileName}`;
        const stat = fileIo.statSync(filePath);
        
        const entry: CacheEntry = {
          path: filePath,
          size: stat.size,
          lastAccessTime: stat.mtime,
          key: fileName
        };

        this.cacheMap.set(fileName, entry);
        this.cacheSize += stat.size;
      });

      hilog.info(DOMAIN, TAG, `Loaded cache info: ${this.cacheMap.size} files, total size: ${this.cacheSize}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Load cache info failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 添加缓存
   */
  addCache(key: string, data: ArrayBuffer): boolean {
    try {
      // 检查缓存空间
      if (this.cacheSize + data.byteLength > this.maxCacheSize) {
        this.evictCache(data.byteLength);
      }

      const filePath = `${this.cacheDir}/${this.sanitizeKey(key)}`;
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, data);
      fileIo.closeSync(file);

      const stat = fileIo.statSync(filePath);
      const entry: CacheEntry = {
        path: filePath,
        size: stat.size,
        lastAccessTime: Date.now(),
        key: key
      };

      this.cacheMap.set(key, entry);
      this.cacheSize += stat.size;

      hilog.info(DOMAIN, TAG, `Cache added: ${key}, size: ${stat.size}`);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Add cache failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 获取缓存
   */
  getCache(key: string): ArrayBuffer | null {
    try {
      const entry = this.cacheMap.get(key);
      if (!entry || !fileIo.accessSync(entry.path)) {
        return null;
      }

      // 更新访问时间
      entry.lastAccessTime = Date.now();

      const file = fileIo.openSync(entry.path, fileIo.OpenMode.READ_ONLY);
      const arrayBuffer = new ArrayBuffer(entry.size);
      fileIo.readSync(file.fd, arrayBuffer);
      fileIo.closeSync(file);

      hilog.info(DOMAIN, TAG, `Cache hit: ${key}`);
      return arrayBuffer;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Get cache failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 检查缓存是否存在
   */
  hasCache(key: string): boolean {
    const entry = this.cacheMap.get(key);
    return entry !== undefined && fileIo.accessSync(entry.path);
  }

  /**
   * 清理缓存以释放空间（LRU策略）
   */
  private evictCache(requiredSize: number): void {
    // 按最后访问时间排序
    const entries = Array.from(this.cacheMap.values());
    entries.sort((a, b) => a.lastAccessTime - b.lastAccessTime);

    let freedSize = 0;
    for (const entry of entries) {
      if (this.cacheSize - freedSize + requiredSize <= this.maxCacheSize) {
        break;
      }

      try {
        fileIo.unlinkSync(entry.path);
        this.cacheMap.delete(entry.key);
        freedSize += entry.size;
        hilog.info(DOMAIN, TAG, `Evicted cache: ${entry.key}, size: ${entry.size}`);
      } catch (err) {
        hilog.error(DOMAIN, TAG, `Evict cache failed: ${JSON.stringify(err)}`);
      }
    }

    this.cacheSize -= freedSize;
  }

  /**
   * 清空所有缓存
   */
  clearAll(): void {
    try {
      const files = fileIo.listFileSync(this.cacheDir);
      files.forEach((fileName: string) => {
        const filePath = `${this.cacheDir}/${fileName}`;
        fileIo.unlinkSync(filePath);
      });

      this.cacheMap.clear();
      this.cacheSize = 0;
      hilog.info(DOMAIN, TAG, 'All cache cleared');
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Clear all cache failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 释放缓存资源
   */
  static releaseCache(): void {
    try {
      if (BetterPlayerCache.instance !== null) {
        BetterPlayerCache.instance.clearAll();
        BetterPlayerCache.instance = null;
        hilog.info(DOMAIN, TAG, 'Cache released');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Release cache failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 清理文件名中的非法字符
   */
  private sanitizeKey(key: string): string {
    return key.replace(/[^a-zA-Z0-9_-]/g, '_');
  }

  /**
   * 获取缓存大小
   */
  getCacheSize(): number {
    return this.cacheSize;
  }

  /**
   * 获取缓存目录
   */
  getCacheDir(): string {
    return this.cacheDir;
  }
}

/**
 * 缓存条目
 */
interface CacheEntry {
  path: string;
  size: number;
  lastAccessTime: number;
  key: string;
}
