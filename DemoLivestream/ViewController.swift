//
//  ViewController.swift
//  DemoLivestream
//
//  Created by Hà Nguyễn Đức on 2/24/18.
//  Copyright © 2018 DucHa. All rights reserved.
//

import HaishinKit
import UIKit
import AVFoundation
import Photos
import VideoToolbox
import TYLive2D
import Logboard

let sampleRate: Double = 44_100

class ExampleRecorderDelegate: DefaultAVMixerRecorderDelegate {
    override func didFinishWriting(_ recorder: AVMixerRecorder) {
        guard let writer: AVAssetWriter = recorder.writer else { return }
        PHPhotoLibrary.shared().performChanges({() -> Void in
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: writer.outputURL)
        }, completionHandler: { (_, error) -> Void in
            do {
                try FileManager.default.removeItem(at: writer.outputURL)
            } catch let error {
                print(error)
            }
        })
    }
}

final class ViewController: UIViewController {
    var rtmpConnection: RTMPConnection = RTMPConnection()
    var rtmpStream: RTMPStream!
    var sharedObject: RTMPSharedObject!
    var currentEffect: VisualEffect?
    
    @IBOutlet var lfView: GLLFView?
    @IBOutlet var currentFPSLabel: UILabel?
    @IBOutlet var publishButton: UIButton?
    @IBOutlet var pauseButton: UIButton?
    @IBOutlet var videoBitrateLabel: UILabel?
    @IBOutlet var videoBitrateSlider: UISlider?
    @IBOutlet var audioBitrateLabel: UILabel?
    @IBOutlet var zoomSlider: UISlider?
    @IBOutlet var audioBitrateSlider: UISlider?
    @IBOutlet var fpsControl: UISegmentedControl?
    @IBOutlet var effectSegmentControl: UISegmentedControl?
    @IBOutlet weak var viewToCapture: UIView!
    
    var currentPosition: AVCaptureDevice.Position = .back
    var mouthPoints = [Double]()
    let live2DView = TYLive2DView()
    var timer: Timer?
    let logger: Logboard = Logboard.with("com.rikkei.DemoLivestream")
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        rtmpStream = RTMPStream(connection: rtmpConnection)
        rtmpStream.syncOrientation = true
        rtmpStream.captureSettings = [
            "sessionPreset": AVCaptureSession.Preset.hd1280x720.rawValue,
            "continuousAutofocus": true,
            "continuousExposure": true
        ]
        rtmpStream.videoSettings = [
            "width": 720,
            "height": 1280
        ]
        rtmpStream.audioSettings = [
            "sampleRate": sampleRate
        ]
        rtmpStream.mixer.recorder.delegate = ExampleRecorderDelegate()
        
        videoBitrateSlider?.value = Float(RTMPStream.defaultVideoBitrate) / 1024
        audioBitrateSlider?.value = Float(RTMPStream.defaultAudioBitrate) / 1024
        
        setUpModel()
        showModelInBroadcaster()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var width: CGFloat!
        var height: CGFloat!
        let modelWidth = live2DView.canvasSize.width
        let modelHeight = live2DView.canvasSize.height
        let fullWidth = viewToCapture.bounds.width
        let fullHeight = viewToCapture.bounds.height
        
