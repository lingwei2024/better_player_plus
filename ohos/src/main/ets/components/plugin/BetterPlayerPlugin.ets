/**
 * BetterPlayerPlugin - 视频播放器插件
 * 管理多个播放器实例和与Flutter的通信
 */
import { BetterPlayer, DataSourceConfig, PlayerConfig } from './BetterPlayer';
import { BetterPlayerCache } from './BetterPlayerCache';
import { CustomDefaultLoadControl } from './CustomDefaultLoadControl';
import { QueuingEventSink, EventSink, EventStreamController } from './QueuingEventSink';
import { PreloadManager, PreloadConfig } from './CacheDataSourceFactory';
import { Context } from '@ohos.abilityAccessCtrl';
import hilog from '@ohos.hilog';


import {
  BinaryMessenger,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  MethodCall,
  TextureRegistry,
  EventChannel,
} from '@ohos/flutter_ohos';

const TAG = 'BetterPlayerPlugin';
const DOMAIN = 0x0001;

interface FlutterTexture {
  id: number;
  release(): void;
}

/**
 * 播放器插件主类
 */
export default class BetterPlayerPlugin implements FlutterPlugin, MethodCallHandler {

  private context!: Context; // ← 必须加
  private players: Map<string, BetterPlayer> = new Map();
  private dataSources: Map<string, Map<string, Object>> = new Map();
  private eventControllers: Map<string, QueuingEventSink> = new Map(); // 改为 Map 存储多个
  private preloadManager!: PreloadManager;
  private currentNotificationTextureId: string = '';
  private currentNotificationDataSource: Map<string, Object> | null = null;

  private textureRegistry?: TextureRegistry;
  private binaryMessenger?: BinaryMessenger | undefined;

  // 方法名常量
  private static readonly CHANNEL = 'better_player_channel';

  // 方法名
  private static readonly INIT_METHOD = 'init';
  private static readonly CREATE_METHOD = 'create';
  private static readonly SET_DATA_SOURCE_METHOD = 'setDataSource';
  private static readonly SET_LOOPING_METHOD = 'setLooping';
  private static readonly SET_VOLUME_METHOD = 'setVolume';
  private static readonly PLAY_METHOD = 'play';
  private static readonly PAUSE_METHOD = 'pause';
  private static readonly SEEK_TO_METHOD = 'seekTo';
  private static readonly POSITION_METHOD = 'position';
  private static readonly ABSOLUTE_POSITION_METHOD = 'absolutePosition';
  private static readonly SET_SPEED_METHOD = 'setSpeed';
  private static readonly SET_TRACK_PARAMETERS_METHOD = 'setTrackParameters';
  private static readonly SET_AUDIO_TRACK_METHOD = 'setAudioTrack';
  private static readonly SET_MIX_WITH_OTHERS_METHOD = 'setMixWithOthers';
  private static readonly DISPOSE_METHOD = 'dispose';
  private static readonly PRE_CACHE_METHOD = 'preCache';
  private static readonly STOP_PRE_CACHE_METHOD = 'stopPreCache';
  private static readonly CLEAR_CACHE_METHOD = 'clearCache';
  private static readonly ENABLE_PICTURE_IN_PICTURE_METHOD = 'enablePictureInPicture';
  private static readonly DISABLE_PICTURE_IN_PICTURE_METHOD = 'disablePictureInPicture';
  private static readonly IS_PICTURE_IN_PICTURE_SUPPORTED_METHOD = 'isPictureInPictureSupported';
  
