//
//  ViewController.swift
//  Cammoji
//
//  Created by Umi Syam on 12/10/15.
//  Copyright © 2015 Umi Syam. All rights reserved.
//

import UIKit
import Foundation

import AVFoundation
import CoreImage
import CoreMedia
import ImageIO
import AssetsLibrary

class ViewController: UIViewController, UIGestureRecognizerDelegate,  AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let kOrientationToDegreesFront: [UIDeviceOrientation: CGFloat] = [
        .Portrait: -90,
        .PortraitUpsideDown: 90,
        .LandscapeLeft: 180,
        .LandscapeRight: 0,
        .FaceUp: 0,
        .FaceDown: 0
    ]
    
    let kOrientationToDegreesBack: [UIDeviceOrientation: CGFloat] = [
        .Portrait: -90,
        .PortraitUpsideDown: 90,
        .LandscapeLeft: 0,
        .LandscapeRight: 180,
        .FaceUp: 0,
        .FaceDown: 0
    ]
    
    // used for KVO observation of the @"capturingStillImage" property to perform flash bulb animation
    let AVCaptureStillImageIsCapturingStillImageContext = "AVCaptureStillImageIsCapturingStillImageContext"
    
    func DegreesToRadians(degrees : CGFloat) -> CGFloat {
        return (degrees * CGFloat(M_PI / 180))
    }
    
    // MARK: Properites
    
    @IBOutlet weak var previewView : UIView!
    @IBOutlet weak var camerasControl : UISegmentedControl!
    @IBOutlet weak var eyeLeftLabel : UILabel!
    @IBOutlet weak var eyeRightLabel : UILabel!
    @IBOutlet weak var mouthLabel : UILabel!
    
    var previewLayer : AVCaptureVideoPreviewLayer!
    var videoDataOutput : AVCaptureVideoDataOutput!
    var detectFaces = false
