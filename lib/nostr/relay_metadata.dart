import 'package:pointycastle/export.dart';

class RelayMetadata {
  String addr;

  bool read;

  bool write;

  RelayMetadata(
    this.addr,
    this.read,
    this.write,
  );

  static List<RelayMetadata> fromJson(Map<String, Object?> e) {
    List<String> read = e["read"].toString().split(",");
    List<String> write = e["write"].toString().split(",");
    Set<String> all = {};
    all.addAll(read);
    all.addAll(write);
    return all.map((e) => RelayMetadata(e, read.contains(e), write.contains(e))).toList();
  }

  static Map<String, Object?> toFullJson(String pubKey, List<RelayMetadata> list, int updated_at) {
    final Map<String, dynamic> data = new Map<String, dynamic>();
    data['pub_key'] = pubKey;
    List<String> read = [];
    List<String> write = [];
    for (var e in list) {
      if (e.read) {
        read.add(e.addr);
      }
      if (e.write) {
        write.add(e.addr);
      }
    }
    data['read'] = read.join(',');
    data['write'] = write.join(',');
    data['updated_at'] = updated_at;
    return data;
  }
}
