import asyncio
import time
import struct
import psutil
import json

class SimpleMQTTClient:
    def __init__(self, host='127.0.0.1', port=1883, client_id='bench-client'):
        self.host = host
        self.port = port
        self.client_id = client_id
        self.reader = None
        self.writer = None

    async def connect(self):
        self.reader, self.writer = await asyncio.open_connection(self.host, self.port)
        
        # Fixed Header: Connect (0x10), Remaining Length
        # Variable Header: Protocol Name (0004 'MQTT'), Protocol Level (04), Connect Flags (02 = Clean Session), Keep Alive (003c = 60s)
        # Payload: Client ID
        
        protocol_name = b'\x00\x04MQTT'
        protocol_level = b'\x04'
        connect_flags = b'\x02'
        keep_alive = b'\x00\x3c'
        
        payload = struct.pack('!H', len(self.client_id)) + self.client_id.encode()
        variable_header = protocol_name + protocol_level + connect_flags + keep_alive
        
        remaining_length = len(variable_header) + len(payload)
        fixed_header = struct.pack('!BB', 0x10, remaining_length)
        
        packet = fixed_header + variable_header + payload
        self.writer.write(packet)
        await self.writer.drain()
        
        # Wait for CONNACK
        connack = await self.reader.readexactly(4)
        if connack[0] != 0x20:
            raise Exception("Failed to connect")

    async def subscribe(self, topic):
        # Fixed Header: Subscribe (0x82), Remaining Length
        # Variable Header: Packet Identifier (0001)
        # Payload: Topic Filter, Requested QoS (0)
        
        packet_id = b'\x00\x01'
        payload = struct.pack('!H', len(topic)) + topic.encode() + b'\x00'
        remaining_length = len(packet_id) + len(payload)
        fixed_header = struct.pack('!BB', 0x82, remaining_length)
        
        packet = fixed_header + packet_id + payload
        self.writer.write(packet)
        await self.writer.drain()
        
        # Wait for SUBACK
        suback = await self.reader.readexactly(5)
        if suback[0] != 0x90:
            raise Exception("Failed to subscribe")

    async def publish(self, topic, message):
        # Fixed Header: Publish (0x30), Remaining Length
        # Variable Header: Topic Name
        # Payload: Message
        
        var_header = struct.pack('!H', len(topic)) + topic.encode()
        payload = message.encode()
        remaining_length = len(var_header) + len(payload)
        fixed_header = bytes([0x30, remaining_length]) # Simplified for small lengths
        
        packet = fixed_header + var_header + payload
        self.writer.write(packet)
        await self.writer.drain()

    async def wait_for_message(self):
        # Very simplified publish packet reading
        header = await self.reader.readexactly(1)
        if (header[0] & 0xF0) == 0x30:
            rem_len = await self.reader.readexactly(1) # Assuming < 128
            data = await self.reader.readexactly(rem_len[0])
            topic_len = struct.unpack('!H', data[:2])[0]
            msg = data[2 + topic_len:]
            return msg.decode()
        return None

    async def disconnect(self):
        if self.writer:
            self.writer.write(b'\xe0\x00') # Fixed Header: Disconnect (0xe0), 0 length
            await self.writer.drain()
            self.writer.close()
            await self.writer.wait_closed()

async def benchmark_concurrency(target_clients=100):
    print(f"--- Concurrency Test: {target_clients} clients ---")
    clients = []
    start_time = time.time()
    
    for i in range(target_clients):
        client = SimpleMQTTClient(client_id=f"bench-{i}")
        try:
            await client.connect()
            clients.append(client)
            if (i + 1) % 10 == 0:
                print(f"Connected {i + 1} clients...")
        except Exception as e:
            print(f"Failed to connect client {i}: {e}")
            break
    
    duration = time.time() - start_time
    print(f"Successfully connected {len(clients)} clients in {duration:.2f}s")
    
    server_pid = None
    for proc in psutil.process_iter(['name']):
        if proc.info['name'] == 'mqtt-server':
            server_pid = proc.pid
            break
    
    if server_pid:
        process = psutil.Process(server_pid)
        mem_info = process.memory_info()
        print(f"Server RSS Memory: {mem_info.rss / 1024 / 1024:.2f} MB")
    else:
        print("Could not find mqtt-server process for memory measurement.")

    # Keep alive for a bit
    await asyncio.sleep(2)
    
    # Cleanup
    print("Disconnecting clients...")
    for client in clients:
        await client.disconnect()
    
    return len(clients)

async def benchmark_latency(warmup=5, trials=50):
    print(f"--- Latency Test: {trials} trials ---")
    sub = SimpleMQTTClient(client_id="bench-sub")
    pub = SimpleMQTTClient(client_id="bench-pub")
    await sub.connect()
    await pub.connect()
    
    topic = "bench/latency"
    await sub.subscribe(topic)
    
    # Warmup
    for _ in range(warmup):
        await pub.publish(topic, "warmup")
        await sub.wait_for_message()
        
    latencies = []
    for i in range(trials):
        msg = f"ping-{i}"
        start = time.perf_counter()
        await pub.publish(topic, msg)
        received = await sub.wait_for_message()
        end = time.perf_counter()
        
        if received == msg:
            latencies.append((end - start) * 1000) # Convert to ms
        else:
            print(f"Unexpected message received: {received}")
            
    latencies.sort()
    p50 = latencies[len(latencies)//2]
    p99 = latencies[int(len(latencies)*0.99)]
    avg = sum(latencies) / len(latencies)
    
    print(f"Latency (ms): Avg={avg:.2f}, P50={p50:.2f}, P99={p99:.2f}")
    
    await sub.disconnect()
    await pub.disconnect()
    return p50, p99

async def main():
    # Wait for server to be ready (caller should start the server)
    await asyncio.sleep(1)
    
    conn_count = await benchmark_concurrency(100)
    p50, p99 = await benchmark_latency(trials=100)
    
    results = {
        "concurrent_connections": conn_count,
        "latency_p50_ms": p50,
        "latency_p99_ms": p99
    }
    
    with open("benchmarks/verified_results.json", "w") as f:
        json.dump(results, f, indent=4)

if __name__ == "__main__":
    asyncio.run(main())
