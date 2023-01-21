import 'package:m3u/m3u.dart';

String createM3uContent(M3uGenericEntry m3uItem) {
  // #EXTM3U
// #EXTINF:-1 tvg-id="AnhuiSatelliteTV.cn" status="online",安徽卫视 (1080p)
// http://39.134.115.163:8080/PLTV/88888910/224/3221225691/index.m3u8
  String content = "";
  final attrStr = m3uItem.attributes.entries
      .map((e) {
        return '${e.key}="${e.value}"';
      })
      .toList()
      .join(" ");
  // final tvgid = 'tvg-id="${m3uItem.attributes["tvg-id"]}"';
  // final status = 'status="${m3uItem.attributes["status"]}"';
  final title = m3uItem.title;
  content += '#EXTINF:-1 $attrStr ,$title\n';
  content += '${m3uItem.link}\n';

  return content;
}
