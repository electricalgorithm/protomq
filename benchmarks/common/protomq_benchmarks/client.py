"""
SimpleMQTTClient - Minimal MQTT 3.1.1 client for benchmarking

A lightweight async MQTT client with only the essential features needed
for performance testing. Avoids overhead from full-featured libraries.
"""

import asyncio
import struct


class SimpleMQTTClient:
    """Minimal MQTT 3.1.1 client for benchmarking"""

    def __init__(self, host="127.0.0.1", port=1883, client_id="bench-client"):
        self.host = host
        self.port = port
        self.client_id = client_id
        self.reader = None
        self.writer = None
        self.connected = False
        self.messages_received = 0

    async def connect(self):
        """Connect to MQTT broker and send CONNECT packet"""
        try:
            self.reader, self.writer = await asyncio.open_connection(
                self.host, self.port
            )

            # MQTT CONNECT packet
            protocol_name = b"\x00\x04MQTT"
            protocol_level = b"\x04"
            connect_flags = b"\x02"  # Clean session
            keep_alive = b"\x00\x3c"  # 60 seconds

            payload = struct.pack("!H", len(self.client_id)) + self.client_id.encode()
            variable_header = protocol_name + protocol_level + connect_flags + keep_alive

            remaining_length = len(variable_header) + len(payload)
            fixed_header = struct.pack("!BB", 0x10, remaining_length)

            packet = fixed_header + variable_header + payload
            self.writer.write(packet)
            await self.writer.drain()

            # Wait for CONNACK
            connack = await asyncio.wait_for(self.reader.readexactly(4), timeout=5.0)
            if connack[0] == 0x20:
                self.connected = True
                return True
        except Exception:
            pass
        return False

    async def subscribe(self, topic):
        """Subscribe to a topic"""
        if not self.connected:
            return False

        try:
            packet_id = b"\x00\x01"
            payload = struct.pack("!H", len(topic)) + topic.encode() + b"\x00"
            remaining_length = len(packet_id) + len(payload)
            fixed_header = struct.pack("!BB", 0x82, remaining_length)

            packet = fixed_header + packet_id + payload
            self.writer.write(packet)
            await self.writer.drain()

            # Wait for SUBACK
            suback = await asyncio.wait_for(self.reader.readexactly(5), timeout=5.0)
            return suback[0] == 0x90
        except Exception:
            return False

    async def publish(self, topic, message):
        """Publish a message to a topic"""
        if not self.connected:
            return False

        try:
            var_header = struct.pack("!H", len(topic)) + topic.encode()
            payload = message if isinstance(message, bytes) else message.encode()
            remaining_length = len(var_header) + len(payload)

            # Handle larger messages with multi-byte remaining length encoding
            if remaining_length < 128:
                fixed_header = bytes([0x30, remaining_length])
            else:
                # Encode remaining length as variable-length integer
                rl_bytes = []
                rl = remaining_length
                while rl > 0:
                    byte = rl % 128
                    rl = rl // 128
                    if rl > 0:
                        byte |= 0x80
                    rl_bytes.append(byte)
                fixed_header = bytes([0x30] + rl_bytes)

            packet = fixed_header + var_header + payload
            self.writer.write(packet)
            await self.writer.drain()
            return True
        except Exception:
            return False

    async def wait_for_message(self, timeout=None):
        """Wait for and parse an incoming PUBLISH message"""
        try:
            # Read fixed header
            if timeout:
                header = await asyncio.wait_for(
                    self.reader.readexactly(1), timeout=timeout
                )
            else:
                header = await self.reader.readexactly(1)

            # Check if it's a PUBLISH packet (0x30)
            if (header[0] & 0xF0) == 0x30:
                # Read remaining length
                rem_len = await self.reader.readexactly(1)
                # Read the rest of the packet
                data = await self.reader.readexactly(rem_len[0])
                # Parse topic length and extract message
                topic_len = struct.unpack("!H", data[:2])[0]
                msg = data[2 + topic_len :]
                return msg.decode()
            return None
        except Exception:
            return None

    async def disconnect(self):
        """Send DISCONNECT packet and close connection"""
        if self.writer:
            try:
                self.writer.write(b"\xe0\x00")  # DISCONNECT packet
                await self.writer.drain()
                self.writer.close()
                await self.writer.wait_closed()
            except Exception:
                pass
        self.connected = False
