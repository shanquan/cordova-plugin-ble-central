//
//  BLECentralPlugin.m
//  BLE Central Cordova Plugin
//
//  (c) 2104-2016 Don Coleman
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import "BLECentralPlugin.h"
#import <Cordova/CDV.h>

@interface BLECentralPlugin() {
    NSDictionary *bluetoothStates;
}

- (CBPeripheral *)findPeripheralByUUID:(NSString *)uuid;
- (void)stopScanTimer:(NSTimer *)timer;
@property(nonatomic,strong)NSString*currentUuid;
@property(nonatomic,strong)NSString*DUFStatus;
@end

@implementation BLECentralPlugin

@synthesize manager;
@synthesize peripherals;

//手环数据Service UUID
NSString *const BAND_SERVICE_UUID = @"F6F10001-D1BE-483B-BA6C-217B45A9F94F";
//DFU升级Service UUID
NSString *const BAND_DFU_SERVICE_UUID=@"8E400001-F315-4F60-9FB8-838830DAEA50";

- (void)pluginInitialize {
    
    NSLog(@"Cordova BLE Central Plugin");
    NSLog(@"(c)2014-2016 Don Coleman");
    
    [super pluginInitialize];
    _DUFStatus=@"";
    
    peripherals = [NSMutableSet set];
    manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    
    connectCallbacks = [NSMutableDictionary new];
    connectCallbackLatches = [NSMutableDictionary new];
    readCallbacks = [NSMutableDictionary new];
    writeCallbacks = [NSMutableDictionary new];
    notificationCallbacks = [NSMutableDictionary new];
    stopNotificationCallbacks = [NSMutableDictionary new];
    bluetoothStates = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"unknown", @(CBCentralManagerStateUnknown),
                       @"resetting", @(CBCentralManagerStateResetting),
                       @"unsupported", @(CBCentralManagerStateUnsupported),
                       @"unauthorized", @(CBCentralManagerStateUnauthorized),
                       @"off", @(CBCentralManagerStatePoweredOff),
                       @"on", @(CBCentralManagerStatePoweredOn),
                       nil];
    readRSSICallbacks = [NSMutableDictionary new];
    
    // app从后台进入前台都会调用这个方法
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationBecomeActive) name:UIApplicationWillEnterForegroundNotification object:nil];
}

#pragma mark - Cordova Plugin Methods

- (void)connect:(CDVInvokedUrlCommand *)command {
    
    NSLog(@"connect");
    NSString *uuid = [command.arguments objectAtIndex:0];
    _currentUuid=uuid;
    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];
    
    if (peripheral) {
        NSLog(@"Connecting to peripheral with UUID : %@", uuid);
        
        [connectCallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
        [manager connectPeripheral:peripheral options:nil];
        
    } else {
        
        NSString *error = [NSString stringWithFormat:@"Could not find peripheral %@.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    
}

// disconnect: function (device_id, success, failure) {
- (void)disconnect:(CDVInvokedUrlCommand*)command {
    NSLog(@"disconnect");
    NSString *uuid = [command.arguments objectAtIndex:0];
    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];
    
    [connectCallbacks removeObjectForKey:uuid];
    
    if (peripheral && peripheral.state != CBPeripheralStateDisconnected) {
        [manager cancelPeripheralConnection:peripheral];
    }
    // always return OK
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

// read: function (device_id, service_uuid, characteristic_uuid, success, failure) {
- (void)read:(CDVInvokedUrlCommand*)command {
    NSLog(@"read");
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyRead];
    if (context) {
        
        CBPeripheral *peripheral = [context peripheral];
        CBCharacteristic *characteristic = [context characteristic];
        
        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        [readCallbacks setObject:[command.callbackId copy] forKey:key];
        
        [peripheral readValueForCharacteristic:characteristic];  // callback sends value
    }
    
}

// write: function (device_id, service_uuid, characteristic_uuid, value, success, failure) {
- (void)write:(CDVInvokedUrlCommand*)command {
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWrite];
    NSData *message = [command.arguments objectAtIndex:3]; // This is binary
    if (context) {
        
        if (message != nil) {
            
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
            [writeCallbacks setObject:[command.callbackId copy] forKey:key];
            
            // TODO need to check the max length
            [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithResponse];
            
            // response is sent from didWriteValueForCharacteristic
            
        } else {
            CDVPluginResult *pluginResult = nil;
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        }
    }
    
}

