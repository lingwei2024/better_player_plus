/**
 * BetterPlayer - 核心视频播放器类
 * 基于鸿蒙 AVPlayer 实现的视频播放器
 */
import media from '@ohos.multimedia.media';
import { Context } from '@ohos.abilityAccessCtrl';
import { BetterPlayerCache } from './BetterPlayerCache';
import { DataSourceUtils } from './DataSourceUtils';
import { CacheDataSourceFactory } from './CacheDataSourceFactory';
import { CustomDefaultLoadControl, BufferManager, BufferState } from './CustomDefaultLoadControl';
import { QueuingEventSink, EventSink } from './QueuingEventSink';
import hilog from '@ohos.hilog';
import fileIo from '@ohos.file.fs';

const TAG = 'BetterPlayer';
const DOMAIN = 0x0001;

/**
 * 视频格式类型
 */
export enum VideoFormat {
  SS = 'ss',
  DASH = 'dash',
  HLS = 'hls',
  MP4 = 'mp4',
  OTHER = 'other'
}

/**
 * 播放器状态
 */
export enum PlayerState {
  IDLE = 'idle',
  INITIALIZED = 'initialized',
  PREPARING = 'preparing',
  PREPARED = 'prepared',
  PLAYING = 'playing',
  PAUSED = 'paused',
  STOPPED = 'stopped',
  COMPLETED = 'completed',
  ERROR = 'error'
}

/**
 * 数据源配置
 */
export interface DataSourceConfig {
  key?: string;
  url: string;
  formatHint?: string;
  headers?: Map<string, string>;
  useCache: boolean;
  maxCacheSize: number;
  maxCacheFileSize: number;
  overriddenDuration?: number;
  licenseUrl?: string;
  drmHeaders?: Map<string, string>;
  cacheKey?: string;
  clearKey?: string;
}

/**
 * 播放器配置
 */
export interface PlayerConfig {
  textureId: string;
  loadControl?: CustomDefaultLoadControl;
}

/**
 * BetterPlayer 核心类
 */
export class BetterPlayer {
  private context: Context;
  private avPlayer: media.AVPlayer | null = null;
  private eventSink: QueuingEventSink;
  private loadControl: CustomDefaultLoadControl;
  private bufferManager: BufferManager;
  
  private playerState: PlayerState = PlayerState.IDLE;
  private isInitialized: boolean = false;
  private currentDataSource: DataSourceConfig | null = null;
  private textureId: string;
  private key: string | null = null;
  
  // 播放控制
  private isLooping: boolean = false;
  private currentVolume: number = 1.0;
  private currentSpeed: number = 1.0;
  private currentPosition: number = 0;
  private duration: number = 0;
  
  // 缓存管理
  private cacheFactory: CacheDataSourceFactory | null = null;
  
  // 音视频轨道
  private audioTracks: media.MediaDescription[] = [];
  private currentAudioTrack: number = 0;
  
  constructor(
    context: Context,
    config: PlayerConfig,
    eventSink: QueuingEventSink) {
    this.context = context;
    this.textureId = config.textureId;
    this.loadControl = config.loadControl || CustomDefaultLoadControl.createDefault();
    this.eventSink = eventSink;
    this.bufferManager = new BufferManager(this.loadControl);
    
    this.initialize();
  }