//    private var _detectFaces = false
    var videoDataOutputQueue : dispatch_queue_t!
    var stillImageOutput : AVCaptureStillImageOutput!
    var flashView : UIView!
    var square : UIImage!
    var isUsingFrontFacingCamera : Bool!
    var faceDetector : CIDetector!
    var beginGestureScale : CGFloat!
    var effectiveScale : CGFloat!
    
    // MARK: View Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        setupAVCapture()
        square = UIImage(named: "squareBox")
        
        let detectorOptions = [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorTracking: true]
        faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: detectorOptions as? [String : AnyObject])
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    // MARKS: Actions
    
    @IBAction func takePicture (sender : UIButton!) {
        print("Capturing image")
        stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
//        captureSession.addOutput(stillImageOutput)
        
        if let videoConnection = stillImageOutput.connectionWithMediaType(AVMediaTypeVideo){
            stillImageOutput.captureStillImageAsynchronouslyFromConnection(videoConnection, completionHandler: {
                (sampleBuffer, error) in
                var imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer)
                var dataProvider = CGDataProviderCreateWithCFData(imageData)
                var cgImageRef = CGImageCreateWithJPEGDataProvider(dataProvider, nil, true, CGColorRenderingIntent.RenderingIntentDefault)
                var image = UIImage(CGImage: cgImageRef!, scale: 1.0, orientation: UIImageOrientation.Right)

                let screenSize: CGRect = UIScreen.mainScreen().bounds
                var imageView = UIImageView(image: image)
                imageView.frame = CGRect(x:0, y:0, width:screenSize.width, height:screenSize.height)
                
                //Show the captured image to
                self.view.addSubview(imageView)
                
                //Save the captured preview to image
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                
            })
        }
 
        
    }
    
    // utility routine to display error aleart if takePicture fails
    func displayErrorOnMainQueue( error:NSError, message: String) {
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            let alertController = UIAlertController(
                title: "\(message) \(error.code)",
                message: error.localizedDescription,
                preferredStyle: UIAlertControllerStyle.Alert
            )
            let alertAction = UIAlertAction(title: "OK", style: UIAlertActionStyle.Default, handler: nil)
            alertController.addAction(alertAction)
            self.presentViewController(alertController, animated: true, completion: nil)
        })
    }
    
    // create a CGImage with provided pixel buffer, pixel buffer must be uncompressed kCVPixelFormatType_32ARGB or kCVPixelFormatType_32BGRA
    func CreateCGImageFromCVPixelBuffer(pixelBuffer:CVPixelBufferRef) -> CGImage!
    {
        var err: OSStatus = noErr
        var bitmapInfo: CGBitmapInfo
        var image: CGImage!
        
        CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
        var sourcePixelFormat: OSType = CVPixelBufferGetPixelFormatType( pixelBuffer )
        if ( Int(kCVPixelFormatType_32ARGB) == Int(sourcePixelFormat) ) {
            bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.ByteOrder32Big.rawValue | CGImageAlphaInfo.NoneSkipFirst.rawValue)
        }
        else if ( Int(kCVPixelFormatType_32BGRA) == Int(sourcePixelFormat) ) {
            bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.ByteOrder32Little.rawValue | CGImageAlphaInfo.NoneSkipFirst.rawValue)
        }
        else {
            return nil // -95014; // only uncompressed pixel formats
        }
        
        let width: Int = CVPixelBufferGetWidth( pixelBuffer )
        let height: Int = CVPixelBufferGetHeight( pixelBuffer )
        let sourceRowBytes: Int = CVPixelBufferGetBytesPerRow( pixelBuffer );
        let sourceBaseAddr: UnsafeMutablePointer<Void>  = CVPixelBufferGetBaseAddress( pixelBuffer );
        //println("Pixel buffer info - w:\(width) h:\(height) BytesPerRow:\(sourceRowBytes) BaseAddr:\(sourceBaseAddr)")
        
        let colorspace = CGColorSpaceCreateDeviceRGB();

        let context = CGBitmapContextCreate(sourceBaseAddr, width, height, 8, Int(sourceRowBytes), colorspace, bitmapInfo.rawValue)
        if (context != nil) {
            image = CGBitmapContextCreateImage(context)
        }
        else {
            print("CreateCGImageFromCVPixelBuffer():  Failed to create bitmap context")
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
        
        return image;
    }
    

    // utility routine used after taking a still image to write the resulting image to the camera roll
    func writeCGImageToCameraRoll (cgImage: CGImageRef, metadata: CFDictionary) -> Bool
    {
        var destinationData: CFMutableDataRef = CFDataCreateMutable(kCFAllocatorDefault, 0)
        
        let destination: CGImageDestinationRef! = CGImageDestinationCreateWithData(destinationData,
            "public.jpeg",
            1,
            nil)
        assert(destination != nil)
        
        let JPEGCompQuality: Float = 0.85 // JPEGHigherQuality
        //  The following no longer works in XCode 6.1; the CFString! type is not hashable.
        //let optionsDict = [kCGImageDestinationLossyCompressionQuality: JPEGCompQuality]
        var key: NSString = kCGImageDestinationLossyCompressionQuality
        let optionsDict = [key: JPEGCompQuality]
        //    var keys: UnsafeMutablePointer<UnsafePointer<Void>>
        //    var key = kCGImageDestinationLossyCompressionQuality as UnsafePointer<Void>
        //    var val:Float = JPEGCompQuality
        //    var optionsDict: CFDictionary! = CFDictionaryCreate(kCFAllocatorDefault, &key, &val, 1, nil, nil)
        CGImageDestinationAddImage( destination, cgImage, optionsDict )
        var success = CGImageDestinationFinalize( destination )
        
        assert(success == true)
        
        let library = ALAssetsLibrary()
        let data = NSData(data:destinationData)
        library.writeImageDataToSavedPhotosAlbum(data, metadata: metadata as NSDictionary as [NSObject : AnyObject], completionBlock: nil)
        return success;
    }
    

    
    @IBAction func switchCameras (sender : UISegmentedControl!) {
        var desiredPosition : AVCaptureDevicePosition
        desiredPosition = isUsingFrontFacingCamera == true ? AVCaptureDevicePosition.Back : AVCaptureDevicePosition.Front
        
        for d in AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo) as! [AVCaptureDevice] {
            
            if d.position == desiredPosition {
                
                previewLayer.session.beginConfiguration()
                
                let input : AVCaptureDeviceInput = try! AVCaptureDeviceInput(device: d)
                
                for oldInput in previewLayer.session.inputs as! [AVCaptureInput] {
                    previewLayer.session.removeInput(oldInput)
                }
                
                previewLayer.session.addInput(input)
                previewLayer.session.commitConfiguration()
            }
        }
        
        isUsingFrontFacingCamera = !isUsingFrontFacingCamera
    }
    
    @IBAction func handlePinchGesture (sender : UIGestureRecognizer!) {
        
    }
    
    @IBAction func toggleFaceDetection (sender : UISwitch!) {
        detectFaces = sender.on
        videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = detectFaces
        if !detectFaces {
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.drawFaceBoxesForFeatures([], clap: CGRectZero, orientation: UIDeviceOrientation.Portrait)
            })
        }
    }
    
    // Setup functions
    
    func setupAVCapture() {
        
        let session : AVCaptureSession = AVCaptureSession()
        session.sessionPreset = AVCaptureSessionPreset640x480
        
        // Select a video device, make an input
        let device : AVCaptureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        let deviceInput : AVCaptureDeviceInput = try! AVCaptureDeviceInput(device: device)
        isUsingFrontFacingCamera = false
        detectFaces = false
        
        if session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
        }
        
        stillImageOutput = AVCaptureStillImageOutput()
        
        // Make a video data output
        videoDataOutput = AVCaptureVideoDataOutput()
        // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
        let rgbOutputSettings = [kCVPixelBufferPixelFormatTypeKey as String: NSNumber(unsignedInt: kCMPixelFormat_32BGRA)]
        
        videoDataOutput.videoSettings = rgbOutputSettings
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        
        videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL)
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        videoDataOutput.connectionWithMediaType(AVMediaTypeVideo).enabled = false
        
        effectiveScale = 1.0
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.backgroundColor = UIColor.blackColor().CGColor
        previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
        let rootLayer : CALayer = previewView.layer
        rootLayer.masksToBounds = true
        previewLayer.frame = rootLayer.bounds
        rootLayer.addSublayer(previewLayer)
        session.startRunning()
    }
    
    func teardownAVCapture() {
        videoDataOutput = nil
        videoDataOutputQueue = nil
        previewLayer.removeFromSuperlayer()
        previewLayer = nil
    }
    
    // MARK: Delegates
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        // got an image
        let pixelBuffer : CVPixelBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer)!
        let attachments : CFDictionaryRef = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, pixelBuffer, CMAttachmentMode( kCMAttachmentMode_ShouldPropagate))!
        
        let ciImage : CIImage = CIImage(CVPixelBuffer: pixelBuffer, options: attachments as? [String : AnyObject])
        
        let curDeviceOrientation : UIDeviceOrientation = UIDevice.currentDevice().orientation
        var exifOrientation : Int
        
        enum DeviceOrientation : Int {
            case PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
            PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.
            PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.
            PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.
            PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.
            PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.
        }
        
        switch curDeviceOrientation {
            
        case UIDeviceOrientation.PortraitUpsideDown:
            exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM.rawValue
        case UIDeviceOrientation.LandscapeLeft:
            if isUsingFrontFacingCamera == true {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT.rawValue
            } else {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_TOP_0COL_LEFT.rawValue
            }
        case UIDeviceOrientation.LandscapeRight:
            if isUsingFrontFacingCamera == true {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_TOP_0COL_LEFT.rawValue
            } else {
                exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT.rawValue
            }
        default:
            exifOrientation = DeviceOrientation.PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP.rawValue
        }
        
        let imageOptions : NSDictionary = [CIDetectorImageOrientation : NSNumber(integer: exifOrientation), CIDetectorSmile : true, CIDetectorEyeBlink : true]
        
        let features = faceDetector.featuresInImage(ciImage, options: imageOptions as? [String : AnyObject])
        
        // get the clean aperture
        // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
        // that represents image data valid for display.
        let fdesc : CMFormatDescriptionRef = CMSampleBufferGetFormatDescription(sampleBuffer)!
        let clap : CGRect = CMVideoFormatDescriptionGetCleanAperture(fdesc, false)
        
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            self.drawFaceBoxesForFeatures(features, clap: clap, orientation: curDeviceOrientation)
        })
    }
    
    // called asynchronously as the capture output is capturing sample buffers, this method asks the face detector (if on)
    // to detect features and for each draw the red square in a layer and set appropriate orientation
    func drawFaceBoxesForFeatures(features : NSArray, clap : CGRect, orientation : UIDeviceOrientation) {
        
        let sublayers : NSArray = previewLayer.sublayers!
        let sublayersCount : Int = sublayers.count
        var currentSublayer : Int = 0
        //        var featuresCount : Int = features.count
        var currentFeature : Int = 0
        
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // hide all the face layers
        for layer in sublayers as! [CALayer] {
            if (layer.name != nil && layer.name == "FaceLayer") {
                layer.hidden = true
            }
        }
        
        if ( features.count == 0 || !detectFaces ) {
            CATransaction.commit()
            return
        }
        
        let parentFrameSize : CGSize = previewView.frame.size
        let gravity : NSString = previewLayer.videoGravity
        
        let previewBox : CGRect = ViewController.videoPreviewBoxForGravity(gravity, frameSize: parentFrameSize, apertureSize: clap.size)
        
        for ff in features as! [CIFaceFeature] {
            // set text on label
            var x : CGFloat = 0.0, y : CGFloat = 0.0
            if ff.hasLeftEyePosition {
                x = ff.leftEyePosition.x
                y = ff.leftEyePosition.y
//                eyeLeftLabel.text = ff.leftEyeClosed ? "(\(x) \(y))" : "(\(x) \(y))" + "👀"
                eyeLeftLabel.text = ff.leftEyeClosed ? "" : "👀"
            }
            
            if ff.hasRightEyePosition {
                x = ff.rightEyePosition.x
                y = ff.rightEyePosition.y
//                eyeRightLabel.text = ff.rightEyeClosed ? "(\(x) \(y))" : "(\(x) \(y))" + "👀"
                eyeRightLabel.text = ff.rightEyeClosed ? "" : "👀"
            }
            
            if ff.hasMouthPosition {
                x = ff.mouthPosition.x
                y = ff.mouthPosition.y
//                mouthLabel.text = ff.hasSmile ? "\(x) \(y)" + "😊" : "(\(x) \(y))"
                mouthLabel.text = ff.hasSmile ? "😊" : ""
            }
            
            // find the correct position for the square layer within the previewLayer
            // the feature box originates in the bottom left of the video frame.
            // (Bottom right if mirroring is turned on)
            var faceRect : CGRect = ff.bounds
            
            // flip preview width and height
            var temp : CGFloat = faceRect.width
            faceRect.size.width = faceRect.height
            faceRect.size.height = temp
            temp = faceRect.origin.x
            faceRect.origin.x = faceRect.origin.y
            faceRect.origin.y = temp
            // scale coordinates so they fit in the preview box, which may be scaled
            let widthScaleBy = previewBox.size.width / clap.size.height
            let heightScaleBy = previewBox.size.height / clap.size.width
            faceRect.size.width *= widthScaleBy
            faceRect.size.height *= heightScaleBy
            faceRect.origin.x *= widthScaleBy
            faceRect.origin.y *= heightScaleBy
            
            faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y)
            var featureLayer : CALayer? = nil
            // re-use an existing layer if possible
            while (featureLayer == nil) && (currentSublayer < sublayersCount) {
                
                let currentLayer : CALayer = sublayers.objectAtIndex(currentSublayer++) as! CALayer
                
                if currentLayer.name == nil {
                    continue
                }
                let name : NSString = currentLayer.name!
                if name.isEqualToString("FaceLayer") {
                    featureLayer = currentLayer;
                    currentLayer.hidden = false
                }
            }
            
            // create a new one if necessary
            if featureLayer == nil {
                featureLayer = CALayer()
                featureLayer?.contents = square.CGImage
                featureLayer?.name = "FaceLayer"
                previewLayer.addSublayer(featureLayer!)
            }
            
            featureLayer?.frame = faceRect
            
            currentFeature++
        }
        
        CATransaction.commit()
    }
    
    // find where the video box is positioned within the preview layer based on the video size and gravity
    class func videoPreviewBoxForGravity(gravity : NSString, frameSize : CGSize, apertureSize : CGSize) -> CGRect {
        let apertureRatio : CGFloat = apertureSize.height / apertureSize.width
        let viewRatio : CGFloat = frameSize.width / frameSize.height
        
        var size : CGSize = CGSizeZero
        if gravity.isEqualToString(AVLayerVideoGravityResizeAspectFill) {
            if viewRatio > apertureRatio {
                size.width = frameSize.width
                size.height = apertureSize.width * (frameSize.width / apertureSize.height)
            } else {
                size.width = apertureSize.height * (frameSize.height / apertureSize.width)
                size.height = frameSize.height
            }
        } else if gravity.isEqualToString(AVLayerVideoGravityResizeAspect) {
            if viewRatio > apertureRatio {
                size.width = apertureSize.height * (frameSize.height / apertureSize.width)
                size.height = frameSize.height
            } else {
                size.width = frameSize.width
                size.height = apertureSize.width * (frameSize.width / apertureSize.height)
            }
        } else if gravity.isEqualToString(AVLayerVideoGravityResize) {
            size.width = frameSize.width
            size.height = frameSize.height
        }
        
        var videoBox : CGRect = CGRectZero
        videoBox.size = size
        if size.width < frameSize.width {
            videoBox.origin.x = (frameSize.width - size.width) / 2;
        } else {
            videoBox.origin.x = (size.width - frameSize.width) / 2;
        }
        
        if size.height < frameSize.height {
            videoBox.origin.y = (frameSize.height - size.height) / 2;
        } else {
            videoBox.origin.y = (size.height - frameSize.height) / 2;
        }
        
        return videoBox
    }
}