// writeWithoutResponse: function (device_id, service_uuid, characteristic_uuid, value, success, failure) {
- (void)writeWithoutResponse:(CDVInvokedUrlCommand*)command {
    NSLog(@"writeWithoutResponse");
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyWriteWithoutResponse];
    NSData *message = [command.arguments objectAtIndex:3]; // This is binary
    
    if (context) {
        CDVPluginResult *pluginResult = nil;
        if (message != nil) {
            CBPeripheral *peripheral = [context peripheral];
            CBCharacteristic *characteristic = [context characteristic];
            
            // TODO need to check the max length
            [peripheral writeValue:message forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
            
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"message was null"];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

// success callback is called on notification
// notify: function (device_id, service_uuid, characteristic_uuid, success, failure) {
- (void)startNotification:(CDVInvokedUrlCommand*)command {
    NSLog(@"registering for notification");
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyNotify]; // TODO name this better
    
    if (context) {
        CBPeripheral *peripheral = [context peripheral];
        CBCharacteristic *characteristic = [context characteristic];
        
        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        NSString *callback = [command.callbackId copy];
        [notificationCallbacks setObject: callback forKey: key];
        
        [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        
    }
    
}

// stopNotification: function (device_id, service_uuid, characteristic_uuid, success, failure) {
- (void)stopNotification:(CDVInvokedUrlCommand*)command {
    NSLog(@"stop notification");
    
    BLECommandContext *context = [self getData:command prop:CBCharacteristicPropertyNotify];
    if (context) {
        CBPeripheral *peripheral = [context peripheral];
        CBCharacteristic *characteristic = [context characteristic];
        
        NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
        NSString *callback = [command.callbackId copy];
        [stopNotificationCallbacks setObject: callback forKey: key];
        
        [peripheral setNotifyValue:NO forCharacteristic:characteristic];
        // callback sent from peripheral:didUpdateNotificationStateForCharacteristic:error:
        
    }
    
}

- (void)isEnabled:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult *pluginResult = nil;
    int bluetoothState = [manager state];
    
    BOOL enabled = bluetoothState == CBCentralManagerStatePoweredOn;
    
    if (enabled) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsInt:bluetoothState];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)scan:(CDVInvokedUrlCommand*)command {
    
    NSLog(@"scan");
    NSArray *arr1 = [manager retrieveConnectedPeripheralsWithServices:@[[CBUUID UUIDWithString:BAND_SERVICE_UUID]]];
    NSArray *arr2 = [manager retrieveConnectedPeripheralsWithServices:@[[CBUUID UUIDWithString:BAND_DFU_SERVICE_UUID]]];
    NSArray*arr = [arr1 arrayByAddingObjectsFromArray:arr2];
    NSSet* set = [NSSet setWithArray:arr];
    if([set count]>0){
        for (CBPeripheral* peripheral in arr1)
        {
            if (peripheral != nil)
            {
                [peripherals addObject:peripheral];
                NSMutableDictionary *peripheralDic = [NSMutableDictionary new];
                [peripheralDic setDictionary:[peripheral asDictionary]];
                [peripheralDic setValue:@"true" forKey:@"connected"];
                NSLog(@"autoConnected %@", peripheralDic);
//                [connectCallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
//                [manager connectPeripheral:peripheral options:nil];
                CDVPluginResult *pluginResult = nil;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:peripheralDic];
                [pluginResult setKeepCallbackAsBool:TRUE];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        }

    }else{
        discoverPeripherialCallbackId = [command.callbackId copy];
        
        NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
        NSNumber *timeoutSeconds = [command.arguments objectAtIndex:1];
        NSMutableArray *serviceUUIDs = [NSMutableArray new];
        
        for (int i = 0; i < [serviceUUIDStrings count]; i++) {
            CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
            [serviceUUIDs addObject:serviceUUID];
        }
        
        
        [manager scanForPeripheralsWithServices:serviceUUIDs options:nil];
        
        [NSTimer scheduledTimerWithTimeInterval:[timeoutSeconds floatValue]
                                         target:self
                                       selector:@selector(stopScanTimer:)
                                       userInfo:[command.callbackId copy]
                                        repeats:NO];
    }

    
}

