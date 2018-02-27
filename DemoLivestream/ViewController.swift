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
    let recordSettings = [
        AVSampleRateKey: NSNumber(value: Float(44100.0)),
        AVFormatIDKey: NSNumber(value: Int32(kAudioFormatMPEG4AAC)),
        AVNumberOfChannelsKey: NSNumber(value: Int32(1)),
        AVEncoderAudioQualityKey:
            NSNumber(value: Int32(AVAudioQuality.max.rawValue))
    ]
    var meterTimer: Timer?
    
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
    var leftEyePoints = [Double]()
    var rightEyePoints = [Double]()
    
    let live2DView = TYLive2DView()
    let logger: Logboard = Logboard.with("com.rikkei.DemoLivestream")
    var audioRecorder: AVAudioRecorder?
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
        (childViewControllers.first as? CameraViewController)?.delegate = self
        setupAudioRecorder()
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
//            (childViewControllers.first as? CameraViewController)?.stop()
            startStopRecording()
        } else {
            UIApplication.shared.isIdleTimerDisabled = true
            rtmpConnection.addEventListener(Event.RTMP_STATUS, selector: #selector(self.rtmpStatusHandler(_:)), observer: self)
            rtmpConnection.connect(Preference.defaultInstance.uri!)
            publish.setTitle("■", for: UIControlState())
            startStopRecording()
//            (childViewControllers.first as? CameraViewController)?.start()
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
    func setupAudioRecorder() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
            try audioRecorder = AVAudioRecorder(url: directoryURL()!,
                                                settings: recordSettings)
            audioRecorder?.prepareToRecord()
            audioRecorder?.isMeteringEnabled = true
        } catch { }
    }
    
    func directoryURL() -> URL? {
        let folderPath = NSTemporaryDirectory()
        let soundFilePath = folderPath.appendingFormat("%.0f%@", Date.timeIntervalSinceReferenceDate * 1000.0, "audio.caf")
        let soundFileURL = URL(fileURLWithPath: soundFilePath)
        return soundFileURL
    }

    @objc func updateAudioMeter() {
        audioRecorder?.updateMeters()
        let averagePower = pow(10.0, (Double(audioRecorder?.averagePower(forChannel: 0) ?? -160) / 40))
        mouthPoints.append(averagePower)
    }
    
    func startStopRecording() {
        if let audioRecorder = audioRecorder, !audioRecorder.isRecording {
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(true)
                audioRecorder.record()
                meterTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(updateAudioMeter), userInfo: nil, repeats: true)
            } catch { }
        } else {
            meterTimer?.invalidate()
            meterTimer = nil
            audioRecorder?.stop()
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setActive(false)
            } catch { }
            mouthPoints.append(Double(0))
        }
    }
    
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
                print("Mouth: \(mouthOpenY)")
                params.setValue(mouthOpenY, forKey: "PARAM_MOUTH_OPEN_Y")
                params.setValue((mouthOpenY * -2) + 1, forKey: "PARAM_MOUTH_FORM")
            }
            if let leftEyeOpen = self.leftEyePoints.first {
                self.leftEyePoints.removeAll()
                params.setValue(leftEyeOpen, forKey: "PARAM_EYE_L_OPEN")
                print("Left: \(leftEyeOpen)")
            }
            if let rightEyeOpen = self.rightEyePoints.first {
                self.rightEyePoints.removeAll()
                params.setValue(rightEyeOpen, forKey: "PARAM_EYE_R_OPEN")
                print("Right: \(rightEyeOpen)")
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

extension ViewController: CameraViewControllerDelegate {
    func didReceiveLandmarks(_ landmarks: [Any]!) {
        if let landmarks = landmarks as? [NSValue] {
            let eyeRatio = calculateEyeRatio(landmarks: landmarks)
            leftEyePoints.append(eyeRatio.left)
            rightEyePoints.append(eyeRatio.right)
            
            let mouthRatio = calculateMouthRatio(landmarks: landmarks)
            mouthPoints.append(mouthRatio)
        }
    }
}

// Calculate facial ratio
extension ViewController {
    func calculateEyeRatio(landmarks: [NSValue]) -> (left: Double, right: Double) {
        // Left eye
        let point43 = landmarks[42].cgPointValue
        let point44 = landmarks[43].cgPointValue
        let point45 = landmarks[44].cgPointValue
        let point46 = landmarks[45].cgPointValue
        let point47 = landmarks[46].cgPointValue
        let point48 = landmarks[47].cgPointValue
        
        let leftRatio: Double = (euclideDistance(point1: point44, point2: point48) + euclideDistance(point1: point45, point2: point47)) / (2 * euclideDistance(point1: point43, point2: point46))
        
        // Right eye
        let point37 = landmarks[36].cgPointValue
        let point38 = landmarks[37].cgPointValue
        let point39 = landmarks[38].cgPointValue
        let point40 = landmarks[39].cgPointValue
        let point41 = landmarks[40].cgPointValue
        let point42 = landmarks[41].cgPointValue
        
        let rightRatio: Double = (euclideDistance(point1: point38, point2: point42) + euclideDistance(point1: point39, point2: point41)) / (2 * euclideDistance(point1: point37, point2: point40))
        return (standardizeEye(ratio: leftRatio), standardizeEye(ratio: rightRatio))
//        return (leftRatio, rightRatio)
    }
    
    func calculateMouthRatio(landmarks: [NSValue]) -> Double {
        let point61 = landmarks[60].cgPointValue
        let point62 = landmarks[61].cgPointValue
        let point63 = landmarks[62].cgPointValue
        let point64 = landmarks[63].cgPointValue
        let point65 = landmarks[64].cgPointValue
        let point66 = landmarks[65].cgPointValue
        let point67 = landmarks[66].cgPointValue
        let point68 = landmarks[67].cgPointValue
        
        let ratio = (euclideDistance(point1: point62, point2: point68) + euclideDistance(point1: point63, point2: point67) + euclideDistance(point1: point64, point2: point66)) / (3 * euclideDistance(point1: point61, point2: point65))
        return ratio
    }
    
    func euclideDistance(point1: CGPoint, point2: CGPoint) -> Double {
        let x = (point1.x - point2.x) * (point1.x - point2.x)
        let y = (point1.y - point2.y) * (point1.y - point2.y)
        return sqrt(Double(x) + Double(y))
    }
    
    func standardizeEye(ratio: Double) -> Double {
        let min = 0.15
        let max = 0.45
        print("Before: \(ratio)")
        return (ratio - min) / (max - min)
    }
}
