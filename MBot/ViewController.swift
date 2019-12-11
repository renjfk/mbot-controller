//
//  ViewController.swift
//  MBot
//
//  Created by Soner Koksal on 2.12.2019.
//  Copyright © 2019 renjfk. All rights reserved.
//

import UIKit
import GameController
import Alertift
import NotificationCenter
import FontAwesome_swift
import BlueCapKit
import CoreBluetooth

var idx = 0
var getDeviceIndex = [GetDevice?](repeating: nil, count: 255)

let BOT_SERVICE = CBUUID(string: "FFE1")
let BOT_NOTIFY = CBUUID(string: "FFE2")
let BOT_WRITE = CBUUID(string: "FFE3")

enum DataType: UInt8 {
    case BYTE = 1
    case FLOAT = 2
    case SHORT = 3
    case STRING = 4
    case DOUBLE = 5
}

enum Action {
    case GET(device: GetDevice)
    case RUN(device: RunDevice)
    case RESET
    case START

    public var data: Data {
        var data = Data([0xFF, 0x55, UInt8(idx)])
        switch self {
        case .GET(let device):
            getDeviceIndex[idx] = device
            data.append(0x01)
            data.append(device.data)
            break
        case .RUN(let device):
            data.append(0x02)
            data.append(device.data)
            break
        case .RESET:
            data.append(0x04)
            break
        case .START:
            data.append(0x05)
            break
        }
        data.insert(UInt8(data.count - 2), at: 2)
        idx = (idx + 1) % 255
        return data
    }
}

enum GetDevice: Equatable {
    case VERSION
    case ULTRASONIC_SENSOR(port: Port)
    case LIGHT_SENSOR(port: Port)
    case IR
    case IR_REMOTE(code: UInt8)
    case IR_REMOTE_CODE
    case LINE_FOLLOWER(port: Port)

    public var data: Data {
        switch self {
        case .VERSION:
            return Data([0x00])
        case .ULTRASONIC_SENSOR(let port):
            return Data([0x01, port.rawValue])
        case .LIGHT_SENSOR(let port):
            return Data([0x03, port.rawValue])
        case .IR:
            return Data([0x0D])
        case .IR_REMOTE(let code):
            return Data([0x0E, code])
        case .IR_REMOTE_CODE:
            return Data([0x12])
        case .LINE_FOLLOWER(let port):
            return Data([0x11, port.rawValue])
        }
    }
}

enum RunDevice {
    case JOYSTICK(m1: Int16, m2: Int16)
    case RGB_LED(port: Port, slot: UInt8, idx: UInt8, red: UInt8, green: UInt8, blue: UInt8)
    case MOTOR(port: Port, speed: Int16)
    case IR(data: Data)
    case TONE(frequency: Note, duration: UInt16)

    public var data: Data {
        switch self {
        case .JOYSTICK(let m1, let m2):
            return Data([0x05, UInt8(m1 & 0xFF), UInt8(m1 >> 8 & 0xFF), UInt8(m2 & 0xFF), UInt8(m2 >> 8 & 0xFF)])
        case .RGB_LED(let port, let slot, let idx, let red, let green, let blue):
            return Data([0x08, port.rawValue, slot, idx, red, green, blue])
        case .IR(let data):
            var dat = Data([0x0D])
            dat.append(data)
            return dat
        case .MOTOR(let port, let speed):
            return Data([0x0A, port.rawValue, UInt8(speed & 0xFF), UInt8(speed >> 8 & 0xFF)])
        case .TONE(let frequency, let duration):
            return Data([0x22, UInt8(frequency.rawValue & 0xFF), UInt8(frequency.rawValue >> 8 & 0xFF), UInt8(duration & 0xFF), UInt8(duration >> 8 & 0xFF)])
        }
    }
}

enum Port: UInt8 {
    case PORT_0 = 0x00
    case PORT_1 = 0x01
    case PORT_2 = 0x02
    case PORT_3 = 0x03
    case PORT_4 = 0x04
    case M1 = 0x09
    case M2 = 0x0A
}

