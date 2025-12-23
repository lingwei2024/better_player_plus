/**
 * 事件队列管理器
 * 用于缓冲和传递事件，确保事件按顺序处理
 */
import hilog from '@ohos.hilog';

const TAG = 'QueuingEventSink';
const DOMAIN = 0x0001;

/**
 * 事件处理器接口
 */
export interface EventSink {
  success(event: Record<string, Object>): void;
  error(code: string, message: string, details?: Record<string, Object>): void;
  endOfStream(): void;
}

/**
 * 事件类型枚举
 */
enum EventType {
  SUCCESS = 0,
  ERROR = 1,
  END_OF_STREAM = 2
}

/**
 * 队列事件基类
 */
abstract class QueuedEvent {
  abstract type: EventType;
  abstract dispatch(sink: EventSink): void;
}

interface ErrorEventData {
  code: string;
  message: string;
  details?: Record<string, Object>;
}

/**
 * 成功事件
 */
class SuccessEvent extends QueuedEvent {
  type: EventType = EventType.SUCCESS;
  data: Record<string, Object>;

  constructor(data: Record<string, Object>) {
    super();
    this.data = data;
  }

  dispatch(sink: EventSink): void {
    sink.success(this.data);
  }
}

/**
 * 错误事件
 */
class ErrorEvent extends QueuedEvent {
  type: EventType = EventType.ERROR;
  code: string;
  message: string;
  details?: Record<string, Object>;

  constructor(code: string, message: string, details?: Record<string, Object>) {
    super();
    this.code = code;
    this.message = message;
    this.details = details;
  }

  dispatch(sink: EventSink): void {
    sink.error(this.code, this.message, this.details);
  }
}

/**
 * 流结束事件
 */
class EndOfStreamEvent extends QueuedEvent {
  type: EventType = EventType.END_OF_STREAM;

  dispatch(sink: EventSink): void {
    sink.endOfStream();
  }
}

/**
 * 队列化事件接收器
 * 实现EventSink接口，可以包装底层的事件接收器
 * 在设置委托之前缓存消息，设置委托后立即传递消息
 */
export class QueuingEventSink implements EventSink {
  private delegate: EventSink | null = null;
  private eventQueue: QueuedEvent[] = [];
  private done: boolean = false;

  /**
   * 设置委托事件接收器
   */
  setDelegate(delegate: EventSink | null): void {
    this.delegate = delegate;
    this.maybeFlush();
  }

  /**
   * 获取委托事件接收器
   */
  getDelegate(): EventSink | null {
    return this.delegate;
  }

  /**
   * 发送成功事件
   */
  success(event: Record<string, Object>): void {
    this.enqueue(new SuccessEvent(event));
    this.maybeFlush();
  }

  /**
   * 发送错误事件
   */
  error(code: string, message: string, details?: Record<string, Object>): void {
    this.enqueue(new ErrorEvent(code, message, details));
    this.maybeFlush();
  }

  /**
   * 发送流结束事件
   */
  endOfStream(): void {
    this.enqueue(new EndOfStreamEvent());
    this.maybeFlush();
    this.done = true;
  }

  /**
   * 将事件加入队列
   */
  private enqueue(event: QueuedEvent): void {
    if (this.done) {
      hilog.warn(DOMAIN, TAG, 'Attempted to enqueue event after stream ended');
      return;
    }
    this.eventQueue.push(event);
  }