- (void)startScan:(CDVInvokedUrlCommand*)command {
    NSLog(@"startScan");
    NSArray *arr1 = [manager retrieveConnectedPeripheralsWithServices:@[[CBUUID UUIDWithString:BAND_SERVICE_UUID]]];
    NSArray *arr2 = [manager retrieveConnectedPeripheralsWithServices:@[[CBUUID UUIDWithString:BAND_DFU_SERVICE_UUID]]];
    NSArray*arr = [arr1 arrayByAddingObjectsFromArray:arr2];
    NSSet* set = [NSSet setWithArray:arr];
    //存在已配对设备在扫描过程中与系统自动连接情况，此时APP无法发现设备，只能再次scan
    if([set count]>0){
        for (CBPeripheral* peripheral in arr1)
        {
            if (peripheral != nil)
            {
                [peripherals addObject:peripheral];
                NSMutableDictionary *peripheralDic = [NSMutableDictionary new];
                [peripheralDic setDictionary:[peripheral asDictionary]];
                [peripheralDic setValue:@"true" forKey:@"connected"];
                NSLog(@"autoConnected %@", peripheralDic);
//  如这里处理自动连接，将无法获取连接断开事件！
//                [connectCallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
//                [manager connectPeripheral:peripheral options:nil];
                CDVPluginResult *pluginResult = nil;
                pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:peripheralDic];
                [pluginResult setKeepCallbackAsBool:TRUE];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }
        }
    }else{
        discoverPeripherialCallbackId = [command.callbackId copy];
        NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
        NSMutableArray *serviceUUIDs = [NSMutableArray new];
        
        for (int i = 0; i < [serviceUUIDStrings count]; i++) {
            CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
            [serviceUUIDs addObject:serviceUUID];
        }
        
        [manager scanForPeripheralsWithServices:serviceUUIDs options:nil];
        
    }

}

- (void)startScanWithOptions:(CDVInvokedUrlCommand*)command {
    NSLog(@"startScanWithOptions");
    discoverPeripherialCallbackId = [command.callbackId copy];
    NSArray *serviceUUIDStrings = [command.arguments objectAtIndex:0];
    NSMutableArray *serviceUUIDs = [NSMutableArray new];
    NSDictionary *options = command.arguments[1];
    
    for (int i = 0; i < [serviceUUIDStrings count]; i++) {
        CBUUID *serviceUUID =[CBUUID UUIDWithString:[serviceUUIDStrings objectAtIndex: i]];
        [serviceUUIDs addObject:serviceUUID];
    }
    
    NSMutableDictionary *scanOptions = [NSMutableDictionary new];
    NSNumber *reportDuplicates = [options valueForKey: @"reportDuplicates"];
    if (reportDuplicates) {
        [scanOptions setValue:reportDuplicates
                       forKey:CBCentralManagerScanOptionAllowDuplicatesKey];
    }
    
    [manager scanForPeripheralsWithServices:serviceUUIDs options:scanOptions];
}

- (void)stopScan:(CDVInvokedUrlCommand*)command {
    
    NSLog(@"stopScan");
    
    [manager stopScan];
    
    if (discoverPeripherialCallbackId) {
        discoverPeripherialCallbackId = nil;
    }
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    
}