  /**
   * 初始化播放器
   */
  private async initialize(): Promise<void> {
    try {
      // 创建 AVPlayer
      this.avPlayer = await media.createAVPlayer();
      
      // 设置状态变化监听
      this.setupStateChangeListener();
      
      // 设置错误监听
      this.setupErrorListener();
      
      // 设置缓冲更新监听
      this.setupBufferingListener();
      
      // 设置播放完成监听
      this.setupCompletionListener();
      
      hilog.info(DOMAIN, TAG, 'Player initialized successfully');
      this.playerState = PlayerState.INITIALIZED;
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Initialize player failed: ${JSON.stringify(err)}`);
      this.sendError('INIT_ERROR', `Failed to initialize player: ${err}`);
    }
  }

  /**
   * 设置数据源
   */
  async setDataSource(config: DataSourceConfig): Promise<void> {
    try {
      if (!this.avPlayer) {
        throw new Error('Player not initialized');
      }

      this.currentDataSource = config;
      this.key = config.key || null;

      // 处理缓存
      if (config.useCache) {
        this.cacheFactory = new CacheDataSourceFactory(
          this.context,
          config.maxCacheSize,
          config.maxCacheFileSize
        );
      }

      // 检查是否为网络URL
      if (DataSourceUtils.isHTTP(config.url)) {
        await this.setNetworkDataSource(config);
      } else {
        await this.setLocalDataSource(config);
      }

      this.playerState = PlayerState.PREPARING;
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set data source failed: ${JSON.stringify(err)}`);
      this.sendError('DATASOURCE_ERROR', `Failed to set data source: ${err}`);
    }
  }

  /**
   * 设置网络数据源
   */
  private async setNetworkDataSource(config: DataSourceConfig): Promise<void> {
    try {
      if (!this.avPlayer) return;

      // 如果使用缓存，先尝试从缓存获取
      if (this.cacheFactory && config.useCache) {
        const dataSource = this.cacheFactory.createDataSource(
          config.url,
          config.headers,
          true,
          config.cacheKey
        );

        // 检查是否已缓存
        const cache = BetterPlayerCache.createCache(this.context, config.maxCacheSize);
        const cacheKey = config.cacheKey || this.generateCacheKey(config.url);
        
        if (cache && cache.hasCache(cacheKey)) {
          hilog.info(DOMAIN, TAG, 'Using cached video');
          const cachedPath = `${cache.getCacheDir()}/${cacheKey}`;
          this.avPlayer.url = cachedPath;
        } else {
          // 直接播放网络URL
          this.avPlayer.url = config.url;
        }
      } else {
        this.avPlayer.url = config.url;
      }

      // 设置HTTP请求头
      if (config.headers) {
        // 注意: AVPlayer 可能不直接支持自定义请求头
        // 需要根据实际API进行调整
        hilog.info(DOMAIN, TAG, 'HTTP headers set');
      }

    } catch (err) {
      throw new Error(`Set network data source failed: ${err}`);
    }
  }

  /**
   * 设置本地数据源
   */
  private async setLocalDataSource(config: DataSourceConfig): Promise<void> {
    try {
      if (!this.avPlayer) return;

      // 检查文件是否存在
      if (!fileIo.accessSync(config.url)) {
        throw new Error(`File not found: ${config.url}`);
      }

      this.avPlayer.url = config.url;
      hilog.info(DOMAIN, TAG, `Set local data source: ${config.url}`);
      
    } catch (err) {
      throw new Error(`Set local data source failed: ${err}`);
    }
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(url: string): string {
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      const char = url.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return Math.abs(hash).toString();
  }

  /**
   * 准备播放
   */
  async prepare(): Promise<void> {
    try {
      if (!this.avPlayer) {
        throw new Error('Player not initialized');
      }

      await this.avPlayer.prepare();
      this.playerState = PlayerState.PREPARED;
      
      // 获取视频信息
      this.duration = this.avPlayer.duration;
      
      hilog.info(DOMAIN, TAG, `Player prepared, duration: ${this.duration}ms`);
      
      if (!this.isInitialized) {
        this.isInitialized = true;
        this.sendInitialized();
      }
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Prepare failed: ${JSON.stringify(err)}`);
      this.sendError('PREPARE_ERROR', `Failed to prepare: ${err}`);
    }
  }

  /**
   * 开始播放
   */
  async play(): Promise<void> {
    try {
      if (!this.avPlayer) {
        throw new Error('Player not initialized');
      }

      if (this.playerState === PlayerState.IDLE || this.playerState === PlayerState.INITIALIZED) {
        await this.prepare();
      }

      await this.avPlayer.play();
      this.playerState = PlayerState.PLAYING;
      
      hilog.info(DOMAIN, TAG, 'Playback started');
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Play failed: ${JSON.stringify(err)}`);
      this.sendError('PLAY_ERROR', `Failed to play: ${err}`);
    }
  }

  /**
   * 暂停播放
   */
  async pause(): Promise<void> {
    try {
      if (!this.avPlayer) return;

      await this.avPlayer.pause();
      this.playerState = PlayerState.PAUSED;
      
      hilog.info(DOMAIN, TAG, 'Playback paused');
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Pause failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 停止播放
   */
  async stop(): Promise<void> {
    try {
      if (!this.avPlayer) return;

      await this.avPlayer.stop();
      this.playerState = PlayerState.STOPPED;
      
      hilog.info(DOMAIN, TAG, 'Playback stopped');
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Stop failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 跳转到指定位置
   */
  async seekTo(positionMs: number): Promise<void> {
    try {
      if (!this.avPlayer) return;

      await this.avPlayer.seek(positionMs);
      this.currentPosition = positionMs;
      
      const event: Record<string, Object> = {
        'event': 'seek',
        'position': positionMs
      };
      this.eventSink.success(event);
      
      hilog.info(DOMAIN, TAG, `Seek to: ${positionMs}ms`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Seek failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置循环播放
   */
  setLooping(loop: boolean): void {
    try {
      if (!this.avPlayer) return;

      this.isLooping = loop;
      this.avPlayer.loop = loop;
      
      hilog.info(DOMAIN, TAG, `Looping set to: ${loop}`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set looping failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置音量
   */
  setVolume(volume: number): void {
    try {
      if (!this.avPlayer) return;

      // 限制音量范围 0.0 - 1.0
      this.currentVolume = Math.max(0.0, Math.min(1.0, volume));
      this.avPlayer.setVolume(this.currentVolume);
      
      hilog.info(DOMAIN, TAG, `Volume set to: ${this.currentVolume}`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set volume failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置播放速度
   */
  setSpeed(speed: number): void {
    try {
      if (!this.avPlayer) return;

      this.currentSpeed = speed;
      // 注意: 需要检查 AVPlayer 是否支持播放速度设置
      // this.avPlayer.setSpeed(speed);
      
      hilog.info(DOMAIN, TAG, `Speed set to: ${speed}`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set speed failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置轨道参数
   */
  setTrackParameters(width: number, height: number, bitrate: number): void {
    try {
      // 注意: 需要根据 AVPlayer API 实现轨道选择
      hilog.info(DOMAIN, TAG, `Track parameters: ${width}x${height}, bitrate: ${bitrate}`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set track parameters failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置音频轨道
   */
  setAudioTrack(name: string, index: number): void {
    try {
      if (!this.avPlayer) return;

      this.currentAudioTrack = index;
      // 注意: 需要根据 AVPlayer API 实现音频轨道切换
      
      hilog.info(DOMAIN, TAG, `Audio track set: ${name}, index: ${index}`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set audio track failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 设置混音模式
   */
  setMixWithOthers(mixWithOthers: boolean): void {
    try {
      // 注意: 需要根据鸿蒙音频管理API实现
      hilog.info(DOMAIN, TAG, `Mix with others: ${mixWithOthers}`);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Set mix with others failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 获取当前播放位置
   */
  getPosition(): number {
    try {
      if (this.avPlayer) {
        return this.avPlayer.currentTime;
      }
      return 0;
    } catch (err) {
      return 0;
    }
  }

  /**
   * 获取绝对播放位置
   */
  getAbsolutePosition(): number {
    // 对于点播视频，绝对位置等于当前位置
    // 对于直播视频，需要加上起始时间戳
    return this.getPosition();
  }

  /**
   * 获取视频时长
   */
  getDuration(): number {
    try {
      if (this.avPlayer) {
        return this.avPlayer.duration;
      }
      return 0;
    } catch (err) {
      return 0;
    }
  }

  /**
   * 发送缓冲更新
   */
  sendBufferingUpdate(isFromBufferingStart: boolean): void {
    try {
      const bufferedPosition = this.getBufferedPosition();
      
      const event: Record<string, Object> = {
        'event': 'bufferingUpdate',
        'values': [[0, bufferedPosition]]
      };
      
      this.eventSink.success(event);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Send buffering update failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 获取已缓冲位置
   */
  private getBufferedPosition(): number {
    // 注意: 需要根据 AVPlayer API 获取缓冲位置
    return 0;
  }

  /**
   * 设置状态变化监听
   */
  private setupStateChangeListener(): void {
    if (!this.avPlayer) return;

    this.avPlayer.on('stateChange', (state: string) => {
      hilog.info(DOMAIN, TAG, `State changed: ${state}`);
      
      switch (state) {
        case 'idle':
          this.playerState = PlayerState.IDLE;
          break;
        case 'initialized':
          this.playerState = PlayerState.INITIALIZED;
          break;
        case 'prepared':
          this.playerState = PlayerState.PREPARED;
          if (!this.isInitialized) {
            this.isInitialized = true;
            this.sendInitialized();
          }
          break;
        case 'playing':
          this.playerState = PlayerState.PLAYING;
          break;
        case 'paused':
          this.playerState = PlayerState.PAUSED;
          break;
        case 'stopped':
          this.playerState = PlayerState.STOPPED;
          break;
        case 'completed':
          this.playerState = PlayerState.COMPLETED;
          this.handlePlaybackCompleted();
          break;
        case 'error':
          this.playerState = PlayerState.ERROR;
          break;
      }
    });
  }

  /**
   * 设置错误监听
   */
  private setupErrorListener(): void {
    if (!this.avPlayer) return;

    this.avPlayer.on('error', (error) => {
      hilog.error(DOMAIN, TAG, `Player error: ${JSON.stringify(error)}`);
      this.sendError('PLAYBACK_ERROR', `Playback error: ${error}`);
    });
  }

  /**
   * 设置缓冲监听
   */
  private setupBufferingListener(): void {
    if (!this.avPlayer) return;

    this.avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType) => {
      if (infoType === media.BufferingInfoType.BUFFERING_START) {
        const event: Record<string, Object> = {
          'event': 'bufferingStart'
        };
        this.eventSink.success(event);
        this.bufferManager.setBuffering(true);
      } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
        const event: Record<string, Object> = {
          'event': 'bufferingEnd'
        };
        this.eventSink.success(event);
        this.bufferManager.setBuffering(false);
      }
    });
  }

  /**
   * 设置播放完成监听
   */
  private setupCompletionListener(): void {
    // 状态变化监听中已处理
  }

  /**
   * 处理播放完成
   */
  private handlePlaybackCompleted(): void {
    const event: Record<string, Object> = {
      'event': 'completed',
      'key': this.key || ''
    };
    this.eventSink.success(event);
    
    hilog.info(DOMAIN, TAG, 'Playback completed');
  }

  /**
   * 发送初始化完成事件
   */
  private sendInitialized(): void {
    if (!this.isInitialized) return;

    const event: Record<string, Object> = {
      'event': 'initialized',
      'key': this.key || '',
      'duration': this.getDuration()
    };

    // 获取视频宽高
    if (this.avPlayer) {
      try {
        const width = this.avPlayer.width;
        const height = this.avPlayer.height;
        event['width'] = width;
        event['height'] = height;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Failed to get video dimensions');
      }
    }

    this.eventSink.success(event);
    hilog.info(DOMAIN, TAG, 'Initialized event sent');
  }

  /**
   * 发送错误事件
   */
  private sendError(code: string, message: string): void {
    this.eventSink.error(code, message);
    hilog.error(DOMAIN, TAG, `Error: ${code} - ${message}`);
  }

  /**
   * 画中画相关
   */
  onPictureInPictureStatusChanged(inPip: boolean): void {
    const event: Record<string, Object> = {
      'event': inPip ? 'pipStart' : 'pipStop'
    };
    this.eventSink.success(event);
  }

  /**
   * 释放资源
   */
  async dispose(): Promise<void> {
    try {
      if (this.avPlayer) {
        await this.avPlayer.release();
        this.avPlayer = null;
      }

      this.eventSink.endOfStream();
      this.playerState = PlayerState.IDLE;
      this.isInitialized = false;
      
      hilog.info(DOMAIN, TAG, 'Player disposed');
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Dispose failed: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 获取播放器状态
   */
  getState(): PlayerState {
    return this.playerState;
  }

  /**
   * 获取纹理ID
   */
  getTextureId(): string {
    return this.textureId;
  }

  /**
   * 清空缓存（静态方法）
   */
  static clearCache(context: Context): void {
    try {
      const cacheDir = `${context.cacheDir}/betterPlayerCache`;
      if (fileIo.accessSync(cacheDir)) {
        const files = fileIo.listFileSync(cacheDir);
        files.forEach((file: string) => {
          const filePath = `${cacheDir}/${file}`;
          fileIo.unlinkSync(filePath);
        });
        hilog.info(DOMAIN, TAG, 'Cache cleared');
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Clear cache failed: ${JSON.stringify(err)}`);
    }
  }
}