  /**
   * 如果委托已设置，则刷新队列
   */
  private maybeFlush(): void {
    if (this.delegate === null) {
      return;
    }

    try {
      for (const event of this.eventQueue) {
        event.dispatch(this.delegate);
      }
      this.eventQueue = [];
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Error flushing event queue: ${JSON.stringify(err)}`);
    }
  }

  /**
   * 清空事件队列
   */
  clearQueue(): void {
    this.eventQueue = [];
    hilog.info(DOMAIN, TAG, 'Event queue cleared');
  }

  /**
   * 获取队列中的事件数量
   */
  getQueueSize(): number {
    return this.eventQueue.length;
  }

  /**
   * 检查队列是否为空
   */
  isEmpty(): boolean {
    return this.eventQueue.length === 0;
  }

  /**
   * 检查流是否已结束
   */
  isDone(): boolean {
    return this.done;
  }

  /**
   * 重置状态
   */
  reset(): void {
    this.delegate = null;
    this.eventQueue = [];
    this.done = false;
    hilog.info(DOMAIN, TAG, 'QueuingEventSink reset');
  }
}

/**
 * 事件流控制器
 * 管理多个事件流
 */
export class EventStreamController {
  private streams: Map<string, QueuingEventSink> = new Map();

  /**
   * 创建新的事件流
   */
  createStream(streamId: string): QueuingEventSink {
    if (this.streams.has(streamId)) {
      hilog.warn(DOMAIN, TAG, `Stream already exists: ${streamId}`);
      return this.streams.get(streamId)!;
    }

    const stream = new QueuingEventSink();
    this.streams.set(streamId, stream);
    hilog.info(DOMAIN, TAG, `Stream created: ${streamId}`);
    return stream;
  }

  /**
   * 获取事件流
   */
  getStream(streamId: string): QueuingEventSink | null {
    return this.streams.get(streamId) || null;
  }

  /**
   * 移除事件流
   */
  removeStream(streamId: string): void {
    const stream = this.streams.get(streamId);
    if (stream) {
      stream.clearQueue();
      this.streams.delete(streamId);
      hilog.info(DOMAIN, TAG, `Stream removed: ${streamId}`);
    }
  }

  /**
   * 关闭所有事件流
   */
  closeAllStreams(): void {
    this.streams.forEach((stream: QueuingEventSink, streamId: string) => {
      if (!stream.isDone()) {
        stream.endOfStream();
      }
      stream.clearQueue();
    });
    this.streams.clear();
    hilog.info(DOMAIN, TAG, 'All streams closed');
  }

  /**
   * 获取活跃的事件流数量
   */
  getActiveStreamCount(): number {
    return this.streams.size;
  }

  /**
   * 检查是否有指定的流
   */
  hasStream(streamId: string): boolean {
    return this.streams.has(streamId);
  }
}

/**
 * 简单的事件接收器实现
 * 用于测试和调试
 */
export class SimpleEventSink implements EventSink {
  private successCallback?: (event: Record<string, Object>) => void;
  private errorCallback?: (code: string, message: string, details?: Record<string, Object>) => void;
  private endCallback?: () => void;

  constructor(
    successCallback?: (event: Record<string, Object>) => void,
    errorCallback?: (code: string, message: string, details?: Record<string, Object>) => void,
    endCallback?: () => void
  ) {
    this.successCallback = successCallback;
    this.errorCallback = errorCallback;
    this.endCallback = endCallback;
  }

  success(event: Record<string, Object>): void {
    if (this.successCallback) {
      this.successCallback(event);
    } else {
      hilog.info(DOMAIN, TAG, `Success event: ${JSON.stringify(event)}`);
    }
  }

  error(code: string, message: string, details?: Record<string, Object>): void {
    if (this.errorCallback) {
      this.errorCallback(code, message, details);
    } else {
      hilog.error(DOMAIN, TAG, `Error event: ${code} - ${message}`);
    }
  }

  endOfStream(): void {
    if (this.endCallback) {
      this.endCallback();
    } else {
      hilog.info(DOMAIN, TAG, 'End of stream event');
    }
  }
}

/**
 * 事件记录接口
 */
interface EventRecord {
  type: string;
  timestamp: number;
  data: Record<string, Object>;
}

/**
 * 事件记录器
 * 用于调试，记录所有事件
 */
export class EventLogger implements EventSink {
  private events: EventRecord[] = [];
  private maxEvents: number;

  constructor(maxEvents: number = 100) {
    this.maxEvents = maxEvents;
  }

  success(event: Record<string, Object>): void {
    this.logEvent('success', event);
  }

  error(code: string, message: string, details?: Record<string, Object>): void {
    const errorData: ErrorEventData = {
      code,
      message
    };

    if (details !== undefined) {
      errorData.details = details;
    }

    // this.logEvent('error', errorData);
  }

  endOfStream(): void {
    this.logEvent('endOfStream', {});
  }

  private logEvent(type: string, data: Record<string, Object>): void {
    this.events.push({
      type: type,
      timestamp: Date.now(),
      data: data
    });

    // 限制事件数量
    if (this.events.length > this.maxEvents) {
      this.events.shift();
    }

    hilog.debug(DOMAIN, TAG, `Event logged: ${type}`);
  }

  /**
   * 获取所有记录的事件
   */
  getEvents(): EventRecord[] {
    return [...this.events];
  }

  /**
   * 清空事件记录
   */
  clear(): void {
    this.events = [];
  }

  /**
   * 获取事件数量
   */
  getEventCount(): number {
    return this.events.length;
  }
}