- (void)isConnected:(CDVInvokedUrlCommand*)command {
    
    CDVPluginResult *pluginResult = nil;
    CBPeripheral *peripheral = [self findPeripheralByUUID:[command.arguments objectAtIndex:0]];
    
    if (peripheral && peripheral.state == CBPeripheralStateConnected) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Not connected"];
    }
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startStateNotifications:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    if (stateCallbackId == nil) {
        stateCallbackId = [command.callbackId copy];
        int bluetoothState = [manager state];
        NSString *state = [bluetoothStates objectForKey:[NSNumber numberWithInt:bluetoothState]];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:state];
        [pluginResult setKeepCallbackAsBool:TRUE];
        NSLog(@"Start state notifications on callback %@", stateCallbackId);
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"State callback already registered"];
    }
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopStateNotifications:(CDVInvokedUrlCommand *)command {
    CDVPluginResult *pluginResult = nil;
    
    if (stateCallbackId != nil) {
        // Call with NO_RESULT so Cordova.js will delete the callback without actually calling it
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_NO_RESULT];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:stateCallbackId];
        stateCallbackId = nil;
    }
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)onReset {
    stateCallbackId = nil;
}

- (void)readRSSI:(CDVInvokedUrlCommand*)command {
    NSLog(@"readRSSI");
    NSString *uuid = [command.arguments objectAtIndex:0];
    
    CBPeripheral *peripheral = [self findPeripheralByUUID:uuid];
    
    if (peripheral && peripheral.state == CBPeripheralStateConnected) {
        [readRSSICallbacks setObject:[command.callbackId copy] forKey:[peripheral uuidAsString]];
        [peripheral readRSSI];
    } else {
        NSString *error = [NSString stringWithFormat:@"Need to be connected to peripheral %@ to read RSSI.", uuid];
        NSLog(@"%@", error);
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
}

#pragma mark - timers

-(void)stopScanTimer:(NSTimer *)timer {
    NSLog(@"stopScanTimer");
    
    [manager stopScan];
    
    if (discoverPeripherialCallbackId) {
        discoverPeripherialCallbackId = nil;
    }
}

#pragma mark - CBCentralManagerDelegate

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI {
    
    [peripherals addObject:peripheral];
    [peripheral setAdvertisementData:advertisementData RSSI:RSSI];
    
    if (discoverPeripherialCallbackId) {
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
        NSLog(@"Discovered %@", [peripheral asDictionary]);
        [pluginResult setKeepCallbackAsBool:TRUE];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:discoverPeripherialCallbackId];
    }
    
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    NSLog(@"Status of CoreBluetooth central manager changed %ld %@", (long)central.state, [self centralManagerStateToString: central.state]);
    
    if (central.state == CBCentralManagerStateUnsupported)
    {
        NSLog(@"=============================================================");
        NSLog(@"WARNING: This hardware does not support Bluetooth Low Energy.");
        NSLog(@"=============================================================");
    }
    
    if (stateCallbackId != nil) {
        CDVPluginResult *pluginResult = nil;
        NSString *state = [bluetoothStates objectForKey:@(central.state)];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:state];
        [pluginResult setKeepCallbackAsBool:TRUE];
        NSLog(@"Report Bluetooth state \"%@\" on callback %@", state, stateCallbackId);
        [self.commandDelegate sendPluginResult:pluginResult callbackId:stateCallbackId];
    }
    
    // check and handle disconnected peripherals
    for (CBPeripheral *peripheral in peripherals) {
        if (peripheral.state == CBPeripheralStateDisconnected) {
            [self centralManager:central didDisconnectPeripheral:peripheral error:nil];
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    
    
    NSLog(@"didConnectPeripheral");
    
    peripheral.delegate = self;
    
    // NOTE: it's inefficient to discover all services
    [peripheral discoverServices:nil];
    
    // NOTE: not calling connect success until characteristics are discovered
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    NSLog(@"didDisconnectPeripheral");
    
    NSString *connectCallbackId = [connectCallbacks valueForKey:[peripheral uuidAsString]];
    
    [connectCallbacks removeObjectForKey:[peripheral uuidAsString]];
    if (connectCallbackId) {
        
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:[peripheral asDictionary]];
        
        // add error info
        [dict setObject:@"Peripheral Disconnected" forKey:@"errorMessage"];
        if (error) {
            [dict setObject:[error localizedDescription] forKey:@"errorDescription"];
        }
        // remove extra junk
        [dict removeObjectForKey:@"rssi"];
        [dict removeObjectForKey:@"advertising"];
        [dict removeObjectForKey:@"services"];
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dict];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];
    }
    
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    
    NSLog(@"didFailToConnectPeripheral");
    
    NSString *connectCallbackId = [connectCallbacks valueForKey:[peripheral uuidAsString]];
    [connectCallbacks removeObjectForKey:[peripheral uuidAsString]];
    
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[peripheral asDictionary]];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];
    
}