  // 参数名
  private static readonly TEXTURE_ID_PARAMETER = 'textureId';
  private static readonly DATA_SOURCE_PARAMETER = 'dataSource';
  private static readonly KEY_PARAMETER = 'key';
  private static readonly ASSET_PARAMETER = 'asset';
  private static readonly URI_PARAMETER = 'uri';
  private static readonly PACKAGE_PARAMETER = 'package';
  private static readonly FORMAT_HINT_PARAMETER = 'formatHint';
  private static readonly HEADERS_PARAMETER = 'headers';
  private static readonly USE_CACHE_PARAMETER = 'useCache';
  private static readonly MAX_CACHE_SIZE_PARAMETER = 'maxCacheSize';
  private static readonly MAX_CACHE_FILE_SIZE_PARAMETER = 'maxCacheFileSize';
  private static readonly PRE_CACHE_SIZE_PARAMETER = 'preCacheSize';
  private static readonly CACHE_KEY_PARAMETER = 'cacheKey';
  private static readonly OVERRIDDEN_DURATION_PARAMETER = 'overriddenDuration';
  private static readonly LICENSE_URL_PARAMETER = 'licenseUrl';
  private static readonly DRM_HEADERS_PARAMETER = 'drmHeaders';
  private static readonly DRM_CLEARKEY_PARAMETER = 'clearKey';
  private static readonly LOOPING_PARAMETER = 'looping';
  private static readonly VOLUME_PARAMETER = 'volume';
  private static readonly SPEED_PARAMETER = 'speed';
  private static readonly LOCATION_PARAMETER = 'location';
  private static readonly WIDTH_PARAMETER = 'width';
  private static readonly HEIGHT_PARAMETER = 'height';
  private static readonly BITRATE_PARAMETER = 'bitrate';
  private static readonly NAME_PARAMETER = 'name';
  private static readonly INDEX_PARAMETER = 'index';
  private static readonly MIX_WITH_OTHERS_PARAMETER = 'mixWithOthers';
  private static readonly URL_PARAMETER = 'url';
  
  // 缓冲控制参数
  private static readonly MIN_BUFFER_MS = 'minBufferMs';
  private static readonly MAX_BUFFER_MS = 'maxBufferMs';
  private static readonly BUFFER_FOR_PLAYBACK_MS = 'bufferForPlaybackMs';
  private static readonly BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 'bufferForPlaybackAfterRebufferMs';
  
  // 通知相关参数
  private static readonly SHOW_NOTIFICATION_PARAMETER = 'showNotification';
  private static readonly TITLE_PARAMETER = 'title';
  private static readonly AUTHOR_PARAMETER = 'author';
  private static readonly IMAGE_URL_PARAMETER = 'imageUrl';
  private static readonly NOTIFICATION_CHANNEL_NAME_PARAMETER = 'notificationChannelName';
  private static readonly ACTIVITY_NAME_PARAMETER = 'activityName';

  ///////////////////
  private channel: MethodChannel | null = null;

  constructor() {}

