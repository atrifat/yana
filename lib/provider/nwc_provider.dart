import 'dart:convert';
import 'dart:io';

import 'package:bip340/bip340.dart';
import 'package:dart_ndk/dart_ndk.dart';
import 'package:dart_ndk/nips/nip01/bip340_event_signer.dart';
import 'package:dart_ndk/nips/nip01/event.dart';
import 'package:dart_ndk/nips/nip01/event_signer.dart';
import 'package:dart_ndk/nips/nip01/filter.dart';
import 'package:dart_ndk/nips/nip01/helpers.dart';
import 'package:dart_ndk/request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yana/nostr/event_kind.dart';

import '../main.dart';
import '../nostr/nip04/nip04.dart';
import '../nostr/nip47/nwc_commands.dart';
import '../nostr/nip47/nwc_kind.dart';
import '../utils/string_util.dart';
import 'data_util.dart';

class NwcProvider extends ChangeNotifier {
  static NwcProvider? _nwcProvider;

  String? uri;
  String? secret;
  String? walletPubKey;
  String? relay;
  int? balance;
  int? maxAmount;
  String? payInvoiceEventId;

  List<String> permissions = [];

  Future<void> init() async {
    // TODO make this multi account aware
    String? perms = sharedPreferences.getString(DataKey.NWC_PERMISSIONS);
    if (StringUtil.isNotBlank(perms)) {
      permissions = perms!.split(",");
    }
    uri = await settingProvider.getNwc();
    secret = await settingProvider.getNwcSecret();
    if (StringUtil.isNotBlank(uri) && StringUtil.isNotBlank(secret)) {
      walletPubKey = sharedPreferences.getString(DataKey.NWC_PUB_KEY);
      relay = sharedPreferences.getString(DataKey.NWC_RELAY);
      await connect(uri!);
    }
  }

  Future<void> reload() async {
    await init();
    notifyListeners();
  }

  int? get getBalance => balance;

  bool get isConnected =>
      permissions != null &&
      permissions.isNotEmpty &&
      StringUtil.isNotBlank(secret);

  Future<void>  connect(String nwc) async {
    nwc = nwc.replaceAll("yana:", "nostr+walletconnect:");
    Uri uri = Uri.parse(nwc.replaceAll("nostr+walletconnect:", "https:"));
    String? walletPubKey = uri.host;
    String? relay = uri.queryParameters['relay'];
    secret = uri.queryParameters['secret'];
    // String? lud16 = uri.queryParameters['lub16'];
    if (StringUtil.isBlank(relay)) {
      EasyLoading.showError("missing relay parameter", duration: const Duration(seconds: 5));
      return;
    }
    if (StringUtil.isBlank(secret)) {
      EasyLoading.showError("missing secret parameter", duration: const Duration(seconds: 5));
      return;
    }
    if (StringUtil.isBlank(walletPubKey)) {
      EasyLoading.showError("missing pubKey from connection uri", duration: const Duration(seconds: 5));
      return;
    }
    relay = Uri.decodeFull(relay!);
    await settingProvider.setNwc(nwc);
    await settingProvider.setNwcSecret(secret!);
    var filter = Filter(kinds: [NwcKind.INFO_REQUEST], authors: [walletPubKey!]);

    if (await relayManager.reconnectRelay(relay, force: true)) {
      (await relayManager.requestRelays([relay], filter)).stream.listen((event) async {
        await onEventInfo.call(event);
      });
    }
  }