#pragma mark CBPeripheralDelegate

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    
    NSLog(@"didDiscoverServices");
    
    // save the services to tell when all characteristics have been discovered
    NSMutableSet *servicesForPeriperal = [NSMutableSet new];
    [servicesForPeriperal addObjectsFromArray:peripheral.services];
    [connectCallbackLatches setObject:servicesForPeriperal forKey:[peripheral uuidAsString]];
    
    for (CBService *service in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:service]; // discover all is slow
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    
    NSLog(@"didDiscoverCharacteristicsForService");
    
    NSString *peripheralUUIDString = [peripheral uuidAsString];
    NSString *connectCallbackId = [connectCallbacks valueForKey:peripheralUUIDString];
    NSMutableSet *latch = [connectCallbackLatches valueForKey:peripheralUUIDString];
    
    [latch removeObject:service];
    
    if ([latch count] == 0) {
        // Call success callback for connect
        if (connectCallbackId) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:[peripheral asDictionary]];
            [pluginResult setKeepCallbackAsBool:TRUE];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:connectCallbackId];
        }
        [connectCallbackLatches removeObjectForKey:peripheralUUIDString];
    }
    
    NSLog(@"Found characteristics for service %@", service);
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSLog(@"Characteristic %@", characteristic);
    }
    
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"didUpdateValueForCharacteristic");
    
    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    NSString *notifyCallbackId = [notificationCallbacks objectForKey:key];
    
    if (notifyCallbackId) {
        NSData *data = characteristic.value; // send RAW data to Javascript
        
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:data];
        [pluginResult setKeepCallbackAsBool:TRUE]; // keep for notification
        [self.commandDelegate sendPluginResult:pluginResult callbackId:notifyCallbackId];
    }
    
    NSString *readCallbackId = [readCallbacks objectForKey:key];
    
    if(readCallbackId) {
        NSData *data = characteristic.value; // send RAW data to Javascript
        
        CDVPluginResult *pluginResult = nil;
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:data];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:readCallbackId];
        
        [readCallbacks removeObjectForKey:key];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    
    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    NSString *notificationCallbackId = [notificationCallbacks objectForKey:key];
    NSString *stopNotificationCallbackId = [stopNotificationCallbacks objectForKey:key];
    
    CDVPluginResult *pluginResult = nil;
    
    // we always call the stopNotificationCallbackId if we have a callback
    // we only call the notificationCallbackId on errors and if there is no stopNotificationCallbackId
    
    if (stopNotificationCallbackId) {
        
        if (error) {
            NSLog(@"%@", error);
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:stopNotificationCallbackId];
        [stopNotificationCallbacks removeObjectForKey:key];
        [notificationCallbacks removeObjectForKey:key];
        
    } else if (notificationCallbackId && error) {
        
        NSLog(@"%@", error);
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:notificationCallbackId];
    }
    
}


- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    // This is the callback for write
    
    NSString *key = [self keyForPeripheral: peripheral andCharacteristic:characteristic];
    NSString *writeCallbackId = [writeCallbacks objectForKey:key];
    
    if (writeCallbackId) {
        CDVPluginResult *pluginResult = nil;
        if (error) {
            NSLog(@"%@", error);
            pluginResult = [CDVPluginResult
                            resultWithStatus:CDVCommandStatus_ERROR
                            messageAsString:[error localizedDescription]
                            ];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:writeCallbackId];
        
        [writeCallbacks removeObjectForKey:key];
    }
    
}

