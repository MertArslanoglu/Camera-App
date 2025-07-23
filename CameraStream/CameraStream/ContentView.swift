//
//  ContentView.swift
//  CameraStream
//
//  Created by Mert Arslanoğlu on 23.07.25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraService = CameraService()

    var body: some View {
        ZStack {
            Group {
                if let session = cameraService.session {
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
                } else {
                    Text("Camera not available")
                }
            }
            
            // Camera Controls Overlay
            VStack {
                // Flash control button in top area
                HStack {
                    Spacer()
                    
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

#Preview {
    ContentView()
}
