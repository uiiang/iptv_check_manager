part of '../iptv_check_manager.dart';

/// 如果有长期隔离的isolate和CheckRequest，则使用worker来存储
class Worker {
  Worker({required this.isolate, required this.port});
  final Isolate isolate;
  final SendPort port;
  CheckRequest? request;

  /// Shortcuts to communicate with user
  void event(dynamic event) => request?._addEvent(event);
  void error(dynamic error) => request?._addError(error);
}
