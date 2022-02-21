import UIKit
import AVFoundation
import Photos

class CameraViewController: UIViewController {
    
    let captureSession = AVCaptureSession()
    var videoDeviceInput:AVCaptureDeviceInput!
    let photoOutput = AVCapturePhotoOutput()
    
    let sessionQueue = DispatchQueue(label: "session Queue")
    let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInDualCamera, .builtInTripleCamera, .builtInWideAngleCamera, .builtInTrueDepthCamera],
        mediaType: .video,
        position: .unspecified
    )
    // 주기를 위해
    var timer:DispatchSourceTimer?
    
    @IBOutlet weak var photoLibraryButton: UIButton!
    @IBOutlet weak var previewView: PreviewView!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var blurBGView: UIVisualEffectView!
    @IBOutlet weak var switchButton: UIButton!
    
    override var prefersStatusBarHidden: Bool{
        return true
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        previewView.session = captureSession
        sessionQueue.async {
            self.setupSession()
            self.startSession()
        }
        setupUI()
       
        
        // 주기적 캡처를 위해
        self.timer = DispatchSource.makeTimerSource(flags: [], queue: .main)
        self.timer?.schedule(deadline: .now(), repeating: 5)
        self.timer?.setEventHandler(handler: {
            let videoPreviewLayerOrientation = self.previewView.videoPreviewLayer.connection?.videoOrientation
            self.sessionQueue.async {
                let connection = self.photoOutput.connection(with: .video)
                connection?.videoOrientation = videoPreviewLayerOrientation!
                
                let setting = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: setting, delegate: self)
            }
        })
        self.timer?.resume()
    }
    @IBAction func switchCamera(_ sender: Any) {
        switchCamera()
    }
    @IBAction func capturePhoto(_ sender: Any) {
        let videoPreviewLayerOrientation = self.previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            let connection = self.photoOutput.connection(with: .video)
            connection?.videoOrientation = videoPreviewLayerOrientation!
            
            let setting = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: setting, delegate: self)
        }
    }
    func setupUI(){
        photoLibraryButton.layer.cornerRadius = 10
        photoLibraryButton.layer.masksToBounds = true
        photoLibraryButton.layer.borderColor = UIColor.white.cgColor // white
        photoLibraryButton.layer.borderWidth = 1
        captureButton.layer.cornerRadius = captureButton.bounds.height/2 // 동그랗게
        captureButton.layer.masksToBounds = true
        blurBGView.layer.cornerRadius = blurBGView.bounds.height/2 // 동그랗게
        blurBGView.layer.masksToBounds = true
    }
    func switchCamera(){
        guard videoDeviceDiscoverySession.devices.count > 1 else { return }
        
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            let isFront = currentPosition == .front
            let preferredPosition:AVCaptureDevice.Position = isFront ? .back : .front
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice:AVCaptureDevice?
            newVideoDevice = devices.first(where: {device in
                return preferredPosition == device.position
            })
            
            // update capture session
            if let newDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: newDevice)
                    self.captureSession.beginConfiguration()
                    self.captureSession.removeInput(self.videoDeviceInput)
                    
                    // add new device input
                    if self.captureSession.canAddInput(videoDeviceInput){
                        self.captureSession.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.captureSession.addInput(self.videoDeviceInput)
                    }
                    self.captureSession.commitConfiguration()
                    
                    DispatchQueue.main.async {
                        self.updateSwitchCameraIcon(position: preferredPosition)
                    }
                    
                } catch let error{
                    print("error : \(error.localizedDescription)")
                }
            }
        }
    }
}

extension CameraViewController{
    func setupSession(){
        // preset to photo
        captureSession.sessionPreset = .photo
        captureSession.beginConfiguration()
        
        // add video input
        
        guard let camera = videoDeviceDiscoverySession.devices.first else{
            captureSession.commitConfiguration()
            return
        }
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: camera) // ??? 변수 이미 있는데
            if captureSession.canAddInput(videoDeviceInput) {
                captureSession.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                // 실행하면 전면 카메라로 자동으로 전환
                let currentVideoDevice = self.videoDeviceInput.device
                let currentPosition = currentVideoDevice.position
                let isFront = currentPosition == .front
                if !isFront {
                    switchCamera()
                }
                
            } else {
                captureSession.commitConfiguration()
                return
            }
        } catch let error{
            captureSession.commitConfiguration()
            return
        }
        
        
        // add output
        photoOutput.setPreparedPhotoSettingsArray([AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])], completionHandler: nil)
        
        if captureSession.canAddOutput(photoOutput){
            captureSession.addOutput(photoOutput)
        } else {
            captureSession.commitConfiguration()
            return
        }
        
        // 종료
        captureSession.commitConfiguration()
    }
    func startSession(){
        sessionQueue.async {
            if !self.captureSession.isRunning{
                self.captureSession.startRunning()
            }
        }
    }
    func stopSession(){
        sessionQueue.async {
            if self.captureSession.isRunning{
                self.captureSession.stopRunning()
            }
        }
    }
    func updateSwitchCameraIcon(position: AVCaptureDevice.Position){
        switch position{
        case .front:
            let image = UIImage(systemName: "pencil")
            switchButton.setImage(image, for: .normal)
            
        case .back:
            let image = UIImage(systemName: "highlighter")
            switchButton.setImage(image, for: .normal)
        default:
            break
        }
    }
}
extension CameraViewController:AVCapturePhotoCaptureDelegate{
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { return}
        guard let imageData = photo.fileDataRepresentation() else {return }
        guard let image = UIImage(data: imageData) else { return }
        self.savePhotoLibrary(image: image)
        self.imageToBase64(image: image)
    }
    
    func savePhotoLibrary(image: UIImage){
        PHPhotoLibrary.requestAuthorization{ status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }){( success, error) in
//                    print("--> 이미지 저장 완료되었나? \(success)")
                }
            } else {
                print("-> 권한을 아직 받지 못함")
                
            }
        }
    }
    func imageToBase64(image: UIImage){
//        print("imageToBase64 : ")
        let imageData:NSData = image.jpegData(compressionQuality: 0)! as NSData
        let strBase64 = imageData.base64EncodedString()
        print(strBase64)
        print()
        print()
        sendString(encodedString: strBase64)
    }
    func sendString(encodedString : String){
        let dic:Dictionary = ["message" : encodedString]
        
        guard let url = URL(string: "http://192.168.219.104:3000") else {
            return
        }
        var request = URLRequest(url:url)
        request.httpMethod = "POST"
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: dic, options: .prettyPrinted)
        } catch { print(error.localizedDescription) }
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept-Type")
        
        // URLSession으로 데이터를 서버에 전송
        print("URLSession 진입")
        let session = URLSession.shared
        session.dataTask(with: request, completionHandler: {(data, response, error) in
            print("전송완료")
        }).resume()
    }
}

