import Foundation
import AVFoundation
import Combine
import CoreImage
import UIKit
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
    
    override init() {
        super.init()
        setupServer()
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
            
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) {
                    session.addInput(input)
                }
            } catch {
                print(error)
                return
            }
            
            if session.canAddOutput(self.output) {
                session.addOutput(self.output)
            }
            
            self.output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            DispatchQueue.main.async {
                self.session = session
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }
        
        currentFrame = jpegData
    }
    
    private func setupServer() {
        serverQueue.async {
            self.startSimpleServer()
        }
    }
    
    private func startSimpleServer() {
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
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult == 0 else {
            print("Failed to bind socket")
            close(serverSocket)
            return
        }
        
        guard listen(serverSocket, 5) == 0 else {
            print("Failed to listen on socket")
            close(serverSocket)
            return
        }
        
        print("Server started on port 8080")
        print("Stream available at: http://\(getWiFiAddress() ?? "localhost"):8080/stream")
        
        while true {
            let clientSocket = accept(serverSocket, nil, nil)
            if clientSocket != -1 {
                DispatchQueue.global().async {
                    self.handleClient(clientSocket: clientSocket)
                }
            }
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
                if let frameData = currentFrame {
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
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let interface = ptr?.pointee {
            defer { ptr = interface.ifa_next }
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if ip != "127.0.0.1" {
                    address = ip
                    break
                }
            }
        }
        return address
    }
}
