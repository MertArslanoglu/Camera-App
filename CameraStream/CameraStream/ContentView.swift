//
//  ContentView.swift
//  CameraStream
//
//  Created by Mert Arslanoğlu on 23.07.25.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var cameraService = CameraService()

    var body: some View {
        ZStack {
            Group {
                if let session = cameraService.session {
                    ZStack {
                        CameraView(session: session)
                            .ignoresSafeArea()
                            .onAppear {
                                cameraService.sessionQueue.async {
                                    session.startRunning()
                                }
                            }
                            .onDisappear {
                                cameraService.sessionQueue.async {
                                    session.stopRunning()
                                }
                            }
                        
                        // SAM Detection Overlay
                        if cameraService.isDetectionEnabled, let samDetector = cameraService.getSAMDetector() {
                            SAMDetectionOverlay(samDetector: samDetector, imageSize: cameraService.currentImageSize)
                                .allowsHitTesting(false)
                        }
                    }
                } else {
                    Text("Camera not available")
                }
            }
            
            // Camera Controls Overlay
            VStack {
                // Top controls (Flash and SAM Detection)
                HStack {
                    // SAM Detection toggle
                    Button(action: {
                        cameraService.toggleDetection()
                    }) {
                        Image(systemName: cameraService.isDetectionEnabled ? "eye.fill" : "eye.slash.fill")
                            .font(.title2)
                            .foregroundColor(cameraService.isDetectionEnabled ? .green : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Flash control button
                    if cameraService.isFlashAvailable {
                        Button(action: {
                            cameraService.toggleFlash()
                        }) {
                            Image(systemName: cameraService.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                                .font(.title2)
                                .foregroundColor(cameraService.isFlashEnabled ? .yellow : .white)
                                .padding(12)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                
                Spacer()
                
                VStack(spacing: 15) {
                    // Detection Status (if enabled)
                    if cameraService.isDetectionEnabled, let samDetector = cameraService.getSAMDetector() {
                        SAMStatusView(samDetector: samDetector)
                    }
                    // Zoom Control
                    VStack(spacing: 10) {
                        Text("Zoom: \(String(format: "%.1fx", cameraService.zoomFactor))")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                        
                        HStack {
                            Text("\(String(format: "%.1fx", cameraService.minZoomFactor))")
                                .font(.caption)
                                .foregroundColor(.white)
                                .bold()
                            
                            Slider(
                                value: Binding(
                                    get: { cameraService.zoomFactor },
                                    set: { cameraService.setZoom($0) }
                                ),
                                in: cameraService.minZoomFactor...cameraService.maxZoomFactor
                            )
                            .accentColor(.white)
                            .frame(height: 40)
                            
                            Text("\(String(format: "%.0fx", cameraService.maxZoomFactor))")
                                .font(.caption)
                                .foregroundColor(.white)
                                .bold()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(15)
                    }
                    
                    // Focus Control
                    VStack(spacing: 10) {
                        HStack {
                            Text("Focus:")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: {
                                if cameraService.isManualFocusEnabled {
                                    cameraService.setAutoFocus()
                                } else {
                                    cameraService.enableManualFocus()
                                }
                            }) {
                                Text(cameraService.isManualFocusEnabled ? "Auto" : "Manual")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                        
                        if cameraService.isManualFocusEnabled {
                            HStack {
                                Text("Near")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .bold()
                                
                                Slider(
                                    value: Binding(
                                        get: { cameraService.focusDistance },
                                        set: { cameraService.setManualFocus($0) }
                                    ),
                                    in: 0.0...1.0
                                )
                                .accentColor(.yellow)
                                .frame(height: 40)
                                
                                Text("Far")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .bold()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(15)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            cameraService.checkForPermissions()
        }
    }
}

// Wrapper view to properly observe SAM detector changes
struct SAMDetectionOverlay: View {
    @ObservedObject var samDetector: SAMDetector
    let imageSize: CGSize
    
    var body: some View {
        DetectionOverlayView(
            detectedObjects: samDetector.detectedObjects,
            imageSize: imageSize
        )
    }
}

// Status view for SAM detection
struct SAMStatusView: View {
    @ObservedObject var samDetector: SAMDetector
    
    var body: some View {
        HStack {
            Circle()
                .fill(samDetector.isProcessing ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            
            Text(samDetector.isProcessing ? "Processing..." : "Detecting Objects")
                .font(.caption)
                .foregroundColor(.white)
            
            Spacer()
            
            Text("\(samDetector.detectedObjects.count) objects")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}

#Preview {
    ContentView()
}
