import Foundation
import AVFoundation
import Combine
import CoreImage
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import Network

class CameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @Published var session: AVCaptureSession?
    let output = AVCaptureVideoDataOutput()
    let sessionQueue = DispatchQueue(label: "sessionQueue")
    
    // Queue for handling server socket operations
    private let serverQueue = DispatchQueue(label: "serverQueue")
    // Socket descriptor for the HTTP server
    private var serverSocket: Int32 = -1
    // Buffer for the latest JPEG frame
    private var currentFrame: Data?
    // Server running flag
    private var isServerRunning = false
    // Frame access queue
    private let frameQueue = DispatchQueue(label: "frameQueue", attributes: .concurrent)
    
    // Camera device for zoom control
    private var currentDevice: AVCaptureDevice?
    @Published var zoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var minZoomFactor: CGFloat = 1.0
    
    // Manual focus control
    @Published var focusDistance: Float = 0.0
    @Published var isManualFocusEnabled: Bool = false
    
    // Flash control
    @Published var isFlashEnabled: Bool = false
    @Published var isFlashAvailable: Bool = false
    
    // SAM Detection
    @Published var isDetectionEnabled: Bool = true // Enable detection by default for testing
    @Published var currentImageSize: CGSize = CGSize(width: 640, height: 480)
    private var samDetector: SAMDetector?
    
    // Core Image context for image processing
    private let ciContext: CIContext
    
    override init() {
        // Initialize CIContext with CPU-based rendering for simulator compatibility
        #if targetEnvironment(simulator)
        ciContext = CIContext(options: [.useSoftwareRenderer: true])
        #else
        ciContext = CIContext()
        #endif
        
        super.init()
        samDetector = SAMDetector()
        setupServer()
    }
    
    deinit {
        stopServer()
    }
    
    func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupSession()
                }
            }
        default:
            break
        }
    }
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVCaptureSession()
            session.sessionPreset = .high
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { 
                print("🔥 CameraService: No camera device available")
                return
            }
            
            // Store device reference for zoom control
            self.currentDevice = device
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print("🔥 CameraService: Error creating camera input: \(error)")
                return
            }
            
            if session.canAddOutput(self.output) {
                session.addOutput(self.output)
            }
            
            self.output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            DispatchQueue.main.async {
                self.session = session
                #if os(iOS)
                // Set zoom limits based on actual device capabilities (iOS only)
                self.maxZoomFactor = min(device.activeFormat.videoMaxZoomFactor, 10.0) // Cap at 10x
                self.minZoomFactor = max(0.5, device.minAvailableVideoZoomFactor) // Support wide-angle if available
                self.zoomFactor = max(self.minZoomFactor, device.videoZoomFactor) // Ensure we start at valid zoom level
                
                print("🔥 Device max zoom: \(device.activeFormat.videoMaxZoomFactor)")
                print("🔥 App zoom range: \(self.minZoomFactor) - \(self.maxZoomFactor)")
                
                // Set initial focus values (iOS only)
                self.isManualFocusEnabled = device.isFocusModeSupported(.locked)
                if device.focusMode == .locked {
                    self.focusDistance = device.lensPosition
                }
                #else
                // macOS doesn't support zoom or manual focus controls
                self.maxZoomFactor = 1.0
                self.minZoomFactor = 1.0
                self.zoomFactor = 1.0
                self.isManualFocusEnabled = false
                self.focusDistance = 0.0
                print("macOS: Camera controls not available")
                #endif
                
                // Set flash availability
                self.isFlashAvailable = device.hasTorch && device.isTorchModeSupported(.on)
            }
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // Update image size for detection overlay
        DispatchQueue.main.async {
            self.currentImageSize = CGSize(width: cgImage.width, height: cgImage.height)
        }
        
        // Run SAM detection if enabled
        if isDetectionEnabled {
            print("🔥 CameraService: Detection enabled - calling SAM detector")
            samDetector?.detectObjects(in: cgImage)
        } else {
            print("🔥 CameraService: Detection disabled")
        }
        
        #if os(iOS)
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }
        #elseif os(macOS)
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) else { return }
        #endif
        
        frameQueue.async(flags: .barrier) {
            self.currentFrame = jpegData
        }
    }
    
    func setZoom(_ factor: CGFloat) {
        #if os(iOS)
        guard let device = currentDevice else { return }
        
        // Clamp the zoom factor to valid range
        let clampedFactor = max(minZoomFactor, min(factor, maxZoomFactor))
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                // Ensure the zoom factor is within device limits (minimum is always 1.0 for most devices)
                let safeFactor = max(1.0, min(clampedFactor, device.activeFormat.videoMaxZoomFactor))
                
                device.videoZoomFactor = safeFactor
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.zoomFactor = device.videoZoomFactor
                }
            } catch {
                print("Error setting zoom: \(error)")
            }
        }
        #else
        // macOS doesn't support zoom
        print("Zoom not supported on macOS")
        #endif
    }
    
    func setManualFocus(_ distance: Float) {
        #if os(iOS)
        guard let device = currentDevice, device.isFocusModeSupported(.locked) else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.focusMode = .locked
                device.setFocusModeLocked(lensPosition: distance, completionHandler: nil)
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.focusDistance = distance
                }
            } catch {
                print("Error setting manual focus: \(error)")
            }
        }
        #else
        // macOS doesn't support manual focus
        print("Manual focus not supported on macOS")
        #endif
    }
    
    func setAutoFocus() {
        guard let device = currentDevice, device.isFocusModeSupported(.continuousAutoFocus) else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.isManualFocusEnabled = false
                }
            } catch {
                print("Error setting auto focus: \(error)")
            }
        }
    }
    
    func enableManualFocus() {
        #if os(iOS)
        guard let device = currentDevice, device.isFocusModeSupported(.locked) else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let currentLensPosition = device.lensPosition
                device.focusMode = .locked
                device.setFocusModeLocked(lensPosition: currentLensPosition, completionHandler: nil)
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.isManualFocusEnabled = true
                    self.focusDistance = currentLensPosition
                }
            } catch {
                print("Error enabling manual focus: \(error)")
            }
        }
        #else
        // macOS doesn't support manual focus
        print("Manual focus not supported on macOS")
        #endif
    }
    
    func toggleFlash() {
        guard let device = currentDevice, device.hasTorch else { return }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if self.isFlashEnabled {
                    device.torchMode = .off
                } else {
                    device.torchMode = .on
                }
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.isFlashEnabled = !self.isFlashEnabled
                }
            } catch {
                print("Error toggling flash: \(error)")
            }
        }
    }
    
    func toggleDetection() {
        isDetectionEnabled.toggle()
        print("🔥 CameraService: Detection toggled to \(isDetectionEnabled)")
        
        // If we're in simulator mode and detection was just enabled, start mock frame generation
        #if targetEnvironment(simulator)
        if isDetectionEnabled {
            print("🔥 CameraService: Starting mock frame generation for simulator")
            startMockFrameGeneration()
        }
        #endif
    }
    
    func getSAMDetector() -> SAMDetector? {
        return samDetector
    }
    
    private func setupServer() {
        serverQueue.async {
            self.startSimpleServer()
        }
    }
    
    private func startSimpleServer() {
        guard !isServerRunning else { return }
        
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket != -1 else {
            print("Failed to create socket")
            return
        }
        
        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        var serverAddr = sockaddr_in()
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = UInt16(8080).bigEndian
        serverAddr.sin_addr.s_addr = INADDR_ANY
        
        let bindResult = withUnsafePointer(to: &serverAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult == 0 else {
            print("Failed to bind socket")
            close(serverSocket)
            serverSocket = -1
            return
        }
        
        guard listen(serverSocket, 5) == 0 else {
            print("Failed to listen on socket")
            close(serverSocket)
            serverSocket = -1
            return
        }
        
        isServerRunning = true
        print("Server started on port 8080")
        print("Stream available at: http://\(getWiFiAddress() ?? "localhost"):8080/stream")
        
        while isServerRunning && serverSocket != -1 {
            let clientSocket = accept(serverSocket, nil, nil)
            if clientSocket != -1 && isServerRunning {
                DispatchQueue.global().async {
                    self.handleClient(clientSocket: clientSocket)
                }
            }
        }
    }
    
    private func stopServer() {
        isServerRunning = false
        if serverSocket != -1 {
            close(serverSocket)
            serverSocket = -1
        }
    }
    
    private func handleClient(clientSocket: Int32) {
        defer { close(clientSocket) }
        
        // Set socket options to prevent broken pipe errors
        var nosigpipe = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
        
        guard bytesRead > 0 else { return }
        
        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        
        if request.contains("GET /stream") {
            let boundary = "frame"
            let headers = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=\(boundary)\r\nConnection: keep-alive\r\nCache-Control: no-cache\r\n\r\n"
            
            sendAll(clientSocket, headers)
            
            while true {
                var frameData: Data?
                frameQueue.sync {
                    frameData = self.currentFrame
                }
                
                if let frameData = frameData {
                    let frameHeader = "--\(boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(frameData.count)\r\n\r\n"
                    sendAll(clientSocket, frameHeader)
                    
                    // Send binary frame data
                    var sent = 0
                    let total = frameData.count
                    while sent < total {
                        let result = frameData.withUnsafeBytes { bytes in
                            let ptr = bytes.bindMemory(to: UInt8.self)
                            return send(clientSocket, ptr.baseAddress! + sent, total - sent, MSG_NOSIGNAL)
                        }
                        if result <= 0 { break }
                        sent += result
                    }
                    
                    sendAll(clientSocket, "\r\n")
                }
                usleep(100000) // ~10 FPS
            }
        } else if request.contains("GET /test") {
            let body = "Camera server is working!"
            let testResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\n\r\n\(body)"
            sendAll(clientSocket, testResponse)
        } else if request.contains("GET /discover") {
            let ipAddress = getWiFiAddress() ?? "Unknown"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(ipAddress.count)\r\n\r\n\(ipAddress)"
            sendAll(clientSocket, response)
        } else {
            let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n"
            sendAll(clientSocket, response)
        }
    }
    
    private func sendAll(_ socket: Int32, _ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        var sent = 0
        let total = data.count
        
        while sent < total {
            let result = data.withUnsafeBytes { bytes in
                let ptr = bytes.bindMemory(to: UInt8.self)
                return send(socket, ptr.baseAddress! + sent, total - sent, MSG_NOSIGNAL)
            }
            
            if result <= 0 { break }
            sent += result
        }
    }
    
    private func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let currentPtr = ptr {
            let interface = currentPtr.pointee
            
            if let addr = interface.ifa_addr {
                let addrFamily = addr.pointee.sa_family
                
                if addrFamily == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let result = getnameinfo(addr,
                                socklen_t(addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                socklen_t(0),
                                NI_NUMERICHOST)
                    
                    if result == 0 {
                        let ip = String(cString: hostname)
                        if ip != "127.0.0.1" && (ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.")) {
                            address = ip
                            break
                        }
                    }
                }
            }
            
            ptr = interface.ifa_next
        }
        return address
    }
}
