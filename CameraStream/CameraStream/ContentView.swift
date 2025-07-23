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
        .onAppear {
            cameraService.checkForPermissions()
        }
    }
}

#Preview {
    ContentView()
}
