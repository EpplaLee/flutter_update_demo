import 'dart:io';
import 'dart:ui';
import 'dart:isolate';
import 'package:open_file/open_file.dart';
import 'package:dio/dio.dart';
import 'package:package_info/package_info.dart';
import 'package:device_info/device_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:dare_devil/utils/constants.dart' as Constants;


ReceivePort _port = ReceivePort();

class AppInfo {
  AppInfo();

  String version;

  AppInfo.fromJson(Map<String, dynamic> json)
    : version = json['version'];
}


class CheckUpdate {
  static String _downloadPath = '';
  static String _filename = 'YOUR_APP.apk';
  static String _taskId = '';

  check(Function showDialog) async {
    bool hasNewVersion = await _checkVersion();
    if(!hasNewVersion) {
      return;
    }
    bool confirm = await showDialog();
    if(!confirm) {
      return;
    }
    // 判断系统，ios跳转app store，安卓下载新的apk
    if(Platform.isIOS) {
      // 跳转app store
    } else if( Platform.isAndroid) {
      await _prepareDownload();
      if(_downloadPath.isNotEmpty) {
        await download();
      }
    }
  }

  // 下载前的准备
  static Future<void> _prepareDownload() async {
    _downloadPath = (await _findLocalPath()) + '/Download';
    final savedDir = Directory(_downloadPath);
    bool hasExisted = await savedDir.exists();
    if (!hasExisted) {
      savedDir.create();
    }
    print('--------------------downloadPath: $downloadPath');
  }

  // 获取下载地址
  static Future<String> _findLocalPath() async {
    final directory = Platform.isAndroid
        ? await getExternalStorageDirectory()
        : await getApplicationDocumentsDirectory();
    return directory.path;
  }

  // 检查版本
  Future<bool> _checkVersion() async {
    // 使用请求库dio读取文件服务器存有版本号的json文件
    var res = await Dio().get('YOUR_HOST/version.json').catchError((e) {
      print('获取版本号失败----------' + e);
    });
    if(res.statusCode == 200) {
      // 解析json字符串
      AppInfo appInfo = AppInfo.fromJson(res.data);
      // 获取 PackageInfo class
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      // 比较版本号
      if(packageInfo.version.hashCode != appInfo.version.hashCode) {
        return true;
      }
    }
    return false;
  }

  // 检查权限
  static Future<bool> _checkPermission() async {
    if (Platform.isAndroid) {
      PermissionStatus permission = await PermissionHandler()
          .checkPermissionStatus(PermissionGroup.storage);
      if (permission != PermissionStatus.granted) {
        Map<PermissionGroup, PermissionStatus> permissions =
            await PermissionHandler()
              .requestPermissions([PermissionGroup.storage]);
        if (permissions[PermissionGroup.storage] == PermissionStatus.granted) {
          return true;
        }
      } else {
        return true;
      }
    } else {
      return true;
    }
    return false;
  }

  // 下载完成之后的回调
  static downloadCallback(id, status, progress) {
      final SendPort send = IsolateNameServer.lookupPortByName('downloader_send_port');
      send.send([id, status, progress]);
  }


  // 下载apk
  static Future<void> download() async {
    final bool _permissionReady = await _checkPermission();
    if(_permissionReady) {
      // final taskId = await downloadApk();
        IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
        _port.listen((dynamic data) async {
          String id = data[0];
          DownloadTaskStatus status = data[1];
          int progress = data[2];
          if(status == DownloadTaskStatus.complete) {
            // 更新弹窗提示，确认后进行安装
            OpenFile.open('$_downloadPath/$_filename');
            print('==============_installApkz: $_taskId  $_downloadPath /$_filename');
          }
        });
      FlutterDownloader.registerCallback(downloadCallback);
      _taskId = await FlutterDownloader.enqueue(
        url: '${Constants.asset_path}/dare_devil/app_release.apk',
        savedDir: _downloadPath,
        fileName: _filename,
        showNotification: true,
        openFileFromNotification: true
      );
    } else {
      print('-----------------未授权');
    }
  }

  // 安装apk
  static Future<void> installApk() async {
    await OpenFile.open('$_downloadPath/$_filename');
  }

}