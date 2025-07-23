import cv2
import socket
import requests
from concurrent.futures import ThreadPoolExecutor, as_completed


def get_local_network_range():
    """Get the local network IP range"""
    try:
        # Connect to a remote server to get local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        local_ip = s.getsockname()[0]
        s.close()

        # Extract network range (assumes /24 subnet)
        ip_parts = local_ip.split(".")
        network_base = f"{ip_parts[0]}.{ip_parts[1]}.{ip_parts[2]}"
        return network_base, local_ip
    except Exception:
        return "192.168.1", "192.168.1.100"


def check_camera_server(ip):
    """Check if there's a camera server at the given IP"""
    try:
        response = requests.get(f"http://{ip}:8080/discover", timeout=1)
        if response.status_code == 200:
            print(f"✓ Found server at {ip}: {response.text}")
            return ip
    except requests.exceptions.ConnectTimeout:
        pass  # Expected for most IPs
    except requests.exceptions.ConnectionError:
        pass  # Expected for most IPs
    except Exception as e:
        # Only print unexpected errors
        if "Connection refused" not in str(e) and "timeout" not in str(e).lower():
            print(f"Unexpected error checking {ip}: {e}")
    return None


def discover_camera_server():
    """Discover camera server on the local network"""
    network_base, local_ip = get_local_network_range()
    print(f"Local IP: {local_ip}")
    print(f"Scanning network {network_base}.x for camera servers...")

    # Generate list of IPs to check (skip our own IP)
    ips_to_check = []
    for i in range(1, 255):
        ip = f"{network_base}.{i}"
        if ip != local_ip:
            ips_to_check.append(ip)

    # Also check common hotspot ranges
    common_ranges = ["10.171.9", "172.20.10", "192.168.1"]
    for range_base in common_ranges:
        if range_base != network_base:
            print(f"Also scanning {range_base}.x (common hotspot range)...")
            for i in range(1, 255):
                ip = f"{range_base}.{i}"
                if ip != local_ip:
                    ips_to_check.append(ip)

    print(f"Checking {len(ips_to_check)} IP addresses...")

    # Use threading to check multiple IPs concurrently
    with ThreadPoolExecutor(max_workers=50) as executor:
        futures = {executor.submit(check_camera_server, ip): ip for ip in ips_to_check}

        for future in as_completed(futures):
            result = future.result()
            if result:
                print(f"Found camera server at: {result}")
                return result

    print("No camera server found on the network")
    return None


def main():
    print("Connecting to iPhone camera server...")

    # Use the known server IP
    server_ip = "192.168.178.71"

    # Test if server is accessible
    print(f"Testing connection to {server_ip}...")
    test_response = check_camera_server(server_ip)

    if not test_response:
        print(f"Cannot connect to camera server at {server_ip}")
        print("Please check that:")
        print("1. iPhone app is running")
        print("2. Both devices are on the same network")
        print("3. Network allows device-to-device communication")

        # Try discovery as fallback
        print("\nTrying network discovery as fallback...")
        server_ip = discover_camera_server()
        if not server_ip:
            return

    stream_url = f"http://{server_ip}:8080/stream"
    print(f"Connecting to camera stream at: {stream_url}")

    # Create a VideoCapture object
    cap = cv2.VideoCapture(stream_url)

    if not cap.isOpened():
        print("Error: Could not open video stream")
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
