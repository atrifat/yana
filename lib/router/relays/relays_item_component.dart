import 'package:cached_network_image/cached_network_image.dart';
import 'package:dart_ndk/nips/nip65/read_write_marker.dart';
import 'package:dart_ndk/relay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yana/main.dart';
import 'package:yana/utils/router_path.dart';
import 'package:yana/utils/router_util.dart';

import '../../i18n/i18n.dart';
import '../../ui/confirm_dialog.dart';
import '../../utils/base.dart';
import '../../utils/hash_util.dart';
import '../../utils/store_util.dart';
import '../../utils/string_util.dart';

class RelaysItemComponent extends StatelessWidget {
  Relay relay;
  String url;
  ReadWriteMarker marker;

  Function onRemove;

  RelaysItemComponent(
      {super.key,
      required this.url,
      required this.relay,
      required this.marker,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    var themeData = Theme.of(context);
    var cardColor = themeData.cardColor;
    Color borderLeftColor = Colors.red;
    if (relayManager.isRelayConnected(relay.url)) {
      borderLeftColor = Colors.green;
    } else if (relay.connecting) {
      borderLeftColor = Colors.yellow;
    }

    Widget imageWidget;

    String? iconUrl;

    if (relay.url.startsWith("wss://relay.damus.io")) {
      iconUrl = "https://damus.io/img/logo.png";
    } else if (relay.url.startsWith("wss://relay.snort.social")) {
      iconUrl = "https://snort.social/favicon.ico";
    } else {
      iconUrl = relay != null &&
              relay.info != null &&
              StringUtil.isNotBlank(relay.info!.icon)
          ? relay.info!.icon
          : StringUtil.robohash(HashUtil.md5(relay!.url));
    }

    imageWidget = Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          // color: themeData.cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: CachedNetworkImage(
          imageUrl: iconUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (context, url) => const CircularProgressIndicator(),
          errorWidget: (context, url, error) => CachedNetworkImage(
              imageUrl: StringUtil.robohash(HashUtil.md5(relay!.url))),
          cacheManager: localCacheManager,
        ));