  getUniqueClassName(): string {
    return "BetterPlayerPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binaryMessenger = binding.getBinaryMessenger();
    this.context = binding.getApplicationContext();
    this.textureRegistry = binding.getTextureRegistry();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), BetterPlayerPlugin.CHANNEL);
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.disposeAllPlayers();
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
    this.textureRegistry = undefined;
  }

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      console.log(".............................收到指令:" + call.method);
      switch (call.method) {
        case BetterPlayerPlugin.INIT_METHOD:
          this.handleInit(result);
          break;
          
        case BetterPlayerPlugin.CREATE_METHOD:
          await this.handleCreate(call, result);
          break;
          
        case BetterPlayerPlugin.PRE_CACHE_METHOD:
          await this.handlePreCache(call, result);
          break;
          
        case BetterPlayerPlugin.STOP_PRE_CACHE_METHOD:
          this.handleStopPreCache(call, result);
          break;
          
        case BetterPlayerPlugin.CLEAR_CACHE_METHOD:
          this.handleClearCache(result);
          break;
          
        default:
          // 需要 textureId 的方法
          const textureId = this.getArgument<string>(call, BetterPlayerPlugin.TEXTURE_ID_PARAMETER);
          if (!textureId) {
            result.error('INVALID_ARGUMENT', 'Missing textureId', undefined);
            return;
          }
          
          const player = this.players.get(textureId);
          if (!player) {
            result.error('NO_PLAYER', `No player found for textureId: ${textureId}`, undefined);
            return;
          }
          
          await this.handlePlayerMethod(call, result, textureId, player);
          break;
      }
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Method call failed: ${error.message}`);
      result.error('METHOD_CALL_ERROR', `Failed to execute method: ${error.message}`, undefined);
    }
  }

  /**
   * 处理播放器相关方法
   */
  private async handlePlayerMethod(
    call: MethodCall,
    result: MethodResult,
    textureId: string,
    player: BetterPlayer
  ): Promise<void> {
    switch (call.method) {
      case BetterPlayerPlugin.SET_DATA_SOURCE_METHOD:
        await this.handleSetDataSource(call, result, textureId, player);
        break;
        
      case BetterPlayerPlugin.SET_LOOPING_METHOD:
        const looping = this.getArgument<boolean>(call, BetterPlayerPlugin.LOOPING_PARAMETER);
        player.setLooping(looping || false);
        result.success(null);
        break;
        
      case BetterPlayerPlugin.SET_VOLUME_METHOD:
        const volume = this.getArgument<number>(call, BetterPlayerPlugin.VOLUME_PARAMETER);
        player.setVolume(volume || 1.0);
        result.success(null);
        break;
        
      case BetterPlayerPlugin.PLAY_METHOD:
        await player.play();
        result.success(null);
        break;
        
      case BetterPlayerPlugin.PAUSE_METHOD:
        await player.pause();
        result.success(null);
        break;
        
      case BetterPlayerPlugin.SEEK_TO_METHOD:
        const location = this.getArgument<number>(call, BetterPlayerPlugin.LOCATION_PARAMETER);
        await player.seekTo(location || 0);
        result.success(null);
        break;
        
      case BetterPlayerPlugin.POSITION_METHOD:
        const position = player.getPosition();
        player.sendBufferingUpdate(false);
        result.success(position);
        break;
        
      case BetterPlayerPlugin.ABSOLUTE_POSITION_METHOD:
        const absolutePosition = player.getAbsolutePosition();
        result.success(absolutePosition);
        break;
        
      case BetterPlayerPlugin.SET_SPEED_METHOD:
        const speed = this.getArgument<number>(call, BetterPlayerPlugin.SPEED_PARAMETER);
        player.setSpeed(speed || 1.0);
        result.success(null);
        break;
        
      case BetterPlayerPlugin.SET_TRACK_PARAMETERS_METHOD:
        const width = this.getArgument<number>(call, BetterPlayerPlugin.WIDTH_PARAMETER);
        const height = this.getArgument<number>(call, BetterPlayerPlugin.HEIGHT_PARAMETER);
        const bitrate = this.getArgument<number>(call, BetterPlayerPlugin.BITRATE_PARAMETER);
        player.setTrackParameters(width || 0, height || 0, bitrate || 0);
        result.success(null);
        break;
        
      case BetterPlayerPlugin.SET_AUDIO_TRACK_METHOD:
        const name = this.getArgument<string>(call, BetterPlayerPlugin.NAME_PARAMETER);
        const index = this.getArgument<number>(call, BetterPlayerPlugin.INDEX_PARAMETER);
        if (name && index !== undefined) {
          player.setAudioTrack(name, index);
        }
        result.success(null);
        break;
        
      case BetterPlayerPlugin.SET_MIX_WITH_OTHERS_METHOD:
        const mixWithOthers = this.getArgument<boolean>(call, BetterPlayerPlugin.MIX_WITH_OTHERS_PARAMETER);
        player.setMixWithOthers(mixWithOthers || false);
        result.success(null);
        break;
        
      case BetterPlayerPlugin.ENABLE_PICTURE_IN_PICTURE_METHOD:
        result.success(null);
        break;
        
      case BetterPlayerPlugin.DISABLE_PICTURE_IN_PICTURE_METHOD:
        result.success(null);
        break;
        
      case BetterPlayerPlugin.IS_PICTURE_IN_PICTURE_SUPPORTED_METHOD:
        result.success(false);
        break;
        
      case BetterPlayerPlugin.DISPOSE_METHOD:
        await this.disposePlayer(textureId, player);
        result.success(null);
        break;
        
      default:
        result.notImplemented();
        break;
    }
  }

  /**
   * 处理初始化
   */
  private handleInit(result: MethodResult): void {
    this.disposeAllPlayers();
    // result.success();
  }

  /**
   * 处理创建播放器
   */
  private async handleCreate(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      if (!this.textureRegistry) {
        result.error('no_texture', 'TextureRegistry not available', undefined);
        return;
      }
      // 添加 binaryMessenger 检查
      if (!this.binaryMessenger) {
        result.error('no_messenger', 'BinaryMessenger not available', undefined);
        return;
      }

      /** 1️⃣ 创建 Texture */
      const surfaceEntry = this.textureRegistry?.createSurfaceTexture();
      // const texture = this.textureRegistry.createTexture() as FlutterTexture;
      const textureId :number = surfaceEntry.getTextureId();

      /** 2️⃣ 创建 EventChannel（注意 channel 名） */
      const eventChannel :MethodChannel = new MethodChannel(
        this.binaryMessenger,
        `better_player_channel/videoEvents${textureId}`
      );


      const eventSink = new QueuingEventSink();
      this.eventControllers.set(textureId.toString(), eventSink);

      /** 3️⃣ 读取缓冲参数（可选） */
      let customLoadControl: CustomDefaultLoadControl | undefined;

      const minBufferMs :number = call.argument('minBufferMs');
      const maxBufferMs :number = call.argument('maxBufferMs');
      const bufferForPlaybackMs :number = call.argument('bufferForPlaybackMs');
      const bufferForPlaybackAfterRebufferMs :number =
        call.argument('bufferForPlaybackAfterRebufferMs');

      if (
        minBufferMs !== undefined &&
          maxBufferMs !== undefined &&
          bufferForPlaybackMs !== undefined &&
          bufferForPlaybackAfterRebufferMs !== undefined
      ) {
        customLoadControl = new CustomDefaultLoadControl(
          minBufferMs as number,
          maxBufferMs as number,
          bufferForPlaybackMs as number,
          bufferForPlaybackAfterRebufferMs as number
        );
      }

      const playerConfig: PlayerConfig = {
        textureId: textureId.toString(), // 修复：转换为 string
        loadControl: customLoadControl
      };

      /** 4️⃣ 创建 BetterPlayer 实例 */
      const player :BetterPlayer = new BetterPlayer(this.context, playerConfig, eventSink);


      // context: Context,
      // config: PlayerConfig,
      // eventSink: QueuingEventSink

      /** 5️⃣ 保存 */
      this.players.set(textureId.toString(), player);
      
      hilog.info(DOMAIN, TAG, `Player created with textureId: ${textureId}`);

      const reply: Record<string, number> = { // 修复：value 类型改为 number
        'textureId': textureId
      };
      result.success(reply);
      
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Create player failed: ${error.message}`);
      result.error('CREATE_ERROR', `Failed to create player: ${error.message}`, undefined);
    }
  }

  /**
   * 处理设置数据源
   */
  private async handleSetDataSource(
    call: MethodCall,
    result: MethodResult,
    textureId: string,
    player: BetterPlayer
  ): Promise<void> {
    try {
      const dataSourceObj = this.getArgument<Object>(call, BetterPlayerPlugin.DATA_SOURCE_PARAMETER);
      if (!dataSourceObj) {
        result.error('INVALID_ARGUMENT', 'Missing dataSource', undefined);
        return;
      }
      
      const dataSourceMap = dataSourceObj as Record<string, Object>;
      const dataSourceMapForStorage = new Map<string, Object>();
      Object.keys(dataSourceMap).forEach(key => {
        dataSourceMapForStorage.set(key, dataSourceMap[key]);
      });
      
      this.dataSources.set(textureId, dataSourceMapForStorage);
      
      const config: DataSourceConfig = {
        key: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.KEY_PARAMETER, ''),
        url: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.URI_PARAMETER, ''),
        formatHint: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.FORMAT_HINT_PARAMETER, undefined),
        headers: this.getHeadersParameter(dataSourceMap),
        useCache: this.getParameter<boolean>(dataSourceMap, BetterPlayerPlugin.USE_CACHE_PARAMETER, false),
        maxCacheSize: this.getParameter<number>(dataSourceMap, BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, 100 * 1024 * 1024),
        maxCacheFileSize: this.getParameter<number>(dataSourceMap, BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, 10 * 1024 * 1024),
        overriddenDuration: this.getParameter<number>(dataSourceMap, BetterPlayerPlugin.OVERRIDDEN_DURATION_PARAMETER, undefined),
        licenseUrl: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.LICENSE_URL_PARAMETER, undefined),
        drmHeaders: this.getHeadersParameter(dataSourceMap, BetterPlayerPlugin.DRM_HEADERS_PARAMETER),
        cacheKey: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.CACHE_KEY_PARAMETER, undefined),
        clearKey: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.DRM_CLEARKEY_PARAMETER, undefined)
      };
      
      await player.setDataSource(config);
      await player.prepare();
      
      result.success(null);
      
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Set data source failed: ${error.message}`);
      result.error('DATASOURCE_ERROR', `Failed to set data source: ${error.message}`, undefined);
    }
  }

  /**
   * 处理预缓存
   */
  private async handlePreCache(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const dataSourceObj = this.getArgument<Object>(call, BetterPlayerPlugin.DATA_SOURCE_PARAMETER);
      if (!dataSourceObj) {
        result.error('INVALID_ARGUMENT', 'Missing dataSource', undefined);
        return;
      }
      
      const dataSourceMap = dataSourceObj as Record<string, Object>;
      
      const config: PreloadConfig = {
        url: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.URI_PARAMETER, ''),
        headers: this.getHeadersParameter(dataSourceMap),
        preCacheSize: this.getParameter<number>(dataSourceMap, BetterPlayerPlugin.PRE_CACHE_SIZE_PARAMETER, 3 * 1024 * 1024),
        maxCacheSize: this.getParameter<number>(dataSourceMap, BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, 100 * 1024 * 1024),
        maxCacheFileSize: this.getParameter<number>(dataSourceMap, BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, 10 * 1024 * 1024),
        cacheKey: this.getParameter<string>(dataSourceMap, BetterPlayerPlugin.CACHE_KEY_PARAMETER, undefined)
      };
      
      await this.preloadManager.startPreload(config);
      result.success(null);
      
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Pre-cache failed: ${error.message}`);
      result.error('PRECACHE_ERROR', `Failed to pre-cache: ${error.message}`, undefined);
    }
  }

  /**
   * 处理停止预缓存
   */
  private handleStopPreCache(call: MethodCall, result: MethodResult): void {
    try {
      const url = this.getArgument<string>(call, BetterPlayerPlugin.URL_PARAMETER);
      if (url) {
        this.preloadManager.stopPreload(url);
      }
      result.success(null);
    } catch (err) {
      const error = err as Error;
      result.error('STOP_PRECACHE_ERROR', `Failed to stop pre-cache: ${error.message}`, undefined);
    }
  }

  /**
   * 处理清空缓存
   */
  private handleClearCache(result: MethodResult): void {
    try {
      BetterPlayer.clearCache(this.context);
      BetterPlayerCache.releaseCache();
      result.success(null);
    } catch (err) {
      const error = err as Error;
      result.error('CLEAR_CACHE_ERROR', `Failed to clear cache: ${error.message}`, undefined);
    }
  }

  /**
   * 释放播放器
   */
  private async disposePlayer(textureId: string, player: BetterPlayer): Promise<void> {
    try {
      await player.dispose();
      this.players.delete(textureId);
      this.dataSources.delete(textureId);
      const eventController = this.eventControllers.get(textureId);
      if (eventController) {
        eventController.endOfStream();
        this.eventControllers.delete(textureId);
      }
      
      hilog.info(DOMAIN, TAG, `Player disposed: ${textureId}`);
    } catch (err) {
      const error = err as Error;
      hilog.error(DOMAIN, TAG, `Dispose player failed: ${error.message}`);
    }
  }

  /**
   * 释放所有播放器
   */
  private disposeAllPlayers(): void {
    this.players.forEach(async (player: BetterPlayer, textureId: string) => {
      await player.dispose();
    });
    
    this.players.clear();
    this.dataSources.clear();
    // 清理所有 eventControllers
    this.eventControllers.forEach((eventSink: QueuingEventSink) => {
      try {
        eventSink.endOfStream();
      } catch (err) {
        hilog.error(DOMAIN, TAG, `Close event sink failed: ${err}`);
      }
    });
    this.eventControllers.clear();
    
    hilog.info(DOMAIN, TAG, 'All players disposed');
  }

  /**
   * 生成纹理ID
   */
  private generateTextureId(): string {
    return `texture_${Date.now()}_${Math.random().toString(36).substring(7)}`;
  }

  /**
   * 获取方法参数
   */
  private getArgument<T>(call: MethodCall, key: string): T | undefined {
    const value = call.argument(key) as T | undefined;
    return value;
  }

  /**
   * 获取数据源参数
   */
  private getParameter<T>(dataSource: Record<string, Object>, key: string, defaultValue?: T): T {
    const value = dataSource[key];
    if (value !== undefined && value !== null) {
      return value as T;
    }
    return defaultValue as T;
  }

  /**
   * 获取请求头参数
   */
  private getHeadersParameter(
    dataSource: Record<string, Object>,
    key: string = BetterPlayerPlugin.HEADERS_PARAMETER
  ): Map<string, string> | undefined {
    const headersObj = this.getParameter<Object>(dataSource, key, undefined);
    if (!headersObj) {
      return undefined;
    }
    
    const headers = new Map<string, string>();
    const headersRecord = headersObj as Record<string, string>;
    Object.keys(headersRecord).forEach(headerKey => {
      headers.set(headerKey, headersRecord[headerKey]);
    });
    
    return headers;
  }

  /**
   * 销毁插件
   */
  async destroy(): Promise<void> {
    this.disposeAllPlayers();
    this.preloadManager.stopAllPreloads();
    BetterPlayerCache.releaseCache();
    
    hilog.info(DOMAIN, TAG, 'Plugin destroyed');
  }
}
