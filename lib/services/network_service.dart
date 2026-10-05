import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../utils/http_response.dart';
import '../utils/app_logger.dart';
import '../utils/sentry_network_tracing.dart';

/// 统一的网络服务管理器
/// 整合所有网络请求功能，提供统一的接口
class NetworkService {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._();

  @visibleForTesting
  static set instanceForTesting(NetworkService? value) => _instance = value;

  NetworkService._();

  // 不同用途的Dio实例
  late final Dio _generalDio; // 通用HTTP请求

  bool _initialized = false;

  @visibleForTesting
  Dio get generalDioForTesting => _generalDio;

  /// 初始化网络服务
  Future<void> init() async {
    if (_initialized) return;

    _generalDio = Dio();

    _configureGeneralDio();

    _initialized = true;
    logDebug('NetworkService 初始化完成');
  }

  /// 配置通用Dio实例
  void _configureGeneralDio() {
    _generalDio.options.connectTimeout = const Duration(seconds: 15);
    _generalDio.options.receiveTimeout = const Duration(seconds: 15);
    _generalDio.options.sendTimeout = const Duration(seconds: 15);

    // 添加日志拦截器
    if (kDebugMode) {
      _generalDio.interceptors.add(
        LogInterceptor(
          requestBody: false,
          responseBody: false,
          requestHeader: false,
          responseHeader: false,
          error: true,
          logPrint: (obj) => logDebug('[HTTP] $obj'),
        ),
      );
    }

    // 添加重试拦截器
    _generalDio.interceptors.add(
      RetryInterceptor(
        dio: _generalDio,
        logPrint: (obj) => logDebug('[RETRY] $obj'),
        retries: 1,
      ),
    );
    SentryNetworkTracing.addToGeneralDioIfEnabled(_generalDio);
  }

  /// 通用HTTP GET请求
  Future<HttpResponse> get(
    String url, {
    Map<String, String>? headers,
    int? timeoutSeconds,
  }) async {
    _ensureInitialized();

    try {
      // 安全检查
      if (!url.startsWith('https://') && !url.contains('hitokoto.cn')) {
        logDebug('警告: 使用非HTTPS URL: $url');
      }

      final response = await _generalDio.get(
        url,
        options: Options(
          headers: headers,
          receiveTimeout:
              timeoutSeconds != null ? Duration(seconds: timeoutSeconds) : null,
          responseType: url.contains('hitokoto.cn')
              ? ResponseType.json
              : ResponseType.plain,
        ),
      );

      return _convertDioResponseToHttpResponse(response);
    } on DioException catch (e, stack) {
      AppLogger.e(
        'GET请求失败: $url',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      return HttpResponse(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// 通用HTTP POST请求
  Future<HttpResponse> post(
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    _ensureInitialized();

    try {
      // 检查是否为HTTPS URL
      if (!url.startsWith('https://')) {
        throw Exception('非安全URL: 所有请求必须使用HTTPS');
      }

      final response = await _generalDio.post(
        url,
        data: body,
        options: Options(headers: headers),
      );

      return _convertDioResponseToHttpResponse(response);
    } on DioException catch (e, stack) {
      AppLogger.e(
        'POST请求失败: $url',
        error: e,
        stackTrace: stack,
        source: 'NetworkService',
      );
      return HttpResponse(
        '{"error": "${e.message}"}',
        e.response?.statusCode ?? 500,
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// 确保服务已初始化
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('NetworkService 未初始化，请先调用 init()');
    }
  }

  /// 转换Dio响应为HttpResponse
  HttpResponse _convertDioResponseToHttpResponse(Response dioResponse) {
    Map<String, String> convertedHeaders = {};
    dioResponse.headers.forEach((name, values) {
      if (values.isNotEmpty) {
        convertedHeaders[name] = values.join(", ");
      }
    });

    String responseBody;
    // 特殊处理一言API的响应
    if (dioResponse.requestOptions.uri.toString().contains('hitokoto.cn')) {
      if (dioResponse.data is Map<String, dynamic>) {
        responseBody = json.encode(dioResponse.data);
      } else if (dioResponse.data is String) {
        responseBody = dioResponse.data;
      } else {
        responseBody = dioResponse.data.toString();
      }
    } else {
      responseBody = dioResponse.data is String
          ? dioResponse.data
          : dioResponse.data.toString();
    }

    return HttpResponse(
      responseBody,
      dioResponse.statusCode ?? 0,
      headers: convertedHeaders,
    );
  }

  /// 清理资源
  void dispose() {
    _generalDio.close();
    _initialized = false;
    logDebug('NetworkService 已清理');
  }
}

/// 重试拦截器
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final Function(Object)? logPrint;

  RetryInterceptor({required this.dio, this.retries = 1, this.logPrint});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final rawCount = err.requestOptions.extra['retryCount'];
    final retryCount = (rawCount is num) ? rawCount.toInt() : 0;
    err.requestOptions.extra['retryCount'] = retryCount;

    if (retryCount < retries && _shouldRetry(err)) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      logPrint?.call(
        '重试请求 ${retryCount + 1}/$retries: ${err.requestOptions.uri}',
      );

      try {
        await Future.delayed(Duration(seconds: retryCount + 1));
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (e, stack) {
        AppLogger.e(
          '重试请求失败: ${err.requestOptions.uri}',
          error: e,
          stackTrace: stack,
          source: 'NetworkService_Retry',
        );
        // 继续到下一个重试或失败
      }
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);
  }
}
