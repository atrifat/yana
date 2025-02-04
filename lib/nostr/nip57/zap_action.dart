import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';

import '../../i18n/i18n.dart';
import '../../main.dart';
import '../../utils/lightning_util.dart';
import '../../utils/string_util.dart';
import '../event_kind.dart';
import 'zap.dart';

class ZapAction {
  static Future<void> handleZap(BuildContext context, int sats, String pubkey,
      {String? eventId, String? pollOption, String? comment, required Function(bool) onZapped}) async {
    var s = I18n.of(context);
    // EasyLoading.sho.showLoading();
    var invoiceCode = await _doGenInvoiceCode(context, sats, pubkey,
        eventId: eventId, pollOption: pollOption, comment: comment);

    if (StringUtil.isBlank(invoiceCode)) {
      EasyLoading.showError(s.Gen_invoice_code_error, duration: const Duration(seconds: 5));
      return;
    }
    bool sendWithWallet = false;
    if (await nwcProvider.isConnected) {
      int? balance = await nwcProvider.getBalance;
      if (balance!=null && balance > 10) {
        await nwcProvider.payInvoice(invoiceCode!, eventId, onZapped);
        sendWithWallet = true;
      }
    }
    if (!sendWithWallet) {
      await LightningUtil.goToPay(context, invoiceCode!);
//      await eventReactionsProvider.subscription(eventId!, null, EventKind.ZAP_RECEIPT);
      onZapped(true);
    }
  }

  static Future<String?> genInvoiceCode(
      BuildContext context, int sats, String pubkey,
      {String? eventId, String? pollOption, String? comment}) async {
    try {
      return await _doGenInvoiceCode(context, sats, pubkey,
          eventId: eventId, pollOption: pollOption, comment: comment);
    } catch (e) {
      print(e);
    }
  }

  static Future<String?> _doGenInvoiceCode(
      BuildContext context, int sats, String pubkey,
      {String? eventId, String? pollOption, String? comment}) async {
    var s = I18n.of(context);
    var metadata = metadataProvider.getMetadata(pubkey);
    if (metadata == null) {
      EasyLoading.show(status: s.Metadata_can_not_be_found);
      return null;
    }

    // lud06 like: LNURL1DP68GURN8GHJ7MRW9E6XJURN9UH8WETVDSKKKMN0WAHZ7MRWW4EXCUP0XPURJCEKXVERVDEJXCMKYDFHV43KX2HK8GT
    // lud16 like: pavol@rusnak.io
    // but some people set lud16 to lud06
    String? lnurl = metadata.lud06;
    String? lud16Link;

    if (StringUtil.isBlank(lnurl)) {
      if (StringUtil.isNotBlank(metadata.lud16)) {
        lnurl = Zap.getLnurlFromLud16(metadata.lud16!);
      }
    }
    if (StringUtil.isBlank(lnurl)) {
      EasyLoading.show(status: "Lnurl ${s.not_found}");
      return null;
    }
    // check if user set wrong
    if (lnurl!.contains("@")) {
      lnurl = Zap.getLnurlFromLud16(metadata.lud16!);
    }

    if (StringUtil.isBlank(lud16Link)) {
      if (StringUtil.isNotBlank(metadata.lud16)) {
        lud16Link = Zap.getLud16LinkFromLud16(metadata.lud16!);
      }
    }
    if (StringUtil.isBlank(lud16Link)) {
      if (StringUtil.isNotBlank(metadata.lud06)) {
        lud16Link = Zap.decodeLud06Link(metadata.lud06!);
      }
    }

    return await Zap.getInvoiceCode(
      lnurl: lnurl!,
      lud16Link: lud16Link!,
      sats: sats,
      recipientPubkey: pubkey,
      signer: loggedUserSigner!,
      relays: myOutboxRelaySet!.urls,
      eventId: eventId,
      pollOption: pollOption,
      comment: comment,
    );
  }
}