- (void)peripheralDidUpdateRSSI:(CBPeripheral*)peripheral error:(NSError*)error {
    [self peripheral: peripheral didReadRSSI: [peripheral RSSI] error: error];
}

- (void)peripheral:(CBPeripheral*)peripheral didReadRSSI:(NSNumber*)rssi error:(NSError*)error {
    NSLog(@"didReadRSSI %@", rssi);
    
    NSString *key = [peripheral uuidAsString];
    NSString *readRSSICallbackId = [readRSSICallbacks objectForKey: key];
    if (readRSSICallbackId) {
        CDVPluginResult* pluginResult = nil;
        if (error) {
            NSLog(@"%@", error);
            pluginResult = [CDVPluginResult
                            resultWithStatus:CDVCommandStatus_ERROR
                            messageAsString:[error localizedDescription]];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                messageAsInt: [rssi integerValue]];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId: readRSSICallbackId];
        [readRSSICallbacks removeObjectForKey:readRSSICallbackId];
    }
}

#pragma mark - internal implemetation

- (CBPeripheral*)findPeripheralByUUID:(NSString*)uuid {
    
    CBPeripheral *peripheral = nil;
    
    for (CBPeripheral *p in peripherals) {
        
        NSString* other = p.identifier.UUIDString;
        NSLog(@"uuid   %@  %@",other,uuid);
        
        if ([uuid isEqualToString:other]) {
            peripheral = p;
            break;
        }
        // return peripheral;
    }
    return peripheral;
}

// RedBearLab
-(CBService *) findServiceFromUUID:(CBUUID *)UUID p:(CBPeripheral *)p
{
    for(int i = 0; i < p.services.count; i++)
    {
        CBService *s = [p.services objectAtIndex:i];
        if ([self compareCBUUID:s.UUID UUID2:UUID])
        return s;
    }
    
    return nil; //Service not found on this peripheral
}

// Find a characteristic in service with a specific property
-(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service prop:(CBCharacteristicProperties)prop
{
    NSLog(@"Looking for %@ with properties %lu", UUID, (unsigned long)prop);
    for(int i=0; i < service.characteristics.count; i++)
    {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ((c.properties & prop) != 0x0 && [c.UUID.UUIDString isEqualToString: UUID.UUIDString]) {
            return c;
        }
    }
    return nil; //Characteristic with prop not found on this service
}

// Find a characteristic in service by UUID
-(CBCharacteristic *) findCharacteristicFromUUID:(CBUUID *)UUID service:(CBService*)service
{
    NSLog(@"Looking for %@", UUID);
    for(int i=0; i < service.characteristics.count; i++)
    {
        CBCharacteristic *c = [service.characteristics objectAtIndex:i];
        if ([c.UUID.UUIDString isEqualToString: UUID.UUIDString]) {
            return c;
        }
    }
    return nil; //Characteristic not found on this service
}

// RedBearLab
-(int) compareCBUUID:(CBUUID *) UUID1 UUID2:(CBUUID *)UUID2
{
    char b1[16];
    char b2[16];
    [UUID1.data getBytes:b1];
    [UUID2.data getBytes:b2];
    
    if (memcmp(b1, b2, UUID1.data.length) == 0)
    return 1;
    else
    return 0;
}

// expecting deviceUUID, serviceUUID, characteristicUUID in command.arguments
-(BLECommandContext*) getData:(CDVInvokedUrlCommand*)command prop:(CBCharacteristicProperties)prop {
    NSLog(@"getData");
    
    CDVPluginResult *pluginResult = nil;
    
    NSString *deviceUUIDString = [command.arguments objectAtIndex:0];
    NSString *serviceUUIDString = [command.arguments objectAtIndex:1];
    NSString *characteristicUUIDString = [command.arguments objectAtIndex:2];
    
    CBUUID *serviceUUID = [CBUUID UUIDWithString:serviceUUIDString];
    CBUUID *characteristicUUID = [CBUUID UUIDWithString:characteristicUUIDString];
    
    CBPeripheral *peripheral = [self findPeripheralByUUID:deviceUUIDString];
    
    if (!peripheral) {
        
        NSLog(@"Could not find peripherial with UUID %@", deviceUUIDString);
        
        NSString *errorMessage = [NSString stringWithFormat:@"Could not find peripherial with UUID %@", deviceUUIDString];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        
        return nil;
    }
    
    CBService *service = [self findServiceFromUUID:serviceUUID p:peripheral];
    
    if (!service)
    {
        NSLog(@"Could not find service with UUID %@ on peripheral with UUID %@",
              serviceUUIDString,
              peripheral.identifier.UUIDString);
        
        
        NSString *errorMessage = [NSString stringWithFormat:@"Could not find service with UUID %@ on peripheral with UUID %@",
                                  serviceUUIDString,
                                  peripheral.identifier.UUIDString];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        
        return nil;
    }
    
    CBCharacteristic *characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service prop:prop];
    
    // Special handling for INDICATE. If charateristic with notify is not found, check for indicate.
    if (prop == CBCharacteristicPropertyNotify && !characteristic) {
        characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service prop:CBCharacteristicPropertyIndicate];
    }
    
    // As a last resort, try and find ANY characteristic with this UUID, even if it doesn't have the correct properties
    if (!characteristic) {
        characteristic = [self findCharacteristicFromUUID:characteristicUUID service:service];
    }
    
    if (!characteristic)
    {
        NSLog(@"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
              characteristicUUIDString,
              serviceUUIDString,
              peripheral.identifier.UUIDString);
        
        NSString *errorMessage = [NSString stringWithFormat:
                                  @"Could not find characteristic with UUID %@ on service with UUID %@ on peripheral with UUID %@",
                                  characteristicUUIDString,
                                  serviceUUIDString,
                                  peripheral.identifier.UUIDString];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        
        return nil;
    }
    
    BLECommandContext *context = [[BLECommandContext alloc] init];
    [context setPeripheral:peripheral];
    [context setService:service];
    [context setCharacteristic:characteristic];
    return context;
    
}

