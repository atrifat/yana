import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip04/nip04.dart';
import 'package:flutter/material.dart';
import 'package:get_time_ago/get_time_ago.dart';
import 'package:pointycastle/export.dart' as pointycastle;
import 'package:provider/provider.dart';
import 'package:yana/ui/content/content_decoder.dart';
import 'package:yana/utils/router_path.dart';
import 'package:yana/utils/router_util.dart';

import '../../provider/setting_provider.dart';
import '../../ui/user_pic_component.dart';
import '../../utils/base.dart';
import '../../utils/base_consts.dart';

class DMDetailItemComponent extends StatefulWidget {
  String sessionPubkey;

  Nip01Event event;

  bool isLocal;

  pointycastle.ECDHBasicAgreement agreement;

  DMDetailItemComponent({
    required this.sessionPubkey,
    required this.event,
    required this.isLocal,
    required this.agreement,
  });

  @override
  State<StatefulWidget> createState() {
    return _DMDetailItemComponent();
  }
}

class _DMDetailItemComponent extends State<DMDetailItemComponent> {
  static const double IMAGE_WIDTH = 34;

  static const double BLANK_WIDTH = 50;

  @override
  Widget build(BuildContext context) {
    var _settingProvider = Provider.of<SettingProvider>(context);
    var themeData = Theme.of(context);
    var mainColor = themeData.primaryColor;
    Widget userHeadWidget = Container(
      margin: const EdgeInsets.only(top: 2),
      child: UserPicComponent(
        pubkey: widget.event.pubKey,
        width: IMAGE_WIDTH,
      ),
    );
    // var maxWidth = mediaDataCache.size.width;
    var smallTextSize = themeData.textTheme.bodySmall!.fontSize;
    var hintColor = themeData.hintColor;

    String timeStr = GetTimeAgo.parse(
        DateTime.fromMillisecondsSinceEpoch(widget.event.createdAt * 1000));

    var content = Nip04.decryptWithAgreement(
        widget.event.content, widget.agreement, widget.sessionPubkey);

    var contentWidget = Container(
      margin: const EdgeInsets.only(
        left: Base.BASE_PADDING_HALF,
        right: Base.BASE_PADDING_HALF,
      ),
      child: Column(
        crossAxisAlignment:
            !widget.isLocal ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeStr,
            style: TextStyle(
              color: hintColor,
              fontSize: smallTextSize,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(Base.BASE_PADDING_HALF),
            // constraints:
            //     BoxConstraints(maxWidth: (maxWidth - IMAGE_WIDTH) * 0.85),
            decoration: BoxDecoration(
              // color: Colors.red,
              color: mainColor.withOpacity(0.3),
              borderRadius: const BorderRadius.all(Radius.circular(5)),
            ),
            // child: SelectableText(content),
            child: Column(
              crossAxisAlignment: widget.isLocal
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: ContentDecoder.decode(
                context,
                content,
                widget.event,
                showLinkPreview:
                    _settingProvider.linkPreview == OpenStatus.OPEN,
              ),
            ),
          ),
        ],
      ),
    );

    // if (!widget.isLocal) {
    userHeadWidget = GestureDetector(
      onTap: () {
        RouterUtil.router(context, RouterPath.USER, widget.event.pubKey);
      },
      child: userHeadWidget,
    );
    // }

    List<Widget> list = [];
    if (widget.isLocal) {
      list.add(Container(width: BLANK_WIDTH));
      list.add(Expanded(child: contentWidget));
      list.add(userHeadWidget);
    } else {
      list.add(userHeadWidget);
      list.add(Expanded(child: contentWidget));
      list.add(Container(width: BLANK_WIDTH));
    }

    return Container(
      padding: EdgeInsets.all(Base.BASE_PADDING_HALF),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: list,
      ),
    );
  }
}
