/**
 * 图片处理工作类
 * 用于异步下载和处理图片
 */
import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import fileIo from '@ohos.file.fs';
import { Context } from '@ohos.abilityAccessCtrl';
import { DataSourceUtils } from './DataSourceUtils';
import hilog from '@ohos.hilog';

const TAG = 'ImageWorker';
const DOMAIN = 0x0001;
const IMAGE_EXTENSION = '.png';
const DEFAULT_NOTIFICATION_IMAGE_SIZE_PX = 256;

/**
 * 图片处理配置
 */
export interface ImageProcessConfig {
  url: string;
  headers?: Map<string, string>;
  maxWidth?: number;
  maxHeight?: number;
  quality?: number;
  format?: string;
}

/**
 * 图片处理结果
 */
export interface ImageProcessResult {
  success: boolean;
  filePath?: string;
  error?: string;
}

/**
 * 图片工作器
 */
export class ImageWorker {
  private context: Context;
  private cacheDir: string;

  constructor(context: Context) {
    this.context = context;
    this.cacheDir = context.cacheDir;
  }

  /**
   * 处理图片
   */
  async processImage(config: ImageProcessConfig): Promise<ImageProcessResult> {
    try {
      hilog.info(DOMAIN, TAG, `Processing image: ${config.url}`);

      // 下载或读取图片
      let pixelMap: image.PixelMap | null = null;
      
      if (DataSourceUtils.isHTTP(config.url)) {
        pixelMap = await this.downloadAndDecodeImage(config.url, config.headers);
      } else {
        pixelMap = await this.loadLocalImage(config.url);
      }

      if (!pixelMap) {
        return {
          success: false,
          error: 'Failed to load image'
        };
      }

      // 调整图片大小
      const resizedPixelMap = await this.resizeImage(
        pixelMap,
        config.maxWidth || DEFAULT_NOTIFICATION_IMAGE_SIZE_PX,
        config.maxHeight || DEFAULT_NOTIFICATION_IMAGE_SIZE_PX
      );

      // 保存图片
      const fileName = this.generateFileName(config.url);
      const filePath = `${this.cacheDir}/${fileName}`;
      const saved = await this.saveImage(resizedPixelMap, filePath, config.quality || 100);

      // 释放资源
      pixelMap.release();
      resizedPixelMap.release();

      if (saved) {
        hilog.info(DOMAIN, TAG, `Image processed successfully: ${filePath}`);
        return {
          success: true,
          filePath: filePath
        };
      } else {
        return {
          success: false,
          error: 'Failed to save image'
        };
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Process image failed: ${JSON.stringify(err)}`);
      return {
        success: false,
        error: `Process failed: ${err}`
      };
    }
  }

  /**
   * 从网络下载并解码图片
   */
  private async downloadAndDecodeImage(
    url: string,
    headers?: Map<string, string>
  ): Promise<image.PixelMap | null> {
    try {
      // 下载图片数据
      const httpRequest = http.createHttp();
      const options = DataSourceUtils.buildHttpRequestOptions(
        http.RequestMethod.GET,
        headers
      );

      const response = await httpRequest.request(url, options);
      httpRequest.destroy();

      if (response.responseCode !== 200) {
        hilog.error(DOMAIN, TAG, `Download failed with code: ${response.responseCode}`);
        return null;
      }

      const arrayBuffer = response.result as ArrayBuffer;
      
      // 创建图片源
      const imageSource = image.createImageSource(arrayBuffer);
      
      // 解码图片
      const pixelMap = await imageSource.createPixelMap();
      
      // 释放图片源
      await imageSource.release();

      return pixelMap;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Download and decode image failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 加载本地图片
   */
  private async loadLocalImage(path: string): Promise<image.PixelMap | null> {
    try {
      // 读取文件
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(path);
      const arrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, arrayBuffer);
      fileIo.closeSync(file);

      // 创建图片源
      const imageSource = image.createImageSource(arrayBuffer);
      
      // 解码图片
      const pixelMap = await imageSource.createPixelMap();
      
      // 释放图片源
      await imageSource.release();

      return pixelMap;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Load local image failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 调整图片大小
   */
  private async resizeImage(
    pixelMap: image.PixelMap,
    maxWidth: number,
    maxHeight: number
  ): Promise<image.PixelMap> {
    try {
      const imageInfo = await pixelMap.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;

      // 计算缩放比例
      const scale = this.calculateScale(width, height, maxWidth, maxHeight);

      if (scale >= 1.0) {
        // 不需要缩放
        return pixelMap;
      }

      // 计算新尺寸
      const newWidth = Math.floor(width * scale);
      const newHeight = Math.floor(height * scale);

      // 缩放图片
      await pixelMap.scale(scale, scale);

      hilog.info(DOMAIN, TAG, `Image resized from ${width}x${height} to ${newWidth}x${newHeight}`);
      return pixelMap;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Resize image failed: ${JSON.stringify(err)}`);
      return pixelMap;
    }
  }

