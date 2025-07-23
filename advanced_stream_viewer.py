import cv2
import requests
import numpy as np
from threading import Thread
import time


class MJPEGStream:
    def __init__(self, url):
        self.url = url
        self.frame = None
        self.running = False

    def start(self):
        self.running = True
        self.thread = Thread(target=self._read_stream)
        self.thread.start()

    def _read_stream(self):
        try:
            response = requests.get(self.url, stream=True, timeout=10)
            if response.status_code != 200:
                print(f"Failed to connect: HTTP {response.status_code}")
                return

            boundary = None
            buffer = b""

            for chunk in response.iter_content(chunk_size=1024):
                if not self.running:
                    break

                buffer += chunk

                # Find boundary if not found yet
                if boundary is None:
                    if b"boundary=" in buffer:
                        boundary_line = buffer.split(b"boundary=")[1].split(b"\r\n")[0]
                        boundary = b"--" + boundary_line
                        print(f"Found boundary: {boundary}")
                    continue

                # Look for complete frames
                while boundary in buffer:
                    # Find the start and end of a frame
                    start = buffer.find(boundary)
                    if start == -1:
                        break

                    next_boundary = buffer.find(boundary, start + len(boundary))
                    if next_boundary == -1:
                        break

                    # Extract frame data
                    frame_data = buffer[start:next_boundary]

                    # Find the start of JPEG data (after headers)
                    jpeg_start = frame_data.find(b"\xff\xd8")  # JPEG header
                    if jpeg_start != -1:
                        jpeg_data = frame_data[jpeg_start:]

                        # Decode JPEG
                        try:
                            frame_array = np.frombuffer(jpeg_data, dtype=np.uint8)
                            frame = cv2.imdecode(frame_array, cv2.IMREAD_COLOR)
                            if frame is not None:
                                self.frame = frame
                        except Exception as e:
                            print(f"Error decoding frame: {e}")

                    # Remove processed data from buffer
                    buffer = buffer[next_boundary:]

        except Exception as e:
            print(f"Stream error: {e}")
        finally:
            self.running = False

    def read(self):
        return self.frame is not None, self.frame

    def stop(self):
        self.running = False
        if hasattr(self, "thread"):
            self.thread.join()


def main():
    STREAM_URL = "http://192.168.178.71:8080/stream"

    print(f"Connecting to camera stream at: {STREAM_URL}")

    # Test basic connectivity first
    try:
        response = requests.get(STREAM_URL, timeout=5, stream=True)
        print(f"HTTP Response: {response.status_code}")
        print(f"Content-Type: {response.headers.get('content-type', 'Unknown')}")
    except Exception as e:
        print(f"Connection test failed: {e}")
        return

    # Create and start MJPEG stream
    stream = MJPEGStream(STREAM_URL)
    stream.start()

    print("Stream started. Press 'q' to quit.")

    # Wait a moment for first frame
    time.sleep(2)

    while True:
        ret, frame = stream.read()

        if ret and frame is not None:
            cv2.imshow("iPhone Camera Stream", frame)
        else:
            # Show a waiting message
            waiting_frame = np.zeros((480, 640, 3), dtype=np.uint8)
            cv2.putText(
                waiting_frame,
                "Waiting for stream...",
                (50, 240),
                cv2.FONT_HERSHEY_SIMPLEX,
                1,
                (255, 255, 255),
                2,
            )
            cv2.imshow("iPhone Camera Stream", waiting_frame)

        # Break the loop on 'q' key press
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    # Clean up
    stream.stop()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