enum Note: UInt16 {
    case C2 = 65; case D2 = 73; case E2 = 82; case F2 = 87; case G2 = 98; case A2 = 110; case B2 = 123
    case C3 = 131; case D3 = 147; case E3 = 165; case F3 = 175; case G3 = 196; case A3 = 220; case B3 = 247
    case C4 = 262; case D4 = 294; case E4 = 330; case F4 = 349; case G4 = 392; case A4 = 440; case B4 = 494
    case C5 = 523; case D5 = 587; case E5 = 658; case F5 = 698; case G5 = 784; case A5 = 880; case B5 = 988
    case C6 = 1047; case D6 = 1175; case E6 = 1319; case F6 = 1397; case G6 = 1568; case A6 = 1760; case B6 = 1976
    case C7 = 2093; case D7 = 2349; case E7 = 2637; case F7 = 2794; case G7 = 3136; case A7 = 3520; case B7 = 3951
    case C8 = 4186
}

enum AppError: Error {
    case serviceNotFound
    case invalidState
    case resetting
    case poweredOff
    case unknown
    case unlikely
}

class ViewController: UIViewController {
    @IBOutlet weak var controllerBtn: UIButton!
    @IBOutlet weak var robotBtn: UIButton!

    var controllerIconGreen: UIImage?
    var controllerIconBlue: UIImage?
    var robotIconGreen: UIImage?
    var robotIconBlue: UIImage?

    let manager = CentralManager(options: [CBCentralManagerOptionRestoreIdentifierKey: "B2B8E364-2649-487A-A481-7D5D84D5EFB9"])
    var onComplete: DispatchWorkItem?
    var peripheral: Peripheral?
    var receiver: Characteristic?
    var sender: Characteristic?
    var mBotVersion: String?
    var beep = false
    var stepBack = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        controllerIconGreen = UIImage.fontAwesomeIcon(name: .gamepad, style: .solid, textColor: .systemGreen, size: CGSize(width: 40, height: 40))
        controllerIconBlue = UIImage.fontAwesomeIcon(name: .gamepad, style: .solid, textColor: .systemBlue, size: CGSize(width: 40, height: 40))
        controllerBtn.setImage(controllerIconBlue, for: .normal)

