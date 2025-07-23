import SwiftUI

struct DetectionOverlayView: View {
    let detectedObjects: [SAMDetector.DetectedObject]
    let imageSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(detectedObjects) { object in
                DetectionBoxView(
                    object: object,
                    containerSize: geometry.size,
                    imageSize: imageSize
                )
            }
        }
    }
}

struct DetectionBoxView: View {
    let object: SAMDetector.DetectedObject
    let containerSize: CGSize
    let imageSize: CGSize
    
    private var scaledBoundingBox: CGRect {
        return CGRect(
            x: object.boundingBox.minX * containerSize.width,
            y: (1 - object.boundingBox.maxY) * containerSize.height,
            width: object.boundingBox.width * containerSize.width,
            height: object.boundingBox.height * containerSize.height
        )
    }
    
    var body: some View {
        ZStack {
            // Display segmentation mask if available
            if let mask = object.mask {
                #if os(iOS)
                Image(uiImage: mask)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .clipped()
                    .allowsHitTesting(false)
                #elseif os(macOS)
                Image(nsImage: mask)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .clipped()
                    .allowsHitTesting(false)
                #endif
            }
            
            // Bounding box rectangle
            Rectangle()
                .stroke(Color.red, lineWidth: 2)
                .frame(width: scaledBoundingBox.width, height: scaledBoundingBox.height)
                .position(
                    x: scaledBoundingBox.midX,
                    y: scaledBoundingBox.midY
                )
            
            // Labels with boundary clamping
            HStack {
                Text("\(object.label)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(4)
                
                Text("\(Int(object.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(3)
                
                // Show mask indicator if available
                if object.mask != nil {
                    Image(systemName: "camera.metering.matrix")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(3)
                }
                
                Spacer()
            }
            .position(
                x: min(max(scaledBoundingBox.midX, 60), containerSize.width - 60),
                y: max(scaledBoundingBox.minY - 15, 20)
            )
        }
    }
}

#Preview {
    DetectionOverlayView(
        detectedObjects: [
            SAMDetector.DetectedObject(
                boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.3, height: 0.4),
                confidence: 0.85,
                label: "person",
                mask: nil
            )
        ],
        imageSize: CGSize(width: 640, height: 480)
    )
}