-(NSString *) keyForPeripheral: (CBPeripheral *)peripheral andCharacteristic:(CBCharacteristic *)characteristic {
    return [NSString stringWithFormat:@"%@|%@", [peripheral uuidAsString], [characteristic UUID]];
}

#pragma mark - util

- (NSString*) centralManagerStateToString: (int)state
{
    switch(state)
    {
        case CBCentralManagerStateUnknown:
        return @"State unknown (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateResetting:
        return @"State resetting (CBCentralManagerStateUnknown)";
        case CBCentralManagerStateUnsupported:
        return @"State BLE unsupported (CBCentralManagerStateResetting)";
        case CBCentralManagerStateUnauthorized:
        return @"State unauthorized (CBCentralManagerStateUnauthorized)";
        case CBCentralManagerStatePoweredOff:
        return @"State BLE powered off (CBCentralManagerStatePoweredOff)";
        case CBCentralManagerStatePoweredOn:
        return @"State powered up and ready (CBCentralManagerStatePoweredOn)";
        default:
        return @"State unknown";
    }
    
    return @"Unknown state";
}

#pragma mark - DFU
/******升级部分***********/

- (void)startDFU:(CDVInvokedUrlCommand *)command{
    startDFUCallbackId = command.callbackId;
    /*
     NSString* _callbackId; 回调时的id
     NSString* _className;  类名
     NSString* _methodName; 方法名
     NSArray* _arguments;   参数
     */
    if (command.arguments.count>0) {
        
        NSString* deviceUUIDString = [command.arguments objectAtIndex:0];
        NSString*DFUFilePath = [command.arguments objectAtIndex:2];
        
        CBPeripheral *peripheral = [self findPeripheralByUUID:deviceUUIDString];
        _initiator = [[DFUServiceInitiator alloc] initWithCentralManager:manager target:peripheral];
//        DFUServiceInitiator *initiator = [[DFUServiceInitiator alloc] initWithCentralManager:manager target:peripheral];
        self.selectedFirmware = [[DFUFirmware alloc]  initWithUrlToZipFile:[NSURL fileURLWithPath:DFUFilePath]];
        [_initiator withFirmware:self.selectedFirmware];
        _initiator.logger = self;
        _initiator.delegate = self;
        _initiator.progressDelegate = self;
        //开始升级
        self.controller = [_initiator start];
        
    }
    
}
-(void)applicationBecomeActive{
    //进入后台 继续升级
    if ([_DUFStatus isEqualToString:@"DFUStateUploading"]) {
        self.controller = [_initiator start];
    }
}
-(void)watchProgressChanged:(CDVInvokedUrlCommand *)command{
    dfuProgressCallbackId =command.callbackId;
}