  Future<void> onEventInfo(Nip01Event event) async {
    if (event.kind == NwcKind.INFO_REQUEST &&
        StringUtil.isNotBlank(event.content)) {
      walletPubKey = event.pubKey;
      relay = event.sources[0];
      sharedPreferences.setString(DataKey.NWC_PERMISSIONS, event.content);
      sharedPreferences.setString(DataKey.NWC_RELAY, relay!);
      sharedPreferences.setString(DataKey.NWC_PUB_KEY, walletPubKey!);
      permissions = event.content.split(",");
      if (permissions.contains(NwcCommand.GET_BALANCE) && balance==null) {
        await requestBalance(walletPubKey!, relay!, secret!);
      }
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    sharedPreferences.setString(DataKey.NWC_PERMISSIONS, "");
    await settingProvider.setNwc(null);
    await settingProvider.setNwcSecret(null);
    sharedPreferences.remove(DataKey.NWC_PERMISSIONS);
    sharedPreferences.remove(DataKey.NWC_RELAY);
    sharedPreferences.remove(DataKey.NWC_PUB_KEY);
    balance = null;
    maxAmount = null;
    uri = null;
    permissions = [];
    notifyListeners();
  }
  Future<void> requestBalance(String walletPubKey, String relay, String secret) async {
    if (StringUtil.isNotBlank(walletPubKey) &&
        StringUtil.isNotBlank(relay) &&
        StringUtil.isNotBlank(secret)) {
      EventSigner nwcSigner = Bip340EventSigner(secret!, getPublicKey(secret!));

      var agreement = NIP04.getAgreement(secret!);
      var encrypted = NIP04.encrypt('{"method":"${NwcCommand.GET_BALANCE}"}', agreement, walletPubKey!);

      var tags = [
        ["p", walletPubKey]
      ];
      final event = Nip01Event(pubKey: nwcSigner!.getPublicKey(), kind: NwcKind.REQUEST, tags: tags, content: encrypted);

      var filter = Filter(
          kinds: [NwcKind.RESPONSE], authors: [walletPubKey!], eTags: [event.id]);

      await relayManager.reconnectRelay(relay);

      NostrRequest balanceSubscription = await relayManager.requestRelays([relay!], filter, closeOnEOSE: false);
      balanceSubscription.stream.listen((event) async {
        await relayManager.closeNostrRequest(balanceSubscription);
        await onGetBalanceResponse(event);
      });
      await relayManager.broadcastEvent(event, [relay!], nwcSigner);
    } else {
      var filter = Filter(kinds: [NwcKind.INFO_REQUEST], authors: [walletPubKey!]);
      if (await relayManager.connectRelay(relay!)) {
        (await relayManager.requestRelays([relay!], filter)).stream.listen((event) {
          onEventInfo.call(event);
        });
      }
    }
  }

  Future<void> onGetBalanceResponse(Nip01Event event) async {
    if (event.kind == NwcKind.RESPONSE &&
        StringUtil.isNotBlank(event.content) &&
        StringUtil.isNotBlank(secret) &&
        StringUtil.isNotBlank(walletPubKey)) {
      var agreement = NIP04.getAgreement(secret!);
      var decrypted = NIP04.decrypt(event.content, agreement, walletPubKey!);
      Map<String, dynamic> data;
      data = json.decode(decrypted);
      if (data != null &&
          data.containsKey("result") &&
          data['result_type'] == NwcCommand.GET_BALANCE) {
        balance = data['result']['balance'];
        if (balance != null) {
          balance = balance! ~/ 1000;
        }
        maxAmount = data['result']['max_amount'];
        if (maxAmount != null) {
          maxAmount = maxAmount! ~/ 1000;
        }
        notifyListeners();
      } else if (data!=null && data.containsKey("error")) {
        var error = data['error']['code'];
        if (error == "UNAUTHORIZED") {
          await disconnect();
          notifyListeners();
        }
      }
    }
  }

  Future<void> payInvoice(String invoice, String? eventId, Function(bool) onZapped) async {
    if (StringUtil.isNotBlank(walletPubKey) &&
        StringUtil.isNotBlank(relay) &&
        StringUtil.isNotBlank(secret)) {
      EventSigner nwcSigner = Bip340EventSigner(secret!, getPublicKey(secret!));

      payInvoiceEventId = eventId;

      var agreement = NIP04.getAgreement(secret!);
      var encrypted =
          NIP04.encrypt('{"method":"${NwcCommand.PAY_INVOICE}", "params": { "invoice":"${invoice}"}}', agreement, walletPubKey!);
      var tags = [
        ["p", walletPubKey]
      ];
      final event = Nip01Event(pubKey: nwcSigner!.getPublicKey(), kind: NwcKind.REQUEST, tags: tags, content: encrypted);
      var filter = Filter(
          kinds: [NwcKind.RESPONSE], authors: [walletPubKey!], eTags: [event.id]);
      (await relayManager.requestRelays([relay!], filter, timeout: 20)).stream.listen((event) {
        onPayInvoiceResponse(event, onZapped);
      });
      await relayManager.broadcastEvent(event, [relay!], nwcSigner);
      // TODO use dart_ndk
      // nwcNostr!.queryRelay2(filter.toMap(), relay!, onPayInvoiceResponse, onZapped: onZapped);
      // TODO use dart_ndk
      // await nwcNostr!.sendRelayEvent(event, relay!);
    } else {
      EasyLoading.showError("missing pubKey and/or relay for connecting", duration: const Duration(seconds: 5));
    }
  }

  Future<void> onPayInvoiceResponse(Nip01Event event, Function(bool) onZapped) async {
    if (event.kind == NwcKind.RESPONSE &&
        StringUtil.isNotBlank(event.content) &&
        StringUtil.isNotBlank(secret) &&
        StringUtil.isNotBlank(walletPubKey)) {
      var agreement = NIP04.getAgreement(secret!);
      var decrypted = NIP04.decrypt(event.content, agreement, walletPubKey!);
      Map<String, dynamic> data;
      data = json.decode(decrypted);
      if (data != null &&
          data.containsKey("result") &&
          data['result_type'] == NwcCommand.PAY_INVOICE) {
        var preImage = data['result']['preimage'];
        EasyLoading.showSuccess("Zap payed", duration: const Duration(seconds: 2));
        if (payInvoiceEventId!=null) {
          // await eventReactionsProvider.subscription(payInvoiceEventId!, null, EventKind.ZAP_RECEIPT);
        }
        notifyListeners();
        requestBalance(walletPubKey!, relay!, secret!);
        onZapped(true);
      } else if (data!=null && data.containsKey("error")){
        onZapped(false);
        EasyLoading.showError("error ${data['error'].toString()}", duration: const Duration(seconds: 5));
      }
    }
    payInvoiceEventId = null;
  }
}
