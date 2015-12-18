//
//  ViewController.swift
//  AutoLockScreen
//
//  Created by Yuhei Miyazato on 12/15/15.
//  Copyright © 2015 mitolab. All rights reserved.
//

import Cocoa
import SocketIO
import RxSwift
import RxCocoa

class ViewModel {
    
    var socket:SocketIOClient?
    var hostUrlSeq = PublishSubject<String>()
    var sioConnectedSeq = PublishSubject<Bool>()
    var connectBtnSeq = PublishSubject<Bool>()
    var isSleeping = Variable<Bool>(false)
    var walkingCnt = Variable<Int>(0)
    
    let disposeBag = DisposeBag()
    
    func getPreviousHostUrl() {
        let sud = NSUserDefaults.standardUserDefaults()
        let storedHostUrl = sud.objectForKey(Consts.hostUrlKey) as! String?
        
        if let hostUrl = storedHostUrl {
            self.hostUrlSeq.on(.Next(hostUrl))
        }
    }
    
    func showAlertAndImmitateToggleButton(msg:String, content:String, viewController:ViewController) {
        dispatch_async(dispatch_get_main_queue(), {
            
            let alert = NSAlert()
            alert.messageText = msg
            alert.informativeText = content
            alert.runModal()
            
            viewController.connectBtn.state = NSOffState   // imitate button press
        })
    }
    
    func setupAndStartSocketIO(hostUrl:String, _ viewController:ViewController) {
        
        self.socket = SocketIOClient(socketURL: hostUrl)
        
        self.socket?.on("connect") { [unowned self] data, ack in
            self.sioConnectedSeq.on(.Next(true))
            self.socket?.emit("connected", Consts.appName)
        }
        
        self.socket?.on("error", callback: { [unowned self, unowned viewController] data, ack in
            self.showAlertAndImmitateToggleButton("SocketIO Error", content: "some error occured while connecting socket. Program automatically disconnect socket, please retry.", viewController: viewController)
            self.connectBtnSeq.on(.Next(false))
        })
        
        self.socket?.on("publish", callback: { [unowned self, unowned viewController] data, ack in
            //print("data: \(data)\n ack:\(ack)")
            let csvStr = data.first as! String
            viewController.dataLabel.stringValue = csvStr
            
            let comps = csvStr.componentsSeparatedByString(",")
            let isWalking = Int(comps[1])
            if !self.isSleeping.value && isWalking > 0 {
                self.walkingCnt.value++
            }
        })

/* automatically disconnect when another one(might be ios app) has disconnected
        self.socket?.on("exit", callback:  { [unowned self, unowned viewController] data, ack in
            if (data.first as! String) != Consts.appName && self.socket != nil {
                self.showAlertAndImmitateToggleButton("SocketIO Disconnectd", content: "Another one has disconnected from socket.io server.", viewController: viewController)
                self.connectBtnSeq.on(.Next(false))
            }
        })
*/
        self.socket?.on("disconnect", callback: { [unowned self, unowned viewController] data, ack in
            self.showAlertAndImmitateToggleButton("SocketIO Disconnectd", content: "I'm disconnected from socket.io server.", viewController: viewController)
        })
        
        self.socket?.connect()
    }
    
    func bindViews(controller:ViewController) {
        
        /* Bind Model -> View */
        self.hostUrlSeq
            .subscribeOn(MainScheduler.sharedInstance)
            .filter({ hostUrl in
                return hostUrl.characters.count > 0
            })
            .bindTo(controller.hostUrlTextField.rx_text)
            .addDisposableTo(self.disposeBag)
        
        self.connectBtnSeq
            .subscribeOn(MainScheduler.sharedInstance)
            .subscribeNext { [unowned self, unowned controller] currentState in
                
                if !currentState {
                    self.disconnect()
                    self.isSleeping.value = false
                } else {
                    
                    let hostUrl = controller.hostUrlTextField.stringValue
                    
                    self.setupAndStartSocketIO(hostUrl, controller)
                    
                    // Save current IP/Port
                    let sud = NSUserDefaults.standardUserDefaults()
                    sud.setValue(hostUrl, forKey: Consts.hostUrlKey)
                    sud.synchronize()
                }
                
            }.addDisposableTo(self.disposeBag)
        
        controller.connectBtn.rx_tap.map { [unowned controller] in
            return (controller.connectBtn.state == NSOnState) ?? false
        }
        .bindTo(self.connectBtnSeq)
        .addDisposableTo(self.disposeBag)

        combineLatest(self.walkingCnt, self.isSleeping) { walkCnt, isSleeping in
            return (walkCnt > Consts.walkThresholdNum && !isSleeping) ?? false
        }
        .subscribeOn(MainScheduler.sharedInstance)
        .subscribeNext { [unowned self] canSleep in
            
            if canSleep {
                // activate task
                let task = NSTask()
                task.launchPath = NSBundle.mainBundle().pathForResource("CGSession", ofType: nil)!
                task.arguments = ["-suspend"]
                task.launch()
                
                // reset parameters
                self.isSleeping.value = true
                self.walkingCnt.value = 0
            }
            
        }.addDisposableTo(self.disposeBag)
    }
    
    func disconnect() {
        self.socket?.disconnect()
        self.socket = nil
    }
}

class ViewController: NSViewController {

    @IBOutlet weak var dataLabel: NSTextField!
    @IBOutlet weak var hostUrlTextField: NSTextField!
    @IBOutlet weak var connectBtn: NSButton!
    
    let vm = ViewModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.vm.bindViews(self)
        self.vm.getPreviousHostUrl()
    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }
}

