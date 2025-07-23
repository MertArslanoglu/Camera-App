import cv2
import requests
import numpy as np

# Direct IP address of the iPhone camera server
STREAM_URL = "http://192.168.178.71:8080/stream"


def read_mjpeg_stream():
    """Read MJPEG stream using requests library with Safari-like headers"""
    headers = {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2.1 Safari/605.1.15",
        "Accept": "*/*",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "identity",  # Don't compress the stream
        "Connection": "keep-alive",
        "Cache-Control": "no-cache",
    }

    try:
        print("Attempting to connect with Safari-like headers...")
        response = requests.get(STREAM_URL, stream=True, timeout=10, headers=headers)
        response.raise_for_status()
        print("Successfully connected to stream!")

        bytes_data = b""
        for chunk in response.iter_content(chunk_size=1024):
            bytes_data += chunk

            # Look for JPEG frame boundaries
            a = bytes_data.find(b"\xff\xd8")  # JPEG start
            b = bytes_data.find(b"\xff\xd9")  # JPEG end

            if a != -1 and b != -1:
                # Extract the JPEG frame
                jpg = bytes_data[a : b + 2]
                bytes_data = bytes_data[b + 2 :]

                # Decode the JPEG frame
                frame = cv2.imdecode(
                    np.frombuffer(jpg, dtype=np.uint8), cv2.IMREAD_COLOR
                )
                if frame is not None:
                    yield frame

    except Exception as e:
        print(f"Error reading stream: {e}")
        return


def main():
    print(f"Connecting to: {STREAM_URL}")
    print("Using requests library with Safari-like headers...")

    # Window settings
    window_name = "iPhone Camera Stream"
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    fullscreen = False

    print("Press 'q' to quit, 'f' for fullscreen, ESC to exit fullscreen")

    try:
        for frame in read_mjpeg_stream():
            if frame is None:
                continue

            # Display the frame
            cv2.imshow(window_name, frame)

            # Handle key presses
            key = cv2.waitKey(1) & 0xFF

            if key == ord("q"):  # Quit
                break
            elif key == ord("f"):  # Toggle fullscreen
                if fullscreen:
                    cv2.setWindowProperty(
                        window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_NORMAL
                    )
                    fullscreen = False
                else:
                    cv2.setWindowProperty(
                        window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_FULLSCREEN
                    )
                    fullscreen = True
            elif key == 27:  # ESC key - exit fullscreen
                if fullscreen:
                    cv2.setWindowProperty(
                        window_name, cv2.WND_PROP_FULLSCREEN, cv2.WINDOW_NORMAL
                    )
                    fullscreen = False

    except KeyboardInterrupt:
        print("\nStream interrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        print("Make sure:")
        print("1. iPhone app is running")
        print("2. iPhone is at IP 192.168.178.71")
        print("3. Both devices are on the same network")

    # Clean up
    cv2.destroyAllWindows()
    print("Stream viewer closed")


if __name__ == "__main__":
    main()
