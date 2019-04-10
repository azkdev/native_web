import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_webview_plugin/flutter_webview_plugin.dart';
import 'package:geolocator/geolocator.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:barcode_scan/barcode_scan.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info/device_info.dart';
import 'package:contacts_service/contacts_service.dart';

import 'configs.dart' as cfg;
import 'agora_video_call.dart';
import 'agora_voice_call.dart';

// Entry point of app
void main() => runApp(WebApp());

// Entry point App scaffold
class WebApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: WebAppHome(),
    );
  }
}

class WebAppHome extends StatelessWidget {
  static const String MESSAGE_PREFIX = 'flutterHost';
  final Set<BuildContext> ctxs = Set();

  // Device info plugin
  final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

  final FlutterWebviewPlugin _webviewPlugin = new FlutterWebviewPlugin();
  // final FirebaseMessaging _firebaseMessaging = FirebaseMessaging();
  // final FlutterLocalNotificationsPlugin _localNotifications =
  //     new FlutterLocalNotificationsPlugin();

  // Data for progress indicator.
  final StreamController<double> _progress = StreamController<double>();
  Sink<double> get _progressSink => _progress.sink;
  Stream<double> get _progressStream => _progress.stream;

  Timer t;
  Random r;
  double progr;

  @override
  Widget build(BuildContext context) {
    if (cfg.configs['url'] == null || cfg.configs['url'] == '') {
      // Configuration not available
      return Container();
    }

    _enableCameraAndMic();

    // Close data stream for progress indicator if webview disposed
    _webviewPlugin.onDestroy.listen((_) {
      _progress.close();
    });

    // Parse configuration
    final initialUrl = cfg.configs['url'];
    final title = cfg.configs['title'];

    // Setup app bar
    var appBar;
    if (cfg.configs['app_bar'] != null && cfg.configs['app_bar']['visible']) {
      appBar = AppBar(
        title: Text(title),
        backgroundColor: Colors.deepPurple,
      );
    }

    // Setup remote notifications
    if (cfg.configs['notifications']) {
      _enableRemoteNotifications(cfg.configs);
    }

    // Setup local notifications
    // var initializationSettings = new InitializationSettings(
    //     new AndroidInitializationSettings('ic_notification'),
    //     new IOSInitializationSettings());
    // _localNotifications.initialize(initializationSettings,
    //     onSelectNotification: (url) {
    //   if (url != null) {
    //     _webviewPlugin.launch(url);
    //   }
    // });

    // Trigger native geolocation permission request if needed
    if (cfg.configs['geolocation']) {
      Geolocator().getLastKnownPosition(desiredAccuracy: LocationAccuracy.high);
    }

    // On state changed hide or show webview and progress indicator
    // If state == startLoad -> hide webview, show progress indicator
    // If state == finishLoad -> show webview, hide progress indicator
    _webviewPlugin.onStateChanged.listen((WebViewStateChanged state) {
      _showProgress(state);
    });

    // Setup js->flutter bridge
    _webviewPlugin.onUrlChanged.listen((String url) {
      String fragment = Uri.parse(url).fragment;
      if (fragment.startsWith(MESSAGE_PREFIX)) {
        String message = fragment.substring(MESSAGE_PREFIX.length + 1);
        _onJavascriptMessage(message);
      }
    });

    ctxs.add(context);

    // Build application
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: WebviewScaffold(
          url: initialUrl,
          geolocationEnabled: true,
          appBar: appBar,
          initialChild: _buildInitialChild(),
        ),
        bottom: true,
        top: true,
        left: true,
        right: true,
      ),
    );
  }

  // Handle device info
  void _getDeviceInfo() async {
    AndroidDeviceInfo andrInfo;
    IosDeviceInfo iosInfo;
    String info;
    Map<String, dynamic> mapInfo;
    if (Platform.isAndroid) {
      andrInfo = await deviceInfo.androidInfo;
      mapInfo = {
        'androidId': andrInfo.androidId,
        'id': andrInfo.id,
        'model': andrInfo.model,
        'version': andrInfo.version,
      };
      info = jsonEncode(mapInfo);
      _invokeJavascriptCallback('onDeviceInfo', info);
    }
    if (Platform.isIOS) {
      iosInfo = await deviceInfo.iosInfo;
      mapInfo = {
        'vendorId': iosInfo.identifierForVendor,
        'model': iosInfo.model,
        'name': iosInfo.name,
        'systemName': iosInfo.systemName,
        'systemVersion': iosInfo.systemVersion,
        'utsName': iosInfo.utsname.machine,
      };
      info = jsonEncode(mapInfo);
      _invokeJavascriptCallback('onDeviceInfo', info);
    }
  }

  // Get contacts
  void _getContacts() async {
    List<Map<String, dynamic>> cts = [];
    // Get all contacts without thumbnail(faster)
    await PermissionHandler().requestPermissions([PermissionGroup.contacts]);
    Iterable<Contact> contacts =
        await ContactsService.getContacts(withThumbnails: false);
    contacts.forEach((Contact ct) {
      if (ct.phones.length > 0) {
        Map<String, dynamic> contct = {
          'name': ct.displayName,
          'phones': ct.phones.map((Item i) => i.value).toList(),
        };
        cts.add(contct);
      }
    });

    _invokeJavascriptCallback('onContactsData', jsonEncode(cts));
  }

  void _showProgress(WebViewStateChanged state) async {
    if (state.type == WebViewState.startLoad) {
      // await _webviewPlugin
      //     .evalJavascript('if (FlutterHost) FlutterHost.isNative = true;');
      await _webviewPlugin.hide();
      t?.cancel();
      r = Random();
      progr = 0.0;
      _progressSink.add(progr);
      t = Timer.periodic(Duration(milliseconds: 1), (Timer t) {
        double nr = r.nextDouble() * 0.0004;
        _progressSink.add(progr += nr);
      });
    }
    if (state.type == WebViewState.finishLoad) {
      _invokeJavascriptCallback('onNative', true);
      await _webviewPlugin.show();
      progr = 0.0;
      _progressSink.add(0.0);
    }
  }

  // Handler for camera and mic permissions on first app lounch
  void _enableCameraAndMic() async {
    await PermissionHandler().requestPermissions(
        [PermissionGroup.camera, PermissionGroup.microphone]);
  }

  void _enableRemoteNotifications(config) {
    // Request notifications permission on iOS
    // _firebaseMessaging.requestNotificationPermissions();

    // Listen for messages
    // _firebaseMessaging.configure(
    //   onMessage: (Map<String, dynamic> msg) {
    //     print('Got FCM message in foreground ${(msg)}');
    //     _handleRemoteMessage(msg, true);
    //   },
    //   onLaunch: (Map<String, dynamic> msg) {
    //     print('Pending FCM message on launch ${(msg)}');
    //     _handleRemoteMessage(msg, false);
    //   },
    //   onResume: (Map<String, dynamic> msg) {
    //     print('Pending FCM message on resume ${(msg)}');
    //     _handleRemoteMessage(msg, false);
    //   },
    // );

    // Optionally subscribe to a FCM topic
    final fcmTopic = config['fcm_topic'];
    if (fcmTopic != null) {
      // _firebaseMessaging.subscribeToTopic(fcmTopic);
    }

    // Listen for token updates
    // _firebaseMessaging.onTokenRefresh.listen(_handleFcmToken);
  }

  void _handleFcmToken(token) {
    print('Got FCM token $token');
    _invokeJavascriptCallback('onFcmToken', token);
  }

  void _handleRemoteMessage(msg, showNotification) {
    print('Got remote message $msg');
    if (!msg.containsKey('notification') ||
        !msg.containsKey('data') ||
        !msg['notification'].containsKey('title') ||
        !msg['notification'].containsKey('body') ||
        !msg['data'].containsKey('url')) {
      print('Malformed remote message');
      return;
    }
    final url = msg['data']['url'];
    if (showNotification) {
      // var androidDetails = new AndroidNotificationDetails(
      //     'main', cfg.configs['title'], '',
      //     importance: Importance.Max, priority: Priority.High);
      // var platformChannelSpecifics =
      //     new NotificationDetails(androidDetails, new IOSNotificationDetails());
      // _localNotifications.show(0, msg['notification']['title'],
      //     msg['notification']['body'], platformChannelSpecifics,
      //     payload: url);
    } else {
      _webviewPlugin.launch(url);
    }
  }

  // Expose native features to JavaScript code
  void _onJavascriptMessage(String message) {
    _webviewPlugin.evalJavascript('_messageArgs').then((jsonArgs) {
      _webviewPlugin.evalJavascript('_messageArgs = "{}";');
      print('JSON ARGS: $jsonArgs');
      var args;
      try {
        if (Platform.isAndroid) {
          // flutter_webview_plugin bug?
          jsonArgs = jsonArgs.replaceAll(new RegExp(r'\\\"'), "\"");
          jsonArgs = jsonArgs.substring(1, jsonArgs.length - 1);
        }
        args = json.decode(jsonArgs);
      } on FormatException catch (e) {
        print('Error message: ${e.message}');
        args = {};
      }
      switch (message) {
        case 'joinVideoChannel':
          _joinVideoCall(args['channel'], ctxs.first, _webviewPlugin, args);
          break;
        case 'joinVoiceChannel':
          _joinVoiceCall(args['channel'], ctxs.first, _webviewPlugin, args);
          break;
        case 'getDeviceInfo':
          _getDeviceInfo();
          break;
        case 'getContacts':
          _getContacts();
          break;
        case 'trackLocation':
          _trackLocation();
          break;
        case 'scheduleNotification':
          _scheduleLocalNotification(args['id'], args['title'], args['body'],
              DateTime.parse(args['date']));
          break;
        case 'unscheduleNotification':
          _unscheduleLocalNotification(args['id']);
          break;
        case 'fcmToken':
          // _firebaseMessaging.getToken().then((token) {
          //   _invokeJavascriptCallback('onFcmToken', token);
          // });
          break;
        case 'scanBarcode':
          _scanBarcode();
          break;
      }
    });
  }

  void _scheduleLocalNotification(id, title, body, date) {
    // final androidDetails = new AndroidNotificationDetails(
    //     'main', cfg.configs['title'], '',
    //     importance: Importance.Max, priority: Priority.High);
    // NotificationDetails platformChannelSpecifics =
    //     new NotificationDetails(androidDetails, IOSNotificationDetails());
    // _localNotifications.schedule(
    //     id, title, body, date, platformChannelSpecifics);
  }

  void _unscheduleLocalNotification(id) {
    // _localNotifications.cancel(id);
  }

  // Handler for video calls
  void _joinVideoCall(String channelName, BuildContext context,
      FlutterWebviewPlugin plg, dynamic args) {
    if (channelName.isNotEmpty) {
      // Push video page with given channel name
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallPage(
                channelName: channelName,
                webviewPlugin: plg,
                args: args,
              ),
        ),
      );
    }
  }

  // Handler for voice calls
  void _joinVoiceCall(String channelName, BuildContext context,
      FlutterWebviewPlugin plg, dynamic args) {
    if (channelName.isNotEmpty) {
      // Push voice call page with given channel name
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => CallPageVoice(
                channelName: channelName,
                webviewPlugin: plg,
                args: args,
              ),
        ),
      );
    }
  }

  // Handler for tracking position
  void _trackLocation() {
    Geolocator geolocator = Geolocator();
    LocationOptions locationOptions =
        LocationOptions(accuracy: LocationAccuracy.high, distanceFilter: 0);

    geolocator.getPositionStream(locationOptions).listen((Position position) {
      if (position != null) {
        Map<String, dynamic> pos = {
          "latitude": position.latitude,
          "longitude": position.longitude,
          "altitude": position.altitude,
          "speed": position.speed,
          "accuracy": position.accuracy
        };
        _invokeJavascriptCallback('onLocationData', jsonEncode(pos));
      } else {
        Map<String, dynamic> err = {
          "message": "Error: Enable location permissions!"
        };
        _invokeJavascriptCallback('onLocationError', jsonEncode(err));
      }
    });
  }

  void _scanBarcode() async {
    try {
      String barcode = await BarcodeScanner.scan();
      _invokeJavascriptCallback('onBarcodeData', barcode);
    } on Exception catch (e) {
      _invokeJavascriptCallback('onBarcodeError', e.toString());
    }
  }

  void _invokeJavascriptCallback(function, arg) {
    String js = 'if (typeof $function === \'function\') $function(\'$arg\')';
    _webviewPlugin.evalJavascript(js);
  }

  // Progress indicator with splashscreen
  Widget _buildInitialChild() {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/img/splash.jpg'),
          fit: BoxFit.cover,
        ),
      ),
      child: Center(
        child: SizedBox(
          height: 3.0,
          width: 120.0,
          child: StreamBuilder(
            stream: _progressStream,
            initialData: 0.0,
            builder: (_, snapshot) {
              return LinearProgressIndicator(
                value: snapshot.hasData ? snapshot.data : 0.0,
                backgroundColor: Color(0x22000000),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
              );
            },
          ),
        ),
      ),
    );
  }
}
