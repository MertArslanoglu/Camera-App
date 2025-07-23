import cv2

# Replace with your iPhone's IP address from Personal Hotspot
STREAM_URL = "http://10.171.9.250:8080/stream"  # Updated with actual hotspot IP


def main():
    print(f"Connecting to camera stream at: {STREAM_URL}")

    # Create a VideoCapture object
    cap = cv2.VideoCapture(STREAM_URL)

    if not cap.isOpened():
        print("Error: Could not open video stream")
        print("Try using iPhone's Personal Hotspot:")
        print("1. Turn on Personal Hotspot on iPhone")
        print("2. Connect MacBook to iPhone's hotspot")
        print("3. Update STREAM_URL with the new hotspot IP")
        return

    print("Successfully connected to stream. Press 'q' to quit.")

    while True:
        # Read frame from stream
        ret, frame = cap.read()

        if not ret:
            print("Failed to grab frame")
            break

        # Display the frame
        cv2.imshow("iPhone Camera Stream", frame)

        # Break the loop on 'q' key press
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    # Clean up
    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
