/**
 * 自定义加载控制配置
 * 控制视频播放器的缓冲策略
 */
import hilog from '@ohos.hilog';

const TAG = 'CustomDefaultLoadControl';
const DOMAIN = 0x0001;

/**
 * 默认配置值（单位：毫秒）
 */
export class DefaultLoadControlConfig {
  // 默认最小缓冲时长: 50秒
  static readonly DEFAULT_MIN_BUFFER_MS: number = 50000;
  
  // 默认最大缓冲时长: 50秒
  static readonly DEFAULT_MAX_BUFFER_MS: number = 50000;
  
  // 默认开始播放所需缓冲: 2.5秒
  static readonly DEFAULT_BUFFER_FOR_PLAYBACK_MS: number = 2500;
  
  // 默认重新缓冲后播放所需缓冲: 5秒
  static readonly DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS: number = 5000;
}

/**
 * 自定义加载控制配置
 */
export class CustomDefaultLoadControl {
  /**
   * 播放器始终尝试确保缓冲的媒体的最小持续时间（毫秒）
   */
  readonly minBufferMs: number;

  /**
   * 播放器尝试缓冲的媒体的最大持续时间（毫秒）
   */
  readonly maxBufferMs: number;

  /**
   * 播放开始或用户操作（如seek）后恢复播放所需缓冲的媒体持续时间（毫秒）
   */
  readonly bufferForPlaybackMs: number;

  /**
   * 重新缓冲后恢复播放所需缓冲的媒体持续时间（毫秒）
   * 重新缓冲是指由于缓冲区耗尽而导致的暂停，而不是用户操作
   */
  readonly bufferForPlaybackAfterRebufferMs: number;

  /**
   * 构造函数 - 使用默认值
   */
  constructor();

  /**
   * 构造函数 - 使用自定义值
   */
  constructor(
    minBufferMs?: number,
    maxBufferMs?: number,
    bufferForPlaybackMs?: number,
    bufferForPlaybackAfterRebufferMs?: number
  );

  constructor(
    minBufferMs?: number,
    maxBufferMs?: number,
    bufferForPlaybackMs?: number,
    bufferForPlaybackAfterRebufferMs?: number
  ) {
    this.minBufferMs = minBufferMs ?? DefaultLoadControlConfig.DEFAULT_MIN_BUFFER_MS;
    this.maxBufferMs = maxBufferMs ?? DefaultLoadControlConfig.DEFAULT_MAX_BUFFER_MS;
    this.bufferForPlaybackMs = bufferForPlaybackMs ?? DefaultLoadControlConfig.DEFAULT_BUFFER_FOR_PLAYBACK_MS;
    this.bufferForPlaybackAfterRebufferMs = bufferForPlaybackAfterRebufferMs ?? 
      DefaultLoadControlConfig.DEFAULT_BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS;

    // 验证配置
    this.validateConfig();
  }

  /**
   * 验证配置参数
   */
  private validateConfig(): void {
    if (this.minBufferMs < 0) {
      hilog.warn(DOMAIN, TAG, `minBufferMs should not be negative: ${this.minBufferMs}`);
    }

    if (this.maxBufferMs < this.minBufferMs) {
      hilog.warn(DOMAIN, TAG, 
        `maxBufferMs (${this.maxBufferMs}) should not be less than minBufferMs (${this.minBufferMs})`);
    }

    if (this.bufferForPlaybackMs < 0) {
      hilog.warn(DOMAIN, TAG, `bufferForPlaybackMs should not be negative: ${this.bufferForPlaybackMs}`);
    }

    if (this.bufferForPlaybackAfterRebufferMs < this.bufferForPlaybackMs) {
      hilog.warn(DOMAIN, TAG,
        `bufferForPlaybackAfterRebufferMs (${this.bufferForPlaybackAfterRebufferMs}) ` +
        `should not be less than bufferForPlaybackMs (${this.bufferForPlaybackMs})`);
    }
  }

  /**
   * 创建默认配置
   */
  static createDefault(): CustomDefaultLoadControl {
    return new CustomDefaultLoadControl();
  }

  /**
   * 创建低延迟配置（适用于直播）
   */
  static createLowLatency(): CustomDefaultLoadControl {
    return new CustomDefaultLoadControl(
      10000,  // 10秒最小缓冲
      15000,  // 15秒最大缓冲
      1000,   // 1秒开始播放
      1500    // 1.5秒重新缓冲后播放
    );
  }

  /**
   * 创建高质量配置（适用于点播）
   */
  static createHighQuality(): CustomDefaultLoadControl {
    return new CustomDefaultLoadControl(
      60000,  // 60秒最小缓冲
      120000, // 120秒最大缓冲
      3000,   // 3秒开始播放
      6000    // 6秒重新缓冲后播放
    );
  }

  /**
   * 创建节省流量配置
   */
  static createDataSaving(): CustomDefaultLoadControl {
    return new CustomDefaultLoadControl(
      30000,  // 30秒最小缓冲
      40000,  // 40秒最大缓冲
      2000,   // 2秒开始播放
      4000    // 4秒重新缓冲后播放
    );
  }

  /**
   * 转换为配置对象
   */
  toConfig(): LoadControlConfig {
    return {
      minBufferMs: this.minBufferMs,
      maxBufferMs: this.maxBufferMs,
      bufferForPlaybackMs: this.bufferForPlaybackMs,
      bufferForPlaybackAfterRebufferMs: this.bufferForPlaybackAfterRebufferMs
    };
  }

