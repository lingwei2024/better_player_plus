/**
 * 缓存数据源工厂
 * 管理带缓存的数据源创建
 */
import http from '@ohos.net.http';
import { Context } from '@ohos.abilityAccessCtrl';
import { BetterPlayerCache } from './BetterPlayerCache';
import { DataSourceUtils } from './DataSourceUtils';
import hilog from '@ohos.hilog';

const TAG = 'CacheDataSourceFactory';
const DOMAIN = 0x0001;

/**
 * 数据源配置
 */
export interface DataSourceConfig {
  url: string;
  headers?: Map<string, string>;
  useCache: boolean;
  maxCacheSize: number;
  maxFileSize: number;
  cacheKey?: string;
}

/**
 * 缓存数据源
 */
export class CacheDataSource {
  private context: Context;
  private config: DataSourceConfig;
  private cache: BetterPlayerCache | null = null;
  private httpRequest: http.HttpRequest | null = null;

  constructor(context: Context, config: DataSourceConfig) {
    this.context = context;
    this.config = config;

    if (config.useCache) {
      this.cache = BetterPlayerCache.createCache(context, config.maxCacheSize);
    }
  }

  /**
   * 读取数据
   */
  async read(offset: number = 0, length: number = -1): Promise<ArrayBuffer | null> {
    try {
      // 生成缓存键
      const cacheKey = this.getCacheKey();

      // 检查缓存
      if (this.cache && this.cache.hasCache(cacheKey)) {
        hilog.info(DOMAIN, TAG, `Reading from cache: ${cacheKey}`);
        return this.cache.getCache(cacheKey);
      }

      // 从网络读取
      hilog.info(DOMAIN, TAG, `Reading from network: ${this.config.url}`);
      const data = await this.readFromNetwork(offset, length);

      // 写入缓存
      if (data && this.cache && data.byteLength <= this.config.maxFileSize) {
        this.cache.addCache(cacheKey, data);
      }

      return data;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Read data failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 从网络读取数据
   */
  private async readFromNetwork(offset: number, length: number): Promise<ArrayBuffer | null> {
    try {
      this.httpRequest = http.createHttp();
      const options = DataSourceUtils.buildHttpRequestOptions(
        http.RequestMethod.GET,
        this.config.headers
      );

      // 添加Range请求头支持断点续传
      if (offset > 0 || length > 0) {
        const rangeHeader = this.buildRangeHeader(offset, length);
        if (!options.header) {
          options.header = {};
        }
        options.header['Range'] = rangeHeader;
      }

      const response = await this.httpRequest.request(this.config.url, options);

      if (response.responseCode === 200 || response.responseCode === 206) {
        return response.result as ArrayBuffer;
      } else {
        hilog.error(DOMAIN, TAG, `HTTP request failed with code: ${response.responseCode}`);
        return null;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Read from network failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 构建Range请求头
   */
  private buildRangeHeader(offset: number, length: number): string {
    if (length > 0) {
      return `bytes=${offset}-${offset + length - 1}`;
    } else {
      return `bytes=${offset}-`;
    }
  }

  /**
   * 获取缓存键
   */
  private getCacheKey(): string {
    if (this.config.cacheKey) {
      return this.config.cacheKey;
    }
    return this.generateCacheKey(this.config.url);
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(url: string): string {
    // 使用URL的hash作为缓存键
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      const char = url.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return Math.abs(hash).toString();
  }

  /**
   * 获取内容长度
   */
  async getContentLength(): Promise<number> {
    return await DataSourceUtils.getContentLength(this.config.url, this.config.headers);
  }

  /**
   * 关闭数据源
   */
  close(): void {
    if (this.httpRequest) {
      this.httpRequest.destroy();
      this.httpRequest = null;
    }
  }
}

/**
 * 缓存数据源工厂
 */
export class CacheDataSourceFactory {
  private context: Context;
  private maxCacheSize: number;
  private maxFileSize: number;

  constructor(context: Context, maxCacheSize: number, maxFileSize: number) {
    this.context = context;
    this.maxCacheSize = maxCacheSize;
    this.maxFileSize = maxFileSize;
  }

  /**
   * 创建数据源
   */
  createDataSource(
    url: string,
    headers?: Map<string, string>,
    useCache: boolean = true,
    cacheKey?: string
  ): CacheDataSource {
    const config: DataSourceConfig = {
      url: url,
      headers: headers,
      useCache: useCache,
      maxCacheSize: this.maxCacheSize,
      maxFileSize: this.maxFileSize,
      cacheKey: cacheKey
    };

    return new CacheDataSource(this.context, config);
  }

  /**
   * 获取缓存大小
   */
  getCacheSize(): number {
    const cache = BetterPlayerCache.createCache(this.context, this.maxCacheSize);
    return cache ? cache.getCacheSize() : 0;
  }

  /**
   * 清空缓存
   */
  clearCache(): void {
    const cache = BetterPlayerCache.createCache(this.context, this.maxCacheSize);
    if (cache) {
      cache.clearAll();
    }
  }
}

/**
 * 预加载任务配置
 */
export interface PreloadConfig {
  url: string;
  headers?: Map<string, string>;
  preCacheSize: number;
  maxCacheSize: number;
  maxCacheFileSize: number;
  cacheKey?: string;
}

/**
 * 预加载管理器
 */
export class PreloadManager {
  private context: Context;
  private activePreloads: Map<string, PreloadTask> = new Map();

  constructor(context: Context) {
    this.context = context;
  }

  /**
   * 开始预加载
   */
  async startPreload(config: PreloadConfig): Promise<boolean> {
    try {
      // 检查是否已经在预加载
      if (this.activePreloads.has(config.url)) {
        hilog.warn(DOMAIN, TAG, `Preload already in progress: ${config.url}`);
        return false;
      }

      const task = new PreloadTask(this.context, config);
      this.activePreloads.set(config.url, task);

      const result = await task.start();

      // 完成后移除任务
      this.activePreloads.delete(config.url);

      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Start preload failed: ${JSON.stringify(err)}`);
      this.activePreloads.delete(config.url);
      return false;
    }
  }

  /**
   * 停止预加载
   */
  stopPreload(url: string): void {
    const task = this.activePreloads.get(url);
    if (task) {
      task.cancel();
      this.activePreloads.delete(url);
      hilog.info(DOMAIN, TAG, `Preload cancelled: ${url}`);
    }
  }

  /**
   * 停止所有预加载
   */
  stopAllPreloads(): void {
    this.activePreloads.forEach((task: PreloadTask, url: string) => {
      task.cancel();
    });
    this.activePreloads.clear();
    hilog.info(DOMAIN, TAG, 'All preloads cancelled');
  }
}

/**
 * 预加载任务
 */
class PreloadTask {
  private context: Context;
  private config: PreloadConfig;
  private cancelled: boolean = false;
  private dataSource: CacheDataSource | null = null;

  constructor(context: Context, config: PreloadConfig) {
    this.context = context;
    this.config = config;
  }

  /**
   * 开始预加载
   */
  async start(): Promise<boolean> {
    try {
      const factory = new CacheDataSourceFactory(
        this.context,
        this.config.maxCacheSize,
        this.config.maxCacheFileSize
      );

      this.dataSource = factory.createDataSource(
        this.config.url,
        this.config.headers,
        true,
        this.config.cacheKey
      );

      // 读取指定大小的数据进行预缓存
      const data = await this.dataSource.read(0, this.config.preCacheSize);

      if (this.cancelled) {
        hilog.info(DOMAIN, TAG, 'Preload was cancelled');
        return false;
      }

      if (data) {
        hilog.info(DOMAIN, TAG, `Preload completed: ${this.config.url}, size: ${data.byteLength}`);
        return true;
      } else {
        hilog.error(DOMAIN, TAG, `Preload failed: ${this.config.url}`);
        return false;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Preload task failed: ${JSON.stringify(err)}`);
      return false;
    } finally {
      if (this.dataSource) {
        this.dataSource.close();
      }
    }
  }

  /**
   * 取消预加载
   */
  cancel(): void {
    this.cancelled = true;
    if (this.dataSource) {
      this.dataSource.close();
    }
  }
}
