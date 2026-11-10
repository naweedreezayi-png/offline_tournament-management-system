import 'package:flutter/material.dart';

/// One entry of the in-app notification list.
class AppNotice {
  final String text;
  final DateTime time;
  const AppNotice(this.text, this.time);
}

/// In-app notifications, fed by the server's live-update stream (SSE).
/// This is NOT operating-system push: nothing arrives while the app is closed
/// (that would need Firebase Cloud Messaging with the owner's own Firebase project).
class NotificationCenter extends ChangeNotifier {
  NotificationCenter._();
  static final NotificationCenter instance = NotificationCenter._();

  final List<AppNotice> _items = [];
  int _unread = 0;

  List<AppNotice> get items => List.unmodifiable(_items);
  int get unread => _unread;

  void add(String text) {
    _items.insert(0, AppNotice(text, DateTime.now()));
    if (_items.length > 50) _items.removeLast();
    _unread++;
    notifyListeners();
  }

  void markRead() {
    if (_unread == 0) return;
    _unread = 0;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _unread = 0;
    notifyListeners();
  }
}
