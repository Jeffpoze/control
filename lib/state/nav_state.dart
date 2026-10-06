import 'package:flutter/foundation.dart';

/// The selected tab, and which server each tab is showing, so the home
/// screen can jump straight to a given client.
class NavState extends ChangeNotifier {
  int tab = 0;
  String? downloaderId;
  String? mediaId;

  static const home = 0, downloads = 1, media = 2, calendar = 3, more = 4;

  void go(int index) {
    if (tab == index) return;
    tab = index;
    notifyListeners();
  }

  void openDownloader(String id) {
    downloaderId = id;
    tab = downloads;
    notifyListeners();
  }

  void openMedia(String id) {
    mediaId = id;
    tab = media;
    notifyListeners();
  }
}
