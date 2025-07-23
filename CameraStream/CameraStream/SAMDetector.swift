import Foundation
import CoreML
import Vision
import CoreImage
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
typealias PlatformImage = NSImage
typealias PlatformColor = NSColor
#endif
import os.log

class SAMDetector: ObservableObject {
    @Published var detectedObjects: [DetectedObject] = []
    @Published var isProcessing = false
    
    private var model: VNCoreMLModel?
    private let processingQueue = DispatchQueue(label: "SAMProcessingQueue", qos: .userInitiated)
    private let logger = Logger(subsystem: "CameraStream", category: "SAMDetector")
    
    // Temporal smoothing properties
    private var previousDetections: [DetectedObject] = []
    private var detectionHistory: [[DetectedObject]] = []
    private let maxHistorySize = 3
    private let smoothingFactor: Float = 0.7
    private var lastDetectionTime = Date()
    private let minDetectionInterval: TimeInterval = 0.1
    
    struct DetectedObject: Identifiable {
        let id = UUID()
        let boundingBox: CGRect
        let confidence: Float
        let label: String
        let mask: PlatformImage?
        
        // Helper for distance calculation
        var center: CGPoint {
            return CGPoint(x: boundingBox.midX, y: boundingBox.midY)
        }
    }
    
    init() {
        logger.info("Initializing SAM Detector")
        setupModel()
    }
    
    private func setupModel() {
        processingQueue.async {
            self.logger.info("Loading Core ML model for object detection")
            self.setupCoreMLModel()
        }
    }
    
    private func setupCoreMLModel() {
        // Debug: List all files in bundle
        let bundlePath = Bundle.main.bundlePath
        print("🔥 SAMDetector: Bundle path: \(bundlePath)")
        
        if let bundleContents = try? FileManager.default.contentsOfDirectory(atPath: bundlePath) {
            print("🔥 SAMDetector: Bundle contents: \(bundleContents)")
        }
        
        // Try to load YOLOv3 object detection model (compiled version .mlmodelc)
        guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc") else {
            print("🔥 SAMDetector: Could not find YOLOv3.mlmodelc in bundle - running with mock detection")
            
            // Also try .mlmodel as fallback
            if let fallbackURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodel") {
                print("🔥 SAMDetector: Found YOLOv3.mlmodel fallback at: \(fallbackURL)")
                loadModel(from: fallbackURL)
                return
            }
            
