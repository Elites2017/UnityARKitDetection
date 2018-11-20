//
//  VisionNative.swift
//  Vision
//
//  Created by Adam Hegedus on 2018. 05. 23..
//

import Foundation
import AVFoundation
import Vision

@objc public class VisionNative: NSObject {
    
    // Shared instance
    @objc static let shared = VisionNative()
    
    // Used to cache vision requests to be performed
    private lazy var visionRequests = [VNRequest]()
    
    // Unique serial queue reserved for vision requests
    private let visionRequestQueue = DispatchQueue(label: "com.possible.unity.visionqueue")
    
    // Id of the managed Unity game object to forward messages to
    private var callbackTarget: String = "Vision"
    
    // Exposed buffer for caching the results of an image classification request
    @objc public var classificationBuffer: [VisionClassification] = []
    private var maxClassificationResults: Int = 10
    
    // Exposed buffer for caching the results of a rectangle recognition request
    @objc public var pointBuffer: [CGPoint] = []
    
    let ssdPostProcessor = SSDPostProcessor(numAnchors: 1917, numClasses: 90)
    
    @objc func allocateVisionRequests(requestType: Int, maxObservations: Int)
    {
        // Empty request buffer
        visionRequests.removeAll()
        
        if (requestType == 0) {
            print("[VisionNative] No requests specified.")
            return
        }
        
        let classifierEnabled = requestType & 1 << 0 == 1 << 0
        let rectangleRecognitionEnabled = requestType & 1 << 1 == 1 << 1
        
        if classifierEnabled {
            
            // Set up CoreML model
            guard let ssd = ssd_mobilenet_feature_extractor()?.model else {
                fatalError("[VisionNative] Failed to generate CoreML model.")
            }
            
            guard let mlModel = try? VNCoreMLModel(for: ssd) else {
                fatalError("[VisionNative] Unable to load CoreML model.")
            }
            
            // Set up Vision-CoreML request
            let classificationRequest = VNCoreMLRequest(model: mlModel, completionHandler: classificationCompleteHandler)
            
            // Crop from centre of images and scale to appropriate size
            classificationRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.centerCrop
            
            // Set the number of maximum image classifications results kept in store
            self.maxClassificationResults = maxObservations
            
            // Register request
            visionRequests.append(classificationRequest)
            
            print("[VisionNative] Classification request allocated.")
        }
        
        if rectangleRecognitionEnabled {
            
            // Set up rectangle detection request
            let rectangleRequest = VNDetectRectanglesRequest(completionHandler: rectangleRecognitionCompleteHandler)
            rectangleRequest.maximumObservations = maxObservations
            rectangleRequest.quadratureTolerance = 15
            
            // Register request
            visionRequests.append(rectangleRequest)
            
            print("[VisionNative] Rectangle detection request allocated.")
        }
    }
    
    @objc func evaluate(texture: MTLTexture) -> Bool {
        
        // Create an image from the current state of the buffer
        guard let image = CIImage(mtlTexture: texture, options: nil) else { return false }
        
        // Perform vision request
        performVisionRequest(for: image)
        
        return true
    }
    
    @objc func evaluate(buffer: CVPixelBuffer) -> Bool {
        
        // Lock the buffer
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
        
        // Create an image from the current state of the buffer
        let image = CIImage(cvPixelBuffer: buffer)
        
        // Unlock the buffer
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags.readOnly)
        
        // Perform vision request
        performVisionRequest(for: image)
        
        return true
    }
    
    private func performVisionRequest(for image: CIImage) {
        
        visionRequestQueue.async {
            // Prepare image request
            let imageRequestHandler = VNImageRequestHandler(ciImage: image, options: [:])
            
            // Run image request
            do {
                try imageRequestHandler.perform(self.visionRequests)
            } catch {
                print(error)
            }
        }
    }
    
    @objc func setCallbackTarget(target: String) {
        
        // Set the target for unity messaging
        self.callbackTarget = target
    }
    
    private func classificationCompleteHandler(request: VNRequest, error: Error?) {
        
        // Fall back to main thread
        DispatchQueue.main.async {
            
            // Catch errors
            if error != nil {
                let error = "[VisionNative] Error: " + (error?.localizedDescription)!
                UnitySendMessage(self.callbackTarget, "OnClassificationComplete", error)
                return
            }
            guard let results = request.results as? [VNCoreMLFeatureValueObservation] else {
                return
            }
            guard results.count == 2 else {
                return
            }

            guard let boxPredictions = results[1].featureValue.multiArrayValue,
                let classPredictions = results[0].featureValue.multiArrayValue else {
                    UnitySendMessage(self.callbackTarget, "OnClassificationComplete", "No results")
                    return
            }
            
            let predictions = self.ssdPostProcessor.postprocess(boxPredictions: boxPredictions, classPredictions: classPredictions)
            
            // Cache classifications
            self.classificationBuffer.removeAll()
            for (_, prediction) in predictions.enumerated() {
                if let classNames = self.ssdPostProcessor.classNames {
                    print("Class: \(classNames[prediction.detectedClass])")
                    let bb = prediction.finalPrediction
                    let vc = VisionClassification(identifier: classNames[prediction.detectedClass],
                                                  confidence:self.sigmoid(Float(prediction.score)),
                                                  xMin:Float(bb.xMin),
                                                  yMin:Float(bb.yMin),
                                                  xMax:Float(bb.xMax),
                                                  yMax:Float(bb.yMax)
                    )
                    self.classificationBuffer.append(vc)
                }
            }
            
            // Call unity object with no errors
            UnitySendMessage(self.callbackTarget, "OnClassificationComplete", "")
        }
    }
    func sigmoid(_ val:Float) -> Float {
        return 1.0/(1.0 + exp(-val))
    }

    private func rectangleRecognitionCompleteHandler(request: VNRequest, error: Error?) {
        
        // Fall back to main thread
        DispatchQueue.main.async {
            
            // Catch errors
            if error != nil {
                let error = "[VisionNative] Error: " + (error?.localizedDescription)!
                UnitySendMessage(self.callbackTarget, "OnRectangleRecognitionComplete", error)
                return
            }
            
            guard let observations = request.results as? [VNRectangleObservation],
                let _ = observations.first else {
                    UnitySendMessage(self.callbackTarget, "OnRectangleRecognitionComplete", "No results")
                    return
            }
            
            // Cache points
            self.pointBuffer.removeAll()
            for observation in observations {
                self.pointBuffer.append(contentsOf: [
                    observation.topLeft,
                    observation.topRight,
                    observation.bottomRight,
                    observation.bottomLeft])
            }
            
            // Call unity object with no errors
            UnitySendMessage(self.callbackTarget, "OnRectangleRecognitionComplete", "")
        }
    }
}