    return GestureDetector(
        onTap: () {
          if (relay != null && relay.info != null) {
            RouterUtil.router(context, RouterPath.RELAY_INFO, relay);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(
            bottom: Base.BASE_PADDING_HALF,
            left: Base.BASE_PADDING_HALF,
            right: Base.BASE_PADDING_HALF,
          ),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.only(
                  left: Base.BASE_PADDING_HALF / 2,
                  right: Base.BASE_PADDING_HALF / 2,
                ),
                color: borderLeftColor,
                height: 50,
                child: const Icon(
                  Icons.lan,
                ),
              ),
              Expanded(
                  child: Row(
                children: [
                  Container(
                      padding: const EdgeInsets.only(
                        left: Base.BASE_PADDING,
                        top: Base.BASE_PADDING_HALF,
                        bottom: Base.BASE_PADDING_HALF,
                        right: Base.BASE_PADDING_HALF,
                      ),
                      child: imageWidget),
                  Container(
                      padding: const EdgeInsets.only(
                        left: Base.BASE_PADDING_HALF,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              relay.url.replaceAll("wss://", ""),
                              style: themeData.textTheme.titleLarge,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(
                                    right: Base.BASE_PADDING_HALF),
                                child: RelaysItemNumComponent(
                                    iconData: Icons.mail,
                                    textColor: themeData.disabledColor,
                                    iconColor: themeData.disabledColor,
                                    num: "${relay.stats.getTotalEventsRead()}"),
                              ),
                              Container(
                                  margin: const EdgeInsets.only(
                                      right: Base.BASE_PADDING_HALF),
                                  child: RelaysItemNumComponent(
                                    iconColor: Colors.lightGreen,
                                    textColor: Colors.lightGreen,
                                    iconData: Icons.lan_outlined,
                                    num: "${relay.stats.connections}",
                                  )),
                              Container(
                                  margin: const EdgeInsets.only(
                                      right: Base.BASE_PADDING_HALF),
                                  child: RelaysItemNumComponent(
                                    iconColor: relay.stats.connectionErrors > 0
                                        ? Colors.red
                                        : themeData.disabledColor,
                                    textColor: relay.stats.connectionErrors > 0
                                        ? Colors.red
                                        : themeData.disabledColor,
                                    iconData: Icons.error_outline,
                                    num: "${relay.stats.connectionErrors}",
                                  )),
                              Container(
                                  margin: const EdgeInsets.only(
                                      right: Base.BASE_PADDING_HALF),
                                  child: RelaysItemNumComponent(
                                    iconColor: themeData.disabledColor,
                                    textColor: themeData.disabledColor,
                                    iconData: Icons.network_check,
                                    num: StoreUtil.bytesToShowStr(
                                        relay.stats.getTotalBytesRead()),
                                  )),
                            ],
                          ),
                        ],
                      ))
                ],
              )),
              loggedUserSigner!.canSign()
                  ? GestureDetector(
                      onTap: () async {
                        bool canSwitch = marker.isWrite;
                        bool? result = await ConfirmDialog.show(
                            context,
                            canSwitch
                                ? "Broadcast setting relay to ${marker.isRead?"NOT ":""}read?"
                                : "Relay must either read or write!",
                            onlyCancel: !canSwitch);

                        if (result != null && result) {
                          marker = ReadWriteMarker.from(
                              read: !marker.isRead, write: marker.isWrite);
                          bool finished = false;
                          Future.delayed(const Duration(seconds: 1),() {
                            if (!finished) {
                              EasyLoading.show(status: "Refreshing relay list before changing...", maskType: EasyLoadingMaskType.black);
                            }
                          });
                          await relayProvider.updateMarker(url, marker);
                          finished = true;
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          right: Base.BASE_PADDING_HALF,
                        ),
                        child: Icon(
                          Icons.inbox_sharp,
                          color: marker.isRead
                              ? themeData.indicatorColor
                              : themeData.focusColor,
                        ),
                      ),
                    )
                  : Container(),
              loggedUserSigner!.canSign()
                  ? GestureDetector(
                      onTap: () async {
                        bool canSwitch = marker.isRead;
                        bool? result = await ConfirmDialog.show(
                            context,
                            canSwitch
                                ? "Broadcast setting relay to ${marker.isWrite?"NOT ":""}write?"
                                : "Relay must either read or write!",
                            onlyCancel: !canSwitch);

                        if (result != null && result) {
                          marker = ReadWriteMarker.from(
                              read: marker.isRead, write: !marker.isWrite);
                          bool finished = false;
                          Future.delayed(const Duration(seconds: 1),() {
                            if (!finished) {
                              EasyLoading.show(status: "Refreshing relay list before changing...", maskType: EasyLoadingMaskType.black);
                            }
                          });
                          await relayProvider.updateMarker(url, marker);
                          finished = true;
                          EasyLoading.dismiss();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          right: Base.BASE_PADDING_HALF,
                        ),
                        child: Icon(
                          Icons.send,
                          color: marker.isWrite
                              ? themeData.indicatorColor
                              : themeData.focusColor,
                        ),
                      ),
                    )
                  : Container(),
              loggedUserSigner!.canSign()
                  ? GestureDetector(
                      onTap: () async {
                        bool? result = await ConfirmDialog.show(
                            context, "Broadcast removal of relay?");

                        if (result != null && result) {
                          bool finished = false;
                          Future.delayed(const Duration(seconds: 1),() {
                            if (!finished) {
                              EasyLoading.show(status: "Refreshing relay list before removing...", maskType: EasyLoadingMaskType.black);
                            }
                          });
                          await relayProvider.removeRelay(url);
                          finished = true;
                          EasyLoading.dismiss();
                          onRemove();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.only(
                          right: Base.BASE_PADDING_HALF,
                        ),
                        child: Icon(
                          Icons.close,
                          color: themeData.disabledColor,
                        ),
                      ))
                  : Container(),
            ],
          ),
        ));
  }
}

class RelaysItemNumComponent extends StatelessWidget {
  Color? iconColor;
  Color? textColor;

  IconData iconData;

  String? num;

  RelaysItemNumComponent({
    super.key,
    this.iconColor,
    this.textColor,
    required this.iconData,
    this.num,
  });

  @override
  Widget build(BuildContext context) {
    var themeData = Theme.of(context);
    var smallFontSize = themeData.textTheme.bodySmall!.fontSize! - 1.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          iconData,
          color: iconColor,
          size: smallFontSize,
        ),
        num != null
            ? Container(
                margin: const EdgeInsets.only(left: Base.BASE_PADDING_HALF),
                child: Text(
                  num!,
                  style: TextStyle(fontSize: smallFontSize, color: textColor),
                ))
            : Container(),
      ],
    );
  }
}