            print("🔥 SAMDetector: No YOLOv3 model found, using mock detection")
            return
        }
        
        print("🔥 SAMDetector: Found YOLOv3.mlmodelc at: \(modelURL)")
        loadModel(from: modelURL)
    }
    
    private func loadModel(from url: URL) {
        do {
            let mlModel = try MLModel(contentsOf: url)
            let visionModel = try VNCoreMLModel(for: mlModel)
            
            DispatchQueue.main.async {
                self.model = visionModel
                print("🔥 SAMDetector: Successfully loaded YOLOv3 Core ML model from: \(url.lastPathComponent)")
            }
        } catch {
            print("🔥 SAMDetector: Failed to load YOLOv3 model from \(url.lastPathComponent): \(error)")
        }
    }
    
    func detectObjects(in image: CGImage) {
        guard !isProcessing else { 
            logger.debug("Detection already in progress, skipping frame")
            return 
        }
        
        logger.debug("Starting object detection on real camera frame")
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        // Run Core ML detection on real camera frames
        performCoreMLDetection(for: image)
    }
    
    private func performCoreMLDetection(for image: CGImage) {
        guard let model = model else {
            // No model loaded, generate mock detections for demonstration
            print("🔥 SAMDetector: No Core ML model available - generating mock detections")
            self.generateMockDetections(for: image)
            return
        }
        
        print("🔥 SAMDetector: Using Core ML model for detection - image size: \(image.width)x\(image.height)")
        
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            DispatchQueue.main.async {
                self?.isProcessing = false
                if let error = error {
                    print("🔥 SAMDetector: Detection error: \(error)")
                    self?.detectedObjects = []
                } else {
                    print("🔥 SAMDetector: Detection completed, processing results...")
                    self?.processDetectionResults(request.results)
                }
            }
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        
        processingQueue.async {
            do {
                try handler.perform([request])
            } catch {
                print("🔥 SAMDetector: Failed to perform detection: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.detectedObjects = []
                }
            }
        }
    }
    
    private func processDetectionResults(_ results: [VNObservation]?) {
        guard let results = results else {
            print("🔥 SAMDetector: No detection results received")
            detectedObjects = []
            return
        }
        
        print("🔥 SAMDetector: Processing \(results.count) detection results")
        
        var objects: [DetectedObject] = []
        
        for observation in results {
            if let recognizedObject = observation as? VNRecognizedObjectObservation {
                let boundingBox = recognizedObject.boundingBox
                
                // Get the top classification
                if let topLabel = recognizedObject.labels.first {
                    print("🔥 SAMDetector: Found object: \(topLabel.identifier) with confidence: \(topLabel.confidence)")
                    
                    let object = DetectedObject(
                        boundingBox: boundingBox,
                        confidence: topLabel.confidence,
                        label: topLabel.identifier,
                        mask: nil // SAM would provide segmentation masks here
                    )
                    objects.append(object)
                }
            }
        }
        
        // Filter objects with confidence > 0.2
        let filteredObjects = objects.filter { $0.confidence > 0.2 }
        print("🔥 SAMDetector: Filtered to \(filteredObjects.count) objects with confidence > 0.2")
        
        // Apply temporal smoothing
        let smoothedObjects = applyTemporalSmoothing(to: filteredObjects)
        detectedObjects = smoothedObjects
    }
    
    // Temporal smoothing to stabilize detections
    private func applyTemporalSmoothing(to newDetections: [DetectedObject]) -> [DetectedObject] {
        // Add to history
        detectionHistory.append(newDetections)
        if detectionHistory.count > maxHistorySize {
            detectionHistory.removeFirst()
        }
        
        // If we don't have enough history, return new detections
        guard detectionHistory.count >= 2 else {
            previousDetections = newDetections
            return newDetections
        }
        
        var smoothedDetections: [DetectedObject] = []
        
        // For each new detection, try to match with previous detections
        for newDetection in newDetections {
            if let matchedPrevious = findBestMatch(for: newDetection, in: previousDetections) {
                // Smooth the bounding box and confidence
                let smoothedBox = smoothBoundingBox(
                    current: newDetection.boundingBox,
                    previous: matchedPrevious.boundingBox,
                    factor: smoothingFactor
                )
                
                let smoothedConfidence = smoothValue(
                    current: newDetection.confidence,
                    previous: matchedPrevious.confidence,
                    factor: smoothingFactor
                )
                
                let smoothedObject = DetectedObject(
                    boundingBox: smoothedBox,
                    confidence: Float(smoothedConfidence),
                    label: newDetection.label, // Keep current label
                    mask: newDetection.mask
                )
                smoothedDetections.append(smoothedObject)
            } else {
                // New detection, add as-is
                smoothedDetections.append(newDetection)
            }
        }
        
        previousDetections = smoothedDetections
        return smoothedDetections
    }
    
    // Find the best matching detection from previous frame
    private func findBestMatch(for detection: DetectedObject, in previousDetections: [DetectedObject]) -> DetectedObject? {
        var bestMatch: DetectedObject?
        var minDistance: Float = Float.greatestFiniteMagnitude
        let maxMatchDistance: Float = 0.3 // Maximum distance to consider a match
        
        for previousDetection in previousDetections {
            // Only match objects with the same label
            guard previousDetection.label == detection.label else { continue }
            
            let distance = euclideanDistance(detection.center, previousDetection.center)
            if distance < minDistance && distance < maxMatchDistance {
                minDistance = distance
                bestMatch = previousDetection
            }
        }
        
        return bestMatch
    }
    
    // Calculate Euclidean distance between two points
    private func euclideanDistance(_ point1: CGPoint, _ point2: CGPoint) -> Float {
        let dx = Float(point1.x - point2.x)
        let dy = Float(point1.y - point2.y)
        return sqrt(dx * dx + dy * dy)
    }
    
    // Smooth bounding box coordinates
    private func smoothBoundingBox(current: CGRect, previous: CGRect, factor: Float) -> CGRect {
        return CGRect(
            x: smoothValue(current: Float(current.origin.x), previous: Float(previous.origin.x), factor: factor),
            y: smoothValue(current: Float(current.origin.y), previous: Float(previous.origin.y), factor: factor),
            width: smoothValue(current: Float(current.width), previous: Float(previous.width), factor: factor),
            height: smoothValue(current: Float(current.height), previous: Float(previous.height), factor: factor)
        )
    }
    
    // Smooth a single float value
    private func smoothValue(current: Float, previous: Float, factor: Float) -> CGFloat {
        return CGFloat(previous * factor + current * (1.0 - factor))
    }
    
    // Simplified SAM-like processing (placeholder for actual SAM integration)
    func generateSegmentationMask(for object: DetectedObject, in image: CGImage) -> PlatformImage? {
        // This would integrate with actual SAM model for segmentation
        // For now, return a simple bounding box visualization
        return createBoundingBoxImage(for: object.boundingBox, imageSize: CGSize(width: image.width, height: image.height))
    }
    
    // Generate mock segmentation masks that look more like real SAM output
    private func generateMockSegmentationMask(boundingBox: CGRect, imageSize: CGSize, color: PlatformColor) -> PlatformImage? {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        return renderer.image { context in
            // Clear background
            context.cgContext.setFillColor(UIColor.clear.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: imageSize))
            
            // Convert normalized coordinates to actual pixel coordinates
            let actualRect = CGRect(
                x: boundingBox.minX * imageSize.width,
                y: (1 - boundingBox.maxY) * imageSize.height,
                width: boundingBox.width * imageSize.width,
                height: boundingBox.height * imageSize.height
            )
            
            // Create an elliptical mask within the bounding box (more realistic than rectangle)
            context.cgContext.setFillColor(color.withAlphaComponent(0.4).cgColor)
            let ellipseRect = actualRect.insetBy(dx: actualRect.width * 0.1, dy: actualRect.height * 0.1)
            context.cgContext.fillEllipse(in: ellipseRect)
            
            // Add a stroke around the segmentation
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(2.0)
            context.cgContext.strokeEllipse(in: ellipseRect)
        }
        #elseif os(macOS)
        // For macOS, create an NSImage using CoreGraphics
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // Clear background
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: imageSize))
        
        // Convert normalized coordinates to actual pixel coordinates
        let actualRect = CGRect(
            x: boundingBox.minX * imageSize.width,
            y: (1 - boundingBox.maxY) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
        
        // Create an elliptical mask within the bounding box
        context.setFillColor(color.withAlphaComponent(0.4).cgColor)
        let ellipseRect = actualRect.insetBy(dx: actualRect.width * 0.1, dy: actualRect.height * 0.1)
        context.fillEllipse(in: ellipseRect)
        
        // Add a stroke around the segmentation
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(2.0)
        context.strokeEllipse(in: ellipseRect)
        
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: imageSize)
        #endif
    }
    
    private func createBoundingBoxImage(for boundingBox: CGRect, imageSize: CGSize) -> PlatformImage? {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        
        return renderer.image { context in
            context.cgContext.setStrokeColor(PlatformColor.red.cgColor)
            context.cgContext.setLineWidth(3.0)
            
            let rect = CGRect(
                x: boundingBox.minX * imageSize.width,
                y: (1 - boundingBox.maxY) * imageSize.height,
                width: boundingBox.width * imageSize.width,
                height: boundingBox.height * imageSize.height
            )
            
            context.cgContext.stroke(rect)
        }
        #elseif os(macOS)
        // For macOS, create an NSImage using CoreGraphics
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.setStrokeColor(PlatformColor.red.cgColor)
        context.setLineWidth(3.0)
        
        let rect = CGRect(
            x: boundingBox.minX * imageSize.width,
            y: (1 - boundingBox.maxY) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )
        
        context.stroke(rect)
        
        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: imageSize)
        #endif
    }
    
    // Generate mock detections for demonstration when no Core ML model is available
    private func generateMockDetections(for image: CGImage) {
        processingQueue.async {
            // Simulate processing time
            Thread.sleep(forTimeInterval: 0.1)
            
            let imageSize = CGSize(width: image.width, height: image.height)
            
            // Create 2-3 mock detected objects
            var mockObjects: [DetectedObject] = []
            
            // Mock object 1 - center-left area
            let object1 = DetectedObject(
                boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.25, height: 0.4),
                confidence: 0.85,
                label: "person",
                mask: self.generateMockSegmentationMask(
                    boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.25, height: 0.4),
                    imageSize: imageSize,
                    color: PlatformColor.green
                )
            )
            mockObjects.append(object1)
            
            // Mock object 2 - center-right area
            let object2 = DetectedObject(
                boundingBox: CGRect(x: 0.55, y: 0.25, width: 0.3, height: 0.5),
                confidence: 0.72,
                label: "chair",
                mask: self.generateMockSegmentationMask(
                    boundingBox: CGRect(x: 0.55, y: 0.25, width: 0.3, height: 0.5),
                    imageSize: imageSize,
                    color: PlatformColor.blue
                )
            )
            mockObjects.append(object2)
            
            // Randomly add a third object sometimes
            if arc4random_uniform(3) == 0 {
                let object3 = DetectedObject(
                    boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.3),
                    confidence: 0.63,
                    label: "bottle",
                    mask: self.generateMockSegmentationMask(
                        boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.3),
                        imageSize: imageSize,
                        color: PlatformColor.orange
                    )
                )
                mockObjects.append(object3)
            }
            
            // Add a low confidence object to test 0.2 threshold
            let lowConfidenceObject = DetectedObject(
                boundingBox: CGRect(x: 0.7, y: 0.1, width: 0.15, height: 0.2),
                confidence: 0.35,
                label: "phone",
                mask: self.generateMockSegmentationMask(
                    boundingBox: CGRect(x: 0.7, y: 0.1, width: 0.15, height: 0.2),
                    imageSize: imageSize,
                    color: PlatformColor.purple
                )
            )
            mockObjects.append(lowConfidenceObject)
            
            DispatchQueue.main.async {
                self.isProcessing = false
                // Apply temporal smoothing to mock detections too
                let smoothedMockObjects = self.applyTemporalSmoothing(to: mockObjects)
                self.detectedObjects = smoothedMockObjects
                print("🔥 SAMDetector: Generated \(mockObjects.count) mock detections (smoothed to \(smoothedMockObjects.count))")
            }
        }
    }
}