-(void)watchStateChanged:(CDVInvokedUrlCommand *)command{
    dfuStateCallbackId=command.callbackId;
}



//更新进度
- (void)dfuProgressDidChangeFor:(NSInteger)part outOf:(NSInteger)totalParts to:(NSInteger)progress currentSpeedBytesPerSecond:(double)currentSpeedBytesPerSecond avgSpeedBytesPerSecond:(double)avgSpeedBytesPerSecond{
    int currentProgress=(int)(progress /totalParts);
    NSDictionary* obj = @{
                          @"percent": [NSString stringWithFormat:@"%d",currentProgress],
                          @"speed": [NSString stringWithFormat:@"%.2f",currentSpeedBytesPerSecond],
                          @"avgSpeed": [NSString stringWithFormat:@"%.2f",avgSpeedBytesPerSecond]
                          };
    
    CDVPluginResult *pluginResult = [CDVPluginResult
                                     resultWithStatus:CDVCommandStatus_OK
                                     messageAsDictionary:obj];
    
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:dfuProgressCallbackId];
    
}

-(void)logWith:(enum LogLevel)level message:(NSString *)message
{
        NSLog(@"log.%ld: %@", (long) level, message);
}

//更新进度状态  升级开始..升级中断..升级完成等状态
- (void)dfuStateDidChangeTo:(enum DFUState)state
{
    NSString*stateString=@"";
    
    switch (state) {
        case DFUStateConnecting:
        stateString=@"CONNECTING";
        break;
        case DFUStateStarting:
        //Starting DFU...
        stateString=@"DFU_PROCESS_STARTING";
        break;
        case DFUStateEnablingDfuMode:
        //Enabling DFU Bootloader...
        stateString=@"ENABLING_DFU_MODE";
        break;
        case DFUStateUploading:
        //Uploading...
        stateString=@"DFUStateUploading";
        break;
        case DFUStateValidating:
        //Validating...
        stateString=@"FIRMWARE_VALIDATING";
        
        break;
        case DFUStateDisconnecting:
        stateString=@"DEVICE_DISCONNECTING";
        //Disconnecting...
        break;
        case DFUStateCompleted:{
            stateString=@"DFU_COMPLETED";
            [[NSNotificationCenter defaultCenter] removeObserver:self];
            [self pluginInitialize];
            break;
        }
        case DFUStateAborted:
        stateString=@"DFU_ABORTED";
        //Upload aborted
        break;
        default:
        break;
    }
    NSLog(@"状态   %@",stateString);
    _DUFStatus=stateString;
    if (stateString) {
        NSDictionary* obj = @{
                              @"state": stateString
                              };
        
        CDVPluginResult *pluginResult = [CDVPluginResult
                                         resultWithStatus:CDVCommandStatus_OK
                                         messageAsDictionary:obj];
        [pluginResult setKeepCallbackAsBool:YES];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:dfuStateCallbackId];
        
    }
    
}
//升级error信息
- (void)dfuError:(enum DFUError)error didOccurWithMessage:(NSString * _Nonnull)message{
    NSLog(@"错误信息   %@",message);
    CDVPluginResult *pluginResult = [CDVPluginResult
                                     resultWithStatus:CDVCommandStatus_ERROR
                                     messageAsString:message];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:startDFUCallbackId];
}


@end
