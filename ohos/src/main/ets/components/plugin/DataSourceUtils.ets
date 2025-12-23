/**
 * 数据源工具类
 * 处理HTTP请求头和URL验证
 */
import http from '@ohos.net.http';
import url from '@ohos.url';
import fs from '@ohos.file.fs';
import hilog from '@ohos.hilog';

const TAG = 'DataSourceUtils';
const DOMAIN = 0x0001;
const USER_AGENT = 'User-Agent';
const DEFAULT_USER_AGENT = 'HarmonyOS-BetterPlayer/1.0';

export class DataSourceUtils {
  /**
   * 获取User-Agent
   */
  static getUserAgent(headers?: Map<string, string>): string {
    if (headers && headers.has(USER_AGENT)) {
      return headers.get(USER_AGENT) || DEFAULT_USER_AGENT;
    }
    return DEFAULT_USER_AGENT;
  }

  /**
   * 创建HTTP请求对象
   */
  static createHttpRequest(
    userAgent: string,
    headers?: Map<string, string>,
    timeout: number = 30000
  ): http.HttpRequest {
    const httpRequest = http.createHttp();

    // 构建请求头
    const requestHeaders: Record<string, string> = {
      'User-Agent': userAgent,
      'Accept': '*/*',
      'Connection': 'keep-alive'
    };

    // 添加自定义请求头
    if (headers) {
      headers.forEach((value: string, key: string) => {
        if (key && value) {
          requestHeaders[key] = value;
        }
      });
    }

    return httpRequest;
  }

  /**
   * 构建HTTP请求选项
   */
  static buildHttpRequestOptions(
    method: http.RequestMethod,
    headers?: Map<string, string>,
    connectTimeout: number = 30000,
    readTimeout: number = 30000
  ): http.HttpRequestOptions {
    const userAgent = DataSourceUtils.getUserAgent(headers);
    
    const requestHeaders: Record<string, string> = {
      'User-Agent': userAgent,
      'Accept': '*/*',
      'Connection': 'keep-alive'
    };

    // 添加自定义请求头
    if (headers) {
      headers.forEach((value: string, key: string) => {
        if (key && value) {
          requestHeaders[key] = value;
        }
      });
    }

    return {
      method: method,
      header: requestHeaders,
      connectTimeout: connectTimeout,
      readTimeout: readTimeout,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    };
  }

  /**
   * 判断是否为HTTP/HTTPS协议
   */
  static isHTTP(uri: string): boolean {
    if (!uri) {
      return false;
    }

    try {
      const urlObject = url.URL.parseURL(uri);
      const scheme = urlObject.protocol.replace(':', '').toLowerCase();
      return scheme === 'http' || scheme === 'https';
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Parse URL failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 判断是否为本地文件
   */
  static isLocalFile(uri: string): boolean {
    if (!uri) {
      return false;
    }

    try {
      const urlObject = url.URL.parseURL(uri);
      const scheme = urlObject.protocol.replace(':', '').toLowerCase();
      return scheme === 'file' || uri.startsWith('/');
    } catch (err) {
      // 如果URL解析失败，可能是本地路径
      return uri.startsWith('/');
    }
  }

  /**
   * 验证URL格式
   */
  static isValidUrl(uri: string): boolean {
    if (!uri) {
      return false;
    }

    try {
      url.URL.parseURL(uri);
      return true;
    } catch (err) {
      return false;
    }
  }

  /**
   * 从URL中提取文件扩展名
   */
  static getFileExtension(uri: string): string {
    try {
      const urlObject = url.URL.parseURL(uri);
      const pathname = urlObject.pathname;
      const lastDotIndex = pathname.lastIndexOf('.');
      
      if (lastDotIndex > 0) {
        return pathname.substring(lastDotIndex + 1).toLowerCase();
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Get file extension failed: ${JSON.stringify(err)}`);
    }
    return '';
  }

  /**
   * 构建带查询参数的URL
   */
  static buildUrlWithParams(baseUrl: string, params?: Map<string, string>): string {
    if (!params || params.size === 0) {
      return baseUrl;
    }

    try {
      const urlObject = url.URL.parseURL(baseUrl);
      params.forEach((value: string, key: string) => {
        urlObject.params.append(key, value);
      });
      return urlObject.toString();
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Build URL with params failed: ${JSON.stringify(err)}`);
      return baseUrl;
    }
  }

  /**
   * 下载文件到本地
   */
  static async downloadFile(
    uri: string,
    destPath: string,
    headers?: Map<string, string>,
    progressCallback?: (received: number, total: number) => void
  ): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();
      const options = DataSourceUtils.buildHttpRequestOptions(http.RequestMethod.GET, headers);

      const response = await httpRequest.request(uri, options);
      
      if (response.responseCode === 200) {
        const data = response.result as ArrayBuffer;
        
        // 保存文件
        const file = await fs.open(destPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        fs.write(file.fd, data);
        fs.close(file);

        hilog.info(DOMAIN, TAG, `File downloaded successfully: ${destPath}`);
        return true;
      } else {
        hilog.error(DOMAIN, TAG, `Download failed with code: ${response.responseCode}`);
        return false;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Download file failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 获取HTTP响应头
   */
  static async getResponseHeaders(
    uri: string,
    headers?: Map<string, string>
  ): Promise<Record<string, string> | null> {
    try {
      const httpRequest = http.createHttp();
      const options = DataSourceUtils.buildHttpRequestOptions(http.RequestMethod.HEAD, headers);

      const response = await httpRequest.request(uri, options);
      
      if (response.responseCode === 200) {
        return response.header as Record<string, string>;
      }
      return null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Get response headers failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  /**
   * 检查资源是否存在
   */
  static async checkResourceExists(uri: string, headers?: Map<string, string>): Promise<boolean> {
    try {
      const httpRequest = http.createHttp();
      const options = DataSourceUtils.buildHttpRequestOptions(http.RequestMethod.HEAD, headers);

      const response = await httpRequest.request(uri, options);
      return response.responseCode === 200;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Check resource exists failed: ${JSON.stringify(err)}`);
      return false;
    }
  }

  /**
   * 获取内容长度
   */
  static async getContentLength(uri: string, headers?: Map<string, string>): Promise<number> {
    try {
      const responseHeaders = await DataSourceUtils.getResponseHeaders(uri, headers);
      if (responseHeaders && responseHeaders['Content-Length']) {
        return parseInt(responseHeaders['Content-Length'], 10);
      }
      return 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Get content length failed: ${JSON.stringify(err)}`);
      return 0;
    }
  }

  /**
   * 清理请求头（移除空值）
   */
  static cleanHeaders(headers?: Map<string, string>): Map<string, string> {
    const cleanedHeaders = new Map<string, string>();
    if (!headers) {
      return cleanedHeaders;
    }

    headers.forEach((value: string, key: string) => {
      if (key && value) {
        cleanedHeaders.set(key, value);
      }
    });

    return cleanedHeaders;
  }
}