  /**
   * 从配置对象创建
   */
  static fromConfig(config: LoadControlConfig): CustomDefaultLoadControl {
    return new CustomDefaultLoadControl(
      config.minBufferMs,
      config.maxBufferMs,
      config.bufferForPlaybackMs,
      config.bufferForPlaybackAfterRebufferMs
    );
  }

  /**
   * 克隆当前配置
   */
  clone(): CustomDefaultLoadControl {
    return new CustomDefaultLoadControl(
      this.minBufferMs,
      this.maxBufferMs,
      this.bufferForPlaybackMs,
      this.bufferForPlaybackAfterRebufferMs
    );
  }

  /**
   * 获取配置摘要
   */
  getSummary(): string {
    return `LoadControl(min=${this.minBufferMs}ms, max=${this.maxBufferMs}ms, ` +
      `playback=${this.bufferForPlaybackMs}ms, rebuffer=${this.bufferForPlaybackAfterRebufferMs}ms)`;
  }

  /**
   * 打印配置信息
   */
  logConfig(): void {
    hilog.info(DOMAIN, TAG, `Min Buffer: ${this.minBufferMs}ms`);
    hilog.info(DOMAIN, TAG, `Max Buffer: ${this.maxBufferMs}ms`);
    hilog.info(DOMAIN, TAG, `Buffer For Playback: ${this.bufferForPlaybackMs}ms`);
    hilog.info(DOMAIN, TAG, `Buffer For Playback After Rebuffer: ${this.bufferForPlaybackAfterRebufferMs}ms`);
  }

  /**
   * 比较两个配置是否相等
   */
  equals(other: CustomDefaultLoadControl): boolean {
    return this.minBufferMs === other.minBufferMs &&
      this.maxBufferMs === other.maxBufferMs &&
      this.bufferForPlaybackMs === other.bufferForPlaybackMs &&
      this.bufferForPlaybackAfterRebufferMs === other.bufferForPlaybackAfterRebufferMs;
  }
}

/**
 * 加载控制配置接口
 */
export interface LoadControlConfig {
  minBufferMs: number;
  maxBufferMs: number;
  bufferForPlaybackMs: number;
  bufferForPlaybackAfterRebufferMs: number;
}

/**
 * 缓冲状态
 */
export enum BufferState {
  // 缓冲不足
  INSUFFICIENT = 0,
  // 缓冲充足可以播放
  SUFFICIENT_FOR_PLAYBACK = 1,
  // 缓冲充足
  SUFFICIENT = 2,
  // 缓冲已满
  FULL = 3
}

/**
 * 缓冲管理器
 */
export class BufferManager {
  private loadControl: CustomDefaultLoadControl;
  private currentBufferMs: number = 0;
  private isBuffering: boolean = false;
  private listeners: BufferStateListener[] = [];

  constructor(loadControl: CustomDefaultLoadControl) {
    this.loadControl = loadControl;
  }

  /**
   * 更新当前缓冲时长
   */
  updateBuffer(bufferMs: number): void {
    this.currentBufferMs = bufferMs;
    const state = this.getBufferState();
    this.notifyBufferStateChanged(state);
  }

  /**
   * 获取当前缓冲状态
   */
  getBufferState(): BufferState {
    if (this.currentBufferMs >= this.loadControl.maxBufferMs) {
      return BufferState.FULL;
    } else if (this.currentBufferMs >= this.loadControl.minBufferMs) {
      return BufferState.SUFFICIENT;
    } else if (this.currentBufferMs >= this.loadControl.bufferForPlaybackMs) {
      return BufferState.SUFFICIENT_FOR_PLAYBACK;
    } else {
      return BufferState.INSUFFICIENT;
    }
  }

  /**
   * 是否可以开始播放
   */
  canStartPlayback(): boolean {
    return this.currentBufferMs >= this.loadControl.bufferForPlaybackMs;
  }

  /**
   * 是否可以在重新缓冲后播放
   */
  canResumeAfterRebuffer(): boolean {
    return this.currentBufferMs >= this.loadControl.bufferForPlaybackAfterRebufferMs;
  }

  /**
   * 添加缓冲状态监听器
   */
  addListener(listener: BufferStateListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  /**
   * 移除缓冲状态监听器
   */
  removeListener(listener: BufferStateListener): void {
    const index = this.listeners.indexOf(listener);
    if (index > -1) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 通知缓冲状态变化
   */
  private notifyBufferStateChanged(state: BufferState): void {
    this.listeners.forEach((listener: BufferStateListener) => {
      listener.onBufferStateChanged(state, this.currentBufferMs);
    });
  }

  /**
   * 设置缓冲状态
   */
  setBuffering(isBuffering: boolean): void {
    if (this.isBuffering !== isBuffering) {
      this.isBuffering = isBuffering;
      this.listeners.forEach((listener: BufferStateListener) => {
        listener.onBufferingChanged(isBuffering);
      });
    }
  }

  /**
   * 获取当前缓冲时长
   */
  getCurrentBufferMs(): number {
    return this.currentBufferMs;
  }

  /**
   * 获取缓冲百分比
   */
  getBufferPercentage(): number {
    return Math.min(100, (this.currentBufferMs / this.loadControl.maxBufferMs) * 100);
  }
}

/**
 * 缓冲状态监听器接口
 */
export interface BufferStateListener {
  onBufferStateChanged(state: BufferState, bufferMs: number): void;
  onBufferingChanged(isBuffering: boolean): void;
}
