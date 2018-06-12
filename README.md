# 仅更新部分IOS代码，新增内容说明

## 扫描广播获取设备MAC地址

需要设备在"kCBAdvDataManufacturerData"字段写入MAC地址信息，广播返回数据示例：
```json
{
    name: "band",
    id: "BD922605-1B07-4D55-8D09-B66653E51BBA", 
    rssi: -79,
    advertising: {
      kCBAdvDataManufacturerData: "ffffdf011ab5b9a7"
    }
}
```

## IOS系统已配对设备扫描连接

因为IOS系统自动连接已配对设备,所以扫描时默认无法扫描到,需要在扫描时自动检测是否存在已连接设备,如存在需要返回设备;如果将自动连接设备连接后直接登录,则js无法捕获连接断开事件，所以如果自动连接设备在扫描中返回后需要再次调用连接方法连接设备；
1. BLECentralPlugin.m中的BAND_SERVICE_UUID和BAND_DFU_SERVICE_UUID替换为设备的SERVICE_UUID。
```object-c
//手环数据Service UUID
NSString *const BAND_SERVICE_UUID = @"F6F10001-D1BE-483B-BA6C-217B45A9F94F";
//DFU升级Service UUID
NSString *const BAND_DFU_SERVICE_UUID=@"8E400001-F315-4F60-9FB8-838830DAEA50";
```

在蓝牙连接断开后再次连接的过程中，APP和系统同时开始扫描，但是在APP扫描过程中系统先自动连接了设备，也会导致IOS无法扫描到设备，处理方法是IOS循环5秒扫描。

2. js循环5秒扫描直至连接设备
```js
var MAC = "df:01:1a:b5:b9:a8";
var devConnected = false,scanTimer;
//获取MAC地址
function getMac(scanDevice){
    if(ionic.Platform.platform()=='android'){
      return scanDevice.id.toLowerCase();
    }else if(ionic.Platform.platform()=='ios'){
      if(scanDevice.advertising&&scanDevice.advertising.kCBAdvDataManufacturerData){
        var macStr = scanDevice.advertising.kCBAdvDataManufacturerData.substring(4).toLowerCase();
        if(macStr.length==12){
          return macStr.substr(0,2)+':'+macStr.substr(2,2)+':'+macStr.substr(4,2)+':'+macStr.substr(6,2)+':'+macStr.substr(8,2)+':'+macStr.substr(10,2);
        }else{
          return "";
        }
      }else{
        return "";
      }
    }
  }
// ios扫描定时器
function startScanTimer(){
    scanTimer = setTimeout(function(){
      ble.stopScan(function(){});
      startScanTimer();
    },6000);
    ble.scan([],5,function(device){
      //扫描到设备：JSON.stringify(device))
      if(getMac(device)==MAC.toLowerCase()||device.connected=="true"){
        clearTimeout(scanTimer);
        if(devConnected!=true){
            //连接绑定设备
        }
      }
    })
  }

//连接绑定设备
var connectDevice=function(){
    if(MAC&&devConnected!=true){
        //ios循环5s扫描
        if(ionic.Platform.platform()=="ios"){
          startScanTimer();
        }else if(ionic.Platform.platform()=="android"){
          ble.startScan([],function(device){
              //扫描到设备：JSON.stringify(device))
              if(getMac(device)==MAC.toLowerCase()){
                  //连接绑定设备
              }
          })
        }
    }
  }
```

## ios DFU升级

手环DFU升级功能，可与android插件[NordicDfuPlugin](https://gitee.com/shanquane/NordicDfuPlugin)配合使用。升级过程：
1. 写bootload命令 
2. 断开连接后扫描MAC地址+1的手环 
3. 连接后下载升级包，调用插件方法startDFU上传固件
有时候升级失败，如果扫描到绑定设备处于bootload状态则自动触发升级

### usage

参考：[NordicDfuPlugin](https://gitee.com/shanquane/NordicDfuPlugin)

example: (step 3)
```js
var targetPath = "";
var DeviceId = "BD922605-1B07-4D55-8D09-B66653E51BBA";
var dfuPlugin;
if(ionic.Platform.platform()=='android'){
  dfuPlugin = cordova.plugins.NordicDfuPlugin;
}else if(ionic.Platform.platform()=='ios'){
  dfuPlugin = ble;
}
if(dfuPlugin.startDFU){
    dfuPlugin.startDFU(DeviceId,"band",targetPath,function(){},function(msg){
        //升级失败：msg
    });
    //监控状态变化
    dfuPlugin.watchStateChanged(function(data){
        //{state:"DFU_COMPLETED","deviceAddress":"FC:CE:63:20:34:AD"}
        if(data.state=="DFU_COMPLETED"){
            //升级成功！
        }
    },function(err){
        //监控状态报错：err
    })
    //监控进度变化
    dfuPlugin.watchProgressChanged(function(data){
        //{"deviceAddress":"","percent":100,"speed":9.13,"avgSpeed":2.53,"currentPart":1,"partsTotal":1}
    },function(err){
        //监控进度失败：err
    })
}
```
