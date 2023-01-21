part of '../iptv_check_manager.dart';

/// 通过向下载队列添加url创建的请求
/// 用来在CheckManager和内部Isolate之间通信
class CheckRequest {
  CheckRequest._({
    required this.m3uEntryList,
    // this.path,
    this.channelCount,
    this.safeRange,
    required this.cancel,
    required this.resume,
    required this.pause,
  }) {
    _controller = StreamController.broadcast(onListen: () {
      if (_lastEvent == null) return;
      if (_lastEvent is Exception) {
        _controller.addError(_lastEvent);
      }
      _controller.add(_lastEvent);
    });
  }

  ///m3u文件路径url
  List<M3uGenericEntry> m3uEntryList;

  ///检测结果保存路径
  // String? path;

  /// 频道数量
  int? channelCount;

  bool? safeRange;

  ///是否暂停检测
  bool isPaused = false;

  ///是否取消检测
  bool isCancelled = false;

  /// 下载进度，-1表示正在排除，0.0-1.0表示下载进度
  double progress = -1.0;

  ProgressStatus progressStatus = ProgressStatus();

  /// Stream controller used to forward isolate events to user
  late final StreamController<dynamic> _controller;
  Stream<dynamic> get events => _controller.stream;

  void _addEvent(dynamic event) {
    _controller.add(event);
    _lastEvent = event;
  }

  void _addError(dynamic event) {
    _controller.addError(event);
    _lastEvent = event;
  }

  /// Current state
  dynamic _lastEvent;
  dynamic get event => _lastEvent;

  /// Control methods
  final void Function() cancel;
  final void Function() resume;
  final void Function() pause;
}