        robotIconGreen = UIImage.fontAwesomeIcon(name: .robot, style: .solid, textColor: .systemGreen, size: CGSize(width: 40, height: 40))
        robotIconBlue = UIImage.fontAwesomeIcon(name: .robot, style: .solid, textColor: .systemBlue, size: CGSize(width: 40, height: 40))
        robotBtn.setImage(robotIconBlue, for: .normal)
        robotBtn.setTitle("Scanning for robot...", for: .disabled)
        var blink = true
        _ = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            if self.beep {
                _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .C6, duration: 400)).data)
                if blink {
                    _ = self.sender?.write(data: Action.RUN(device: .RGB_LED(port: .PORT_0, slot: 2, idx: 0, red: 30, green: 0, blue: 0)).data)
                } else {
                    _ = self.sender?.write(data: Action.RUN(device: .RGB_LED(port: .PORT_0, slot: 2, idx: 0, red: 0, green: 0, blue: 0)).data)
                }
                blink = !blink
            } else if !blink {
                _ = self.sender?.write(data: Action.RUN(device: .RGB_LED(port: .PORT_0, slot: 2, idx: 0, red: 0, green: 0, blue: 0)).data)
                blink = !blink
            }
        }
        var motion = 0
        _ = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            if self.stepBack > 0 {
                motion = (motion + 1) % 4
                switch motion {
                case 1:
                    _ = self.sender?.write(data: Action.RUN(device: .JOYSTICK(m1: 250, m2: -100)).data)
                    break
                case 3:
                    _ = self.sender?.write(data: Action.RUN(device: .JOYSTICK(m1: 100, m2: -250)).data)
                    break
                default:
                    _ = self.sender?.write(data: Action.RUN(device: .JOYSTICK(m1: 0, m2: 0)).data)
                }
                self.stepBack -= 1
            } else if motion == 1 || motion == 3 {
                _ = self.sender?.write(data: Action.RUN(device: .JOYSTICK(m1: 0, m2: 0)).data)
                motion = (motion + 1) % 4
            }
        }
    }

    @IBAction func handleController(_ btn: UIButton) {
        let controller = GCController.controllers().first
        if controller != nil {
            btn.isEnabled = false
            btn.setImage(controllerIconGreen, for: .normal)
            btn.setTitle("Connected to controller", for: .normal)
            var command: DispatchWorkItem?
            controller?.extendedGamepad?.leftThumbstick.valueChangedHandler = { pad, x, y in
                command?.cancel()
                command = DispatchWorkItem {
                    let speed1 = Int16(255 * y * (x < 0 ? x + 1 : 1))
                    let speed2 = Int16(255 * y * (x > 0 ? 1 - x : 1))
                    if self.stepBack == 0 {
                        if y < 0 {
                            self.beep = true
                        } else {
                            self.beep = false
                        }
                        _ = self.sender?.write(data: Action.RUN(device: .JOYSTICK(m1: -speed1, m2: speed2)).data)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: command!)
            }
            let randomLed = {
                _ = self.sender?.write(data: Action.RUN(device: .RGB_LED(port: .PORT_0, slot: 2, idx: UInt8.random(in: 1...2), red: UInt8.random(in: 0...20), green: UInt8.random(in: 0...20), blue: UInt8.random(in: 0...20))).data)
            }
            controller?.extendedGamepad?.buttonX.valueChangedHandler = { input, v, b in
                if b {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .C5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.buttonY.valueChangedHandler = { input, v, b in
                if b {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .D5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.buttonA.valueChangedHandler = { input, v, b in
                if b {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .E5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.buttonB.valueChangedHandler = { input, v, b in
                if b {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .F5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.leftShoulder.valueChangedHandler = { input, v, b in
                if b {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .G5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.rightShoulder.valueChangedHandler = { input, v, b in
                if b {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .A5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.leftTrigger.valueChangedHandler = { input, v, b in
                if b && v == 1 {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .B5, duration: 200)).data)
                    _ = randomLed()
                }
            }
            controller?.extendedGamepad?.rightTrigger.valueChangedHandler = { input, v, b in
                if b && v == 1 {
                    _ = self.sender?.write(data: Action.RUN(device: .TONE(frequency: .C6, duration: 200)).data)
                    _ = randomLed()
                }
            }

            NotificationCenter.default.addObserver(forName: NSNotification.Name.GCControllerDidDisconnect, object: nil, queue: nil) { notification in
                _ = self.sender?.write(data: Action.RESET.data)
                btn.isEnabled = true
                btn.setImage(self.controllerIconBlue, for: .normal)
                btn.setTitle("Connect to controller", for: .normal)
            }
        } else {
            Alertift.alert(title: "Error", message: "No available controller found!").action(.default("OK")).show()
        }
    }

    @IBAction func handleRobot(_ btn: UIButton) {
        if peripheral?.state == .connected {
            peripheral?.disconnect()
            btn.setTitle("Connect to robot", for: .normal)
            btn.setImage(self.robotIconBlue, for: .normal)
        } else {
            btn.isEnabled = false
            let scanFuture = manager.whenStateChanges().flatMap { state -> FutureStream<Peripheral> in
                switch state {
                case .poweredOn:
                    return self.manager.startScanning(timeout: 10)
                case .unauthorized, .unsupported:
                    throw AppError.invalidState
                case .resetting:
                    throw AppError.resetting
                case .poweredOff:
                    throw AppError.poweredOff
                case .unknown:
                    throw AppError.unknown
                }
            }

            scanFuture.onComplete { v in
                self.onComplete?.cancel()
                self.onComplete = DispatchWorkItem {
                    btn.isEnabled = !self.manager.isScanning
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: self.onComplete!)
            }

            var ultrasonic: Timer?
            scanFuture.flatMap { peripheral -> FutureStream<Void> in
                if peripheral.name.starts(with: "Makeblock_") {
                    self.manager.stopScanning()
                    self.peripheral = peripheral
                    return peripheral.connect(connectionTimeout: 10)
                } else {
                    return FutureStream()
                }
            }.flatMap { () -> Future<Void> in
                guard let peripheral = self.peripheral else {
                    throw AppError.unlikely
                }
                return peripheral.discoverServices([BOT_SERVICE])
            }.flatMap { () -> Future<Void> in
                guard let peripheral = self.peripheral, let service = peripheral.services(withUUID: BOT_SERVICE)?.first else {
                    throw AppError.serviceNotFound
                }

                return service.discoverAllCharacteristics()
            }.flatMap { () -> Future<Void> in
                guard let peripheral = self.peripheral, let service = peripheral.services(withUUID: BOT_SERVICE)?.first else {
                    throw AppError.serviceNotFound
                }

                guard let receiver = service.characteristics(withUUID: BOT_NOTIFY)?.first,
                      let sender = service.characteristics(withUUID: BOT_WRITE)?.first else {
                    throw AppError.serviceNotFound
                }

                self.receiver = receiver
                self.sender = sender

                return receiver.startNotifying()
            }.flatMap { () -> Future<Void> in
                btn.setTitle("Disconnect from robot", for: .normal)
                btn.setImage(self.robotIconGreen, for: .normal)

                let checkVersion = DispatchWorkItem {
                    self.peripheral?.disconnect()
                    Alertift.alert(title: "Error", message: "Connected device does not seem to have mBot protocol supported firmware installed!").action(.default("OK")).show()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: checkVersion)

                var buffer = Data()
                _ = self.receiver?.receiveNotificationUpdates().flatMap { (data: Data?) -> Future<Void> in
                    objc_sync_enter(buffer)

                    buffer.append(data!)

                    var i = 0;
                    var start = -1;
                    while i < buffer.count {
                        if i > 0 {
                            if buffer[i] == 0x55 && buffer[i - 1] == 0xFF && start < 0 {
                                start = i - 1
                            } else if buffer[i] == 0x0A && buffer[i - 1] == 0x0D && start > -1 {
                                if i - start > 4 {
                                    let device = getDeviceIndex[Int(buffer[start + 2])]
                                    switch DataType(rawValue: buffer[start + 3])! {
                                    case .BYTE:
                                        _ = buffer[start + 4]
                                        break
                                    case .FLOAT:
                                        let v = buffer.subdata(in: start + 4..<start + 8).withUnsafeBytes {
                                            $0.load(as: Float.self)
                                        }
                                        if device == .ULTRASONIC_SENSOR(port: .PORT_3) && v < 10 && self.stepBack == 0 {
                                            self.stepBack = 10
                                        }
                                        break
                                    case .SHORT:
                                        _ = buffer.subdata(in: start + 4..<start + 6).withUnsafeBytes {
                                            $0.load(as: UInt16.self)
                                        }
                                        break
                                    case .STRING:
                                        if device == .VERSION {
                                            ultrasonic = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
                                                _ = self.sender?.write(data: Action.GET(device: .ULTRASONIC_SENSOR(port: .PORT_3)).data)
                                            }
                                            let s = String(data: buffer.subdata(in: start + 5..<start + Int(buffer[start + 4]) + 5), encoding: .ascii)
                                            self.mBotVersion = s
                                            btn.setTitle(String(format: "Disconnect from robot (%@)", s!), for: .normal)
                                            checkVersion.cancel()
                                        }
                                        break
                                    case .DOUBLE:
                                        _ = buffer.subdata(in: start + 4..<start + 12).withUnsafeBytes {
                                            $0.load(as: Double.self)
                                        }
                                        break
                                    }
                                }
                                buffer.removeSubrange(start...i)
                                i = i - start
                                start = -1
                            }
                        }
                        i += 1
                    }

                    objc_sync_exit(buffer)

                    return Future();
                }

                return (self.sender?.write(data: Action.GET(device: .VERSION).data))!
            }.flatMap { () -> Future<Void> in
                (self.sender?.write(data: Action.RESET.data))!
            }.onFailure { error in
                ultrasonic?.invalidate()
                btn.setTitle("Connect to robot", for: .normal)
                btn.setImage(self.robotIconBlue, for: .normal)
                switch error {
                case PeripheralError.forcedDisconnect:
                    break
                default:
                    Alertift.alert(title: "Error", message: error.localizedDescription).action(.default("OK")).show()
                }
            }
        }
    }
}
