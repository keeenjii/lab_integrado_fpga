// For performing some operations asynchronously
import 'dart:async';
import 'dart:convert';

// For using PlatformException
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'SizeConfig.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Laboratório Integrado',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: BluetoothApp(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  // Initializing the Bluetooth connection state to be unknown
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  // Initializing a global key, as it would help us in showing a SnackBar later
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  // Get the instance of the Bluetooth
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  // Track the Bluetooth connection with the remote device
  BluetoothConnection connection;

  List<int> _deviceState;

  bool isDisconnecting = false;

  Map<String, Color> colors = {
    'onBorderColor': Colors.green,
    'offBorderColor': Colors.red,
    'neutralBorderColor': Colors.transparent,
    'onTextColor': Colors.green[700],
    'offTextColor': Colors.red[700],
    'neutralTextColor': Colors.blue,
  };

  // To track whether the device is still connected to Bluetooth
  bool get isConnected => connection != null && connection.isConnected;

  List<BluetoothDevice> _devicesList = [];
  BluetoothDevice _device;
  bool _connected = false;
  bool _isButtonUnavailable = false;

  @override
  void initState() {
    super.initState();

    // Get current state
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    _deviceState = List.filled(17, 0); // neutral

    // If the bluetooth of the device is not enabled,
    // then request permission to turn on bluetooth
    // as the app starts up
    enableBluetooth();

    // Listen for further state changes
    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_OFF) {
          _isButtonUnavailable = true;
        }
        getPairedDevices();
      });
    });
  }

  @override
  void dispose() {
    // Avoid memory leak and disconnect
    if (isConnected) {
      isDisconnecting = true;
      connection.dispose();
      connection = null;
    }

    super.dispose();
  }

  Future<void> enableBluetooth() async {
    _bluetoothState = await FlutterBluetoothSerial.instance.state;

    if (_bluetoothState == BluetoothState.STATE_OFF) {
      await FlutterBluetoothSerial.instance.requestEnable();
      await getPairedDevices();
      return true;
    } else {
      await getPairedDevices();
    }
    return false;
  }

  Future<void> getPairedDevices() async {
    List<BluetoothDevice> devices = [];

    try {
      devices = await _bluetooth.getBondedDevices();
    } on PlatformException {
      print("Error");
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _devicesList = devices;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return MaterialApp(
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text("Remote FPGA input display"),
          centerTitle: true,
          backgroundColor: Colors.green,
          actions: <Widget>[
            TextButton.icon(
              icon: Icon(
                Icons.refresh,
                color: Colors.white,
              ),
              label: Text(
                "Refresh",
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
              onPressed: () async {
                // So, that when new devices are paired
                // while the app is running, user can refresh
                // the paired devices list.
                await getPairedDevices().then((_) {
                  show('Lista de dispositivos atualizada');
                });
              },
            ),
          ],
        ),
        body: Container(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              Visibility(
                visible: _isButtonUnavailable &&
                    _bluetoothState == BluetoothState.STATE_ON,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.yellow,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(left: SizeConfig.blockSize*10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Habilitar Bluetooth',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: SizeConfig.blockSize * 10,
                        ),
                      ),
                    ),
                    Switch(
                      value: _bluetoothState.isEnabled,
                      onChanged: (bool value) {
                        future() async {
                          if (value) {
                            await FlutterBluetoothSerial.instance
                                .requestEnable();
                          } else {
                            await FlutterBluetoothSerial.instance
                                .requestDisable();
                          }

                          await getPairedDevices();
                          _isButtonUnavailable = false;

                          if (_connected) {
                            _disconnect();
                          }
                        }

                        future().then((_) {
                          setState(() {});
                        });
                      },
                    )
                  ],
                ),
              ),
              Stack(
                children: <Widget>[
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: EdgeInsets.only(left: SizeConfig.blockSize*8, right: SizeConfig.blockSize*8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              'Device:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            DropdownButton(
                              items: _getDeviceItems(),
                              onChanged: (value) =>
                                  setState(() => _device = value),
                              value: _devicesList.isNotEmpty ? _device : null,
                            ),
                            ElevatedButton(
                              onPressed: _isButtonUnavailable
                                  ? null
                                  : _connected ? _disconnect : _connect,
                              child:
                              Text(_connected ? 'Disconnect' : 'Connect'),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _switchFpga(1),
                          _switchFpga(2),
                          _switchFpga(3),
                          _buttonFpga(13),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _switchFpga(4),
                          _switchFpga(5),
                          _switchFpga(6),
                          _buttonFpga(14),

                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _switchFpga(7),
                          _switchFpga(8),
                          _switchFpga(9),
                          _buttonFpga(15),

                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          _switchFpga(10),
                          _switchFpga(11),
                          _switchFpga(12),
                          _buttonFpga(16),

                        ],
                      ),
                    ],
                  ),
                  Container(
                    color: Colors.green,
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(SizeConfig.blockSize * 10),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(height: SizeConfig.blockSize * 3),
                        ElevatedButton(
                          child: Text("Bluetooth Settings"),
                          onPressed: () {
                            FlutterBluetoothSerial.instance.openSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  // Create the List of devices to be shown in Dropdown Menu
  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devicesList.isEmpty) {
      items.add(DropdownMenuItem(
        child: Text('NONE'),
      ));
    } else {
      _devicesList.forEach((device) {
        items.add(DropdownMenuItem(
          child: Text(device.name),
          value: device,
        ));
      });
    }
    return items;
  }

  void _connect() async {
    setState(() {
      _isButtonUnavailable = true;
    });
    if (_device == null) {
      show('No device selected');
    } else {
      if (!isConnected) {
        await BluetoothConnection.toAddress(_device.address)
            .then((_connection) {
          print('Connected to the device');
          connection = _connection;
          setState(() {
            _connected = true;
          });

          connection.input.listen(null).onDone(() {
            if (isDisconnecting) {
              print('Disconnecting locally!');
            } else {
              print('Disconnected remotely!');
            }
            if (this.mounted) {
              setState(() {});
            }
          });
        }).catchError((error) {
          print('Cannot connect, exception occurred');
          print(error);
        });
        show('Device connected');

        setState(() => _isButtonUnavailable = false);
      }
    }
  }

  void _disconnect() async {
    setState(() {
      _isButtonUnavailable = true;
      _deviceState = List.filled(17, 0);
    });

    await connection.close();
    show('Device disconnected');
    if (!connection.isConnected) {
      setState(() {
        _connected = false;
        _isButtonUnavailable = false;
      });
    }
  }

  void _sendOnMessageToBluetooth(int id) async {
    connection.output.add(utf8.encode("${String.fromCharCode(id + 32)}" + "\r\n"));
    await connection.output.allSent;
    show('Device Turned On');
    setState(() {
      _deviceState[id] = 1; // device on
    });
  }

  void _sendOffMessageToBluetooth(int id) async {
    connection.output.add(utf8.encode("${String.fromCharCode(id + 32)}" + "\r\n"));
    await connection.output.allSent;
    show('Device Turned Off');
    setState(() {
      _deviceState[id] = -1; // device off
    });
  }

  void _sendMessage(int id) async {
    if (_deviceState[id] != 1)
       _sendOnMessageToBluetooth(id);
    else
      _sendOffMessageToBluetooth(id);
  }

  // Method to show a Snackbar,
  // taking message as the text
  Future show(
      String message, {
        Duration duration: const Duration(seconds: 3),
      }) async {
    await new Future.delayed(new Duration(milliseconds: 100));
    ScaffoldMessenger.of(context).showSnackBar(
      new SnackBar(
        content: new Text(
          message,
        ),
        duration: duration,
      ),
    );
  }

  Widget _switchFpga (int id) {
    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: Card(
        shape: RoundedRectangleBorder(
          side: new BorderSide(
            color: _deviceState[id] == 0
                ? colors['neutralBorderColor']
                : _deviceState[id] == 1
                ? colors['onBorderColor']
                : colors['offBorderColor'],
            width: 3,
          ),
          borderRadius: BorderRadius.circular(4.0),
        ),
        elevation: _deviceState[id] == 0 ? 4 : 0,
        child: Padding(
          padding: const EdgeInsets.all(0.5),
          child: Column(
            children: [
              TextButton(
                  child: _deviceState[id] == 1 ? Image (
                    image: AssetImage('assets/switchOn.png'),
                    height: 40,
                    width: 40,
                  )
                  : Image (
                    image: AssetImage('assets/switchOff.png'),
                    height: 40,
                    width: 40,
                  ),
                  onPressed: _connected ?
                  () => _sendMessage(id)
                      : null
                ),
              Text('SW$id')
            ],
          )
        ),
      ),
    );
  }

  Widget _buttonFpga (int id) {
    return Padding(
      padding: EdgeInsets.all(SizeConfig.blockSize * 2),
      child: Card(
        shape: RoundedRectangleBorder(
          side: new BorderSide(
            color: _deviceState[id] == 0
                ? colors['neutralBorderColor']
                : _deviceState[id] == 1
                ? colors['onBorderColor']
                : colors['offBorderColor'],
            width: 3,
          ),
          borderRadius: BorderRadius.circular(4.0),
        ),
        elevation: _deviceState[id] == 0 ? 4 : 0,
        child: Padding(
            padding: EdgeInsets.all(SizeConfig.blockSize * 5),
            child: Column(
              children: [
                GestureDetector(
                    child: _deviceState[id] == 1 ? Image (
                      image: AssetImage('assets/buttonOn.png'),
                      height: 40,
                      width: 40,
                    )
                        : Image (
                      image: AssetImage('assets/buttonOff.png'),
                      height: 40,
                      width: 40,
                    ),
                    onTapDown: (details){
                      if (_connected)
                          _sendMessage(id);
                    },
                    onTapUp: (details){
                      if (_connected)
                        _sendMessage(id);
                    },
                ),
                Text('B$id')
              ],
            )
        ),
      ),
    );
  }
}