  /**
   * 计算缩放比例
   */
  private calculateScale(
    width: number,
    height: number,
    maxWidth: number,
    maxHeight: number
  ): number {
    if (width <= maxWidth && height <= maxHeight) {
      return 1.0;
    }

    const widthScale = maxWidth / width;
    const heightScale = maxHeight / height;

    return Math.min(widthScale, heightScale);
  }

  /**
   * 保存图片
   */
  private async saveImage(
    pixelMap: image.PixelMap,
    filePath: string,
    quality: number
  ): Promise<boolean> {
    try {
      // 创建图片打包器
      const imagePacker = image.createImagePacker();

      // 设置打包选项
      const packOpts: image.PackingOption = {
        format: 'image/png',
        quality: quality
      };

      // 打包图片
      const arrayBuffer = await imagePacker.packing(pixelMap, packOpts);

      // 释放打包器
      await imagePacker.release();

      // 保存文件
      const file = fileIo.openSync(filePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, arrayBuffer);
      fileIo.closeSync(file);

      hilog.info(DOMAIN, TAG, `Image saved: ${filePath}`);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Save image failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 生成文件名
   */
  private generateFileName(url: string): string {
    // 使用URL的hash作为文件名
    const hash = this.hashCode(url);
    return `${Math.abs(hash)}${IMAGE_EXTENSION}`;
  }

  /**
   * 计算字符串的hash值
   */
  private hashCode(str: string): number {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return hash;
  }

  /**
   * 批量处理图片
   */
  async processImages(configs: ImageProcessConfig[]): Promise<ImageProcessResult[]> {
    const results: ImageProcessResult[] = [];
    
    for (const config of configs) {
      const result = await this.processImage(config);
      results.push(result);
    }

    return results;
  }

  /**
   * 清理缓存的图片
   */
  clearCache(): void {
    try {
      const files = fileIo.listFileSync(this.cacheDir);
      
      files.forEach((fileName: string) => {
        if (fileName.endsWith(IMAGE_EXTENSION)) {
          const filePath = `${this.cacheDir}/${fileName}`;
          fileIo.unlinkSync(filePath);
          hilog.info(DOMAIN, TAG, `Deleted cached image: ${fileName}`);
        }
      });

      hilog.info(DOMAIN, TAG, 'Image cache cleared');
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Clear cache failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 获取缓存图片数量
   */
  getCachedImageCount(): number {
    try {
      const files = fileIo.listFileSync(this.cacheDir);
      return files.filter((name: string) => name.endsWith(IMAGE_EXTENSION)).length;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Get cached image count failed: ${JSON.stringify(err)}`);
      return 0;
    }
  }

  /**
   * 删除指定的缓存图片
   */
  deleteCachedImage(url: string): boolean {
    try {
      const fileName = this.generateFileName(url);
      const filePath = `${this.cacheDir}/${fileName}`;
      
      if (fileIo.accessSync(filePath)) {
        fileIo.unlinkSync(filePath);
        hilog.info(DOMAIN, TAG, `Deleted cached image: ${fileName}`);
        return true;
      }
      return false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Delete cached image failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 检查图片是否已缓存
   */
  isImageCached(url: string): boolean {
    try {
      const fileName = this.generateFileName(url);
      const filePath = `${this.cacheDir}/${fileName}`;
      return fileIo.accessSync(filePath);
    } catch (err) {
      return false;
    }
  }

  /**
   * 获取缓存的图片路径
   */
  getCachedImagePath(url: string): string | null {
    try {
      const fileName = this.generateFileName(url);
      const filePath = `${this.cacheDir}/${fileName}`;
      
      if (fileIo.accessSync(filePath)) {
        return filePath;
      }
      return null;
    } catch (err) {
      return null;
    }
  }
}

/**
 * 图片工作器管理类
 */
export class ImageWorkerManager {
  private static instance: ImageWorkerManager | null = null;
  private workers: Map<string, ImageWorker> = new Map();

  private constructor() {}

  static getInstance(): ImageWorkerManager {
    if (!ImageWorkerManager.instance) {
      ImageWorkerManager.instance = new ImageWorkerManager();
    }
    return ImageWorkerManager.instance;
  }

  /**
   * 获取或创建图片工作器
   */
  getWorker(context: Context): ImageWorker {
    const contextId = context.cacheDir;
    
    if (!this.workers.has(contextId)) {
      const worker = new ImageWorker(context);
      this.workers.set(contextId, worker);
    }

    return this.workers.get(contextId)!;
  }

  /**
   * 清理所有工作器
   */
  clearAllWorkers(): void {
    this.workers.clear();
    hilog.info(DOMAIN, TAG, 'All image workers cleared');
  }
}
