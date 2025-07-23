# SAM Object Detection Integration

## Overview
This camera app now includes real-time object detection capabilities inspired by SAM (Segment Anything Model). The implementation uses Core ML and Vision framework for on-device inference.

## Features
- **Real-time Object Detection**: Detect objects in live camera feed
- **Bounding Box Visualization**: Red boxes around detected objects
- **Confidence Scores**: Shows detection confidence percentage
- **Object Labels**: Displays detected object types
- **Processing Status**: Visual indicator when processing frames

## How to Use

### Enable/Disable Detection
- Tap the **eye icon** in the top-left corner to toggle object detection
- Green eye = Detection enabled
- Crossed-out eye = Detection disabled

### Detection Status
When detection is enabled, you'll see:
- **Processing indicator**: Orange circle when analyzing frames
- **Object counter**: Shows number of detected objects
- **Status text**: "Processing..." or "Detecting Objects"

### Detection Overlays
Detected objects are shown with:
- **Red bounding boxes** around objects
- **Object labels** (e.g., "person", "car", "bottle")
- **Confidence percentages** (only shows objects >50% confidence)

## Technical Implementation

### Current Setup
- Uses Vision framework with Core ML
- Placeholder for YOLOv3 model (actual model file needed)
- Processes frames at ~10 FPS to balance performance
- Thread-safe frame processing

### To Add Real SAM Model
1. Download a SAM-compatible Core ML model
2. Add the `.mlmodelc` file to the app bundle
3. Update `SAMDetector.swift` to load your specific model
4. Modify `setupModel()` function with correct model name

### Performance Considerations
- Detection runs on background queue to maintain camera performance
- Frame processing is throttled to prevent overwhelming the device
- Only processes frames when detection is enabled

## Code Structure
- `SAMDetector.swift`: Core detection logic
- `DetectionOverlayView.swift`: UI overlay for showing results
- `CameraService.swift`: Integration with camera pipeline
- `ContentView.swift`: UI controls and status display

## Future Enhancements
- Segmentation masks (true SAM capability)
- Custom object training
- Detection filtering by object type
- Performance metrics display
- Export detection results

## Notes
- This is a foundation for SAM integration
- Actual SAM models require significant computational resources
- Consider using smaller, optimized models for real-time performance
- Detection accuracy depends on lighting conditions and object visibility

## Troubleshooting

### Metal Framework Errors (Simulator)
If you see errors like:
```
Unable to open mach-O at path: /Library/Caches/com.apple.xbs/Binaries/RenderBox/install/Root/System/Library/PrivateFrameworks/RenderBox.framework/default.metallib Error:2
```

**Solution**: This is a common simulator issue with GPU-accelerated features.

**What we've implemented:**
- Automatic simulator detection using `#if targetEnvironment(simulator)`
- CPU-based Core Image context for simulators
- Mock detection mode to avoid Metal dependencies
- Fallback mechanisms for Core ML model loading

**On Simulator**: Uses mock detection with sample bounding boxes
**On Device**: Uses actual Core ML models with GPU acceleration

### Performance Issues
- **High CPU usage**: Reduce detection frequency or image resolution
- **Memory warnings**: Implement frame skipping during high memory usage
- **Slow detection**: Consider using smaller, optimized models

### Model Loading Issues
- Ensure `.mlmodelc` files are properly added to Xcode project
- Check model compatibility with target iOS version
- Verify model input/output specifications match code expectations
