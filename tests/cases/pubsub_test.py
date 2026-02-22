import socket
import time
import struct
import sys

def encode_string(s):
    encoded = s.encode('utf-8')
    return struct.pack("!H", len(encoded)) + encoded

def create_connect(client_id):
    # Fixed header: CONNECT (1<<4), remaining length
    var_header = b"\x00\x04MQTT\x04\x02\x00\x3C" # Protocol name, level 4, flags 0x02, keepalive 60
    payload = encode_string(client_id)
    remaining_length = len(var_header) + len(payload)
    
    header = b"\x10" + bytes([remaining_length])
    return header + var_header + payload

def create_subscribe(packet_id, topic):
    # SUBSCRIBE (8<<4 | 2) = 0x82
    var_header = struct.pack("!H", packet_id)
    payload = encode_string(topic) + b"\x00" # QoS 0
    remaining_length = len(var_header) + len(payload)
    
    header = b"\x82" + bytes([remaining_length])
    return header + var_header + payload

def create_publish(topic, message):
    # PUBLISH (3<<4) = 0x30 (QoS 0)
    var_header = encode_string(topic)
    payload = message.encode('utf-8')
    remaining_length = len(var_header) + len(payload)
    
    header = b"\x30" + bytes([remaining_length])
    return header + var_header + payload

def read_packet(sock):
    # Read fixed header
    byte1 = sock.recv(1)
    if not byte1: return None, None
    
    # Read remaining length
    multiplier = 1
    value = 0
    while True:
        b = sock.recv(1)
        if not b: return None, None
        byte = b[0]
        value += (byte & 127) * multiplier
        multiplier *= 128
        if (byte & 128) == 0:
            break
            
    # Read payload
    payload = b""
    if value > 0:
        payload = sock.recv(value)
        
    packet_type = byte1[0] >> 4
    return packet_type, payload

print("🧪 ProtoMQ Pub/Sub Integration Test")
print("==============================")

# Start Subscriber
try:
    sub_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sub_sock.connect(("localhost", 1883))
    print("✅ Subscriber connected")
    
    # Send CONNECT
    sub_sock.send(create_connect("sub1"))
    type, _ = read_packet(sub_sock)
    if type == 2: # CONNACK
        print("✅ Subscriber received CONNACK")
    else:
        print(f"❌ Expected CONNACK, got {type}")
        sys.exit(1)
        
    # Send SUBSCRIBE
    sub_sock.send(create_subscribe(1, "test/topic"))
    type, _ = read_packet(sub_sock)
    if type == 9: # SUBACK
        print("✅ Subscriber received SUBACK")
    else:
        print(f"❌ Expected SUBACK, got {type}")
        sys.exit(1)

except Exception as e:
    print(f"❌ Subscriber setup failed: {e}")
    sys.exit(1)

# Start Publisher
try:
    pub_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    pub_sock.connect(("localhost", 1883))
    print("✅ Publisher connected")
    
    # Send CONNECT
    pub_sock.send(create_connect("pub1"))
    type, _ = read_packet(pub_sock)
    if type == 2: # CONNACK
        print("✅ Publisher received CONNACK")
    
    # Send PUBLISH
    msg = "Hello from Python!"
    print(f"📤 Publishing: '{msg}'")
    pub_sock.send(create_publish("test/topic", msg))
    
    # Check Subscriber received it
    sub_sock.settimeout(2.0)
    type, payload = read_packet(sub_sock)
    
    if type == 3: # PUBLISH
        # Parse PUBLISH payload (parsing simplified)
        # Topic len (2 bytes), Topic, Payload
        topic_len = struct.unpack("!H", payload[0:2])[0]
        topic = payload[2:2+topic_len].decode('utf-8')
        received_msg = payload[2+topic_len:].decode('utf-8')
        
        print(f"📥 Subscriber received on '{topic}': '{received_msg}'")
        
        if topic == "test/topic" and received_msg == msg:
            print("✅ TEST PASSED: Message received correctly")
        else:
            print("❌ TEST FAILED: Content mismatch")
            sys.exit(1)
    else:
        print(f"❌ Expected PUBLISH, got {type}")
        sys.exit(1)

except Exception as e:
    print(f"❌ Test failed exception: {e}")
    sys.exit(1)
finally:
    sub_sock.close()
    if 'pub_sock' in locals(): pub_sock.close()