        if (fullHeight / fullWidth > modelHeight / modelWidth) {
            width = fullWidth
            height = width * modelHeight / modelWidth
        } else {
            height = fullHeight
            width = height * modelWidth / modelHeight
        }
        live2DView.frame = CGRect(x: (fullWidth - width) / 2.0, y: (fullHeight - height) / 2.0, width: width, height: height)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        logger.info("viewWillAppear")
        super.viewWillAppear(animated)
        rtmpStream.attachAudio(AVCaptureDevice.default(for: .audio)) { error in
            self.logger.warn(error.description)
        }
        //        rtmpStream.attachCamera(DeviceUtil.device(withPosition: currentPosition)) { error in
        //            logger.warn(error.description)
        //        }
        rtmpStream.attachScreen(ScreenCaptureSession(viewToCapture: viewToCapture), useScreenSize: true)
        rtmpStream.addObserver(self, forKeyPath: "currentFPS", options: NSKeyValueObservingOptions.new, context: nil)
        lfView?.attachStream(rtmpStream)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        logger.info("viewWillDisappear")
        super.viewWillDisappear(animated)
        rtmpStream.removeObserver(self, forKeyPath: "currentFPS")
        rtmpStream.close()
        rtmpStream.dispose()
    }
    
    @IBAction func rotateCamera(_ sender: UIButton) {
        logger.info("rotateCamera")
        let position: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        //        rtmpStream.attachCamera(DeviceUtil.device(withPosition: position)) { error in
        //            logger.warn(error.description)
        //        }
        rtmpStream.attachScreen(ScreenCaptureSession(viewToCapture: viewToCapture), useScreenSize: true)
        currentPosition = position
    }
    
    @IBAction func toggleTorch(_ sender: UIButton) {
        rtmpStream.torch = !rtmpStream.torch
    }
    
    @IBAction func on(slider: UISlider) {
        if slider == audioBitrateSlider {
            audioBitrateLabel?.text = "audio \(Int(slider.value))/kbps"
            rtmpStream.audioSettings["bitrate"] = slider.value * 1024
        }
        if slider == videoBitrateSlider {
            videoBitrateLabel?.text = "video \(Int(slider.value))/kbps"
            rtmpStream.videoSettings["bitrate"] = slider.value * 1024
        }
        if slider == zoomSlider {
            rtmpStream.setZoomFactor(CGFloat(slider.value), ramping: true, withRate: 5.0)
        }
    }
    
    @IBAction func on(pause: UIButton) {
        rtmpStream.togglePause()
    }
    
    @IBAction func on(close: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func on(publish: UIButton) {
        if publish.isSelected {
            UIApplication.shared.isIdleTimerDisabled = false
            rtmpConnection.close()
            rtmpConnection.removeEventListener(Event.RTMP_STATUS, selector: #selector(self.rtmpStatusHandler(_:)), observer: self)
            publish.setTitle("●", for: UIControlState())
            timer?.invalidate()
            timer = nil
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            rtmpConnection.addEventListener(Event.RTMP_STATUS, selector: #selector(self.rtmpStatusHandler(_:)), observer: self)
            rtmpConnection.connect(Preference.defaultInstance.uri!)
            publish.setTitle("■", for: UIControlState())
            timer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(updateMouthPoints), userInfo: nil, repeats: true)
        }
        publish.isSelected = !publish.isSelected
    }
    
    @objc func rtmpStatusHandler(_ notification: Notification) {
        let e: Event = Event.from(notification)
        if let data: ASObject = e.data as? ASObject, let code: String = data["code"] as? String {
            switch code {
            case RTMPConnection.Code.connectSuccess.rawValue:
                rtmpStream!.publish(Preference.defaultInstance.streamName!)
            // sharedObject!.connect(rtmpConnection)
            default:
                break
            }
        }
    }
    
    func tapScreen(_ gesture: UIGestureRecognizer) {
        if let gestureView = gesture.view, gesture.state == .ended {
            let touchPoint: CGPoint = gesture.location(in: gestureView)
            let pointOfInterest: CGPoint = CGPoint(x: touchPoint.x/gestureView.bounds.size.width,
                                                   y: touchPoint.y/gestureView.bounds.size.height)
            print("pointOfInterest: \(pointOfInterest)")
            rtmpStream.setPointOfInterest(pointOfInterest, exposure: pointOfInterest)
        }
    }
    
    @IBAction func onFPSValueChanged(_ segment: UISegmentedControl) {
        switch segment.selectedSegmentIndex {
        case 0:
            rtmpStream.captureSettings["fps"] = 15.0
        case 1:
            rtmpStream.captureSettings["fps"] = 30.0
        case 2:
            rtmpStream.captureSettings["fps"] = 60.0
        default:
            break
        }
    }
    
    @IBAction func onEffectValueChanged(_ segment: UISegmentedControl) {
        if let currentEffect: VisualEffect = currentEffect {
            let _: Bool = rtmpStream.unregisterEffect(video: currentEffect)
        }
        switch segment.selectedSegmentIndex {
        case 1:
            currentEffect = MonochromeEffect()
            let _: Bool = rtmpStream.registerEffect(video: currentEffect!)
        case 2:
            currentEffect = PronamaEffect()
            let _: Bool = rtmpStream.registerEffect(video: currentEffect!)
        default:
            break
        }
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if Thread.isMainThread {
            currentFPSLabel?.text = "\(rtmpStream.currentFPS)"
        }
    }
}

// MARK: Live2D
extension ViewController {
    func setUpModel() {
        let model = TYLive2DModel(plistPath: Bundle.main.path(forResource: "model", ofType: "plist", inDirectory: "Haru"))
        live2DView.load(model)
        viewToCapture.addSubview(live2DView)
    }
    
    func showModelInBroadcaster() {
        live2DView.startAnimation { (userTime) in
            let timeSec = Double(userTime) / 1000.0
            let t = timeSec * 2 * Double.pi
            
            let params = NSMutableDictionary()
            params.setValue(Double(0.5 + 0.5 * sin(t / 1.0)), forKey: "PARAM_BREATH")
            
            if let mouthOpenY = self.mouthPoints.first {
                self.mouthPoints.remove(at: 0)
                params.setValue(mouthOpenY, forKey: "PARAM_MOUTH_OPEN_Y")
                params.setValue((mouthOpenY * -2) + 1, forKey: "PARAM_MOUTH_FORM")
            }
            self.live2DView.setParamsWith(params as! [String: NSNumber])
        }
    }
    
    @objc func updateMouthPoints() {
//        let averagePower = pow(10.0, -Double(arc4random() % 4))
        let averagePower = Double(arc4random() % 9 + 1) / 10.0
        mouthPoints.append(averagePower)
    }
}
