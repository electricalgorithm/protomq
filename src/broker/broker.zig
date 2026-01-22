const std = @import("std");

/// Topic broker for managing subscriptions and routing messages
pub const TopicBroker = struct {
    allocator: std.mem.Allocator,
    subscriptions: std.StringHashMap(SubscriberList),

    const SubscriberList = std.ArrayList(usize); // List of client IDs

    pub fn init(allocator: std.mem.Allocator) TopicBroker {
        return TopicBroker{
            .allocator = allocator,
            .subscriptions = std.StringHashMap(SubscriberList).init(allocator),
        };
    }

    pub fn deinit(self: *TopicBroker) void {
        var it = self.subscriptions.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.subscriptions.deinit();
    }

    /// Subscribe a client to a topic
    pub fn subscribe(self: *TopicBroker, topic: []const u8, client_id: usize) !void {
        // Get or create subscription list for this topic
        const result = try self.subscriptions.getOrPut(topic);

        if (!result.found_existing) {
            // New topic - create subscriber list
            result.value_ptr.* = .empty;
            // Duplicate the topic string for the hashmap key
            const topic_copy = try self.allocator.dupe(u8, topic);
            result.key_ptr.* = topic_copy;
        }

        // Add client to subscriber list if not already present
        for (result.value_ptr.items) |existing_client| {
            if (existing_client == client_id) {
                return; // Already subscribed
            }
        }

        try result.value_ptr.append(self.allocator, client_id);
    }

    /// Unsubscribe a client from a topic
    pub fn unsubscribe(self: *TopicBroker, topic: []const u8, client_id: usize) !void {
        if (self.subscriptions.getPtr(topic)) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == client_id) {
                    _ = list.swapRemove(i);
                    return;
                }
                i += 1;
            }
        }
    }

    /// Get all subscribers for a topic (including wildcard matches)
    pub fn getSubscribers(self: *TopicBroker, topic: []const u8, allocator: std.mem.Allocator) !std.ArrayList(usize) {
        var result: std.ArrayList(usize) = .empty;
        var seen = std.AutoHashMap(usize, void).init(allocator);
        defer seen.deinit();

        var it = self.subscriptions.iterator();
        while (it.next()) |entry| {
            if (topicMatches(entry.key_ptr.*, topic)) {
                // Add all subscribers from this subscription
                for (entry.value_ptr.items) |client_id| {
                    if (!seen.contains(client_id)) {
                        try result.append(allocator, client_id);
                        try seen.put(client_id, {});
                    }
                }
            }
        }

        return result;
    }

    /// Remove all subscriptions for a client
    pub fn removeClient(self: *TopicBroker, client_id: usize) void {
        var it = self.subscriptions.valueIterator();
        while (it.next()) |list| {
            var i: usize = 0;
            while (i < list.items.len) {
                if (list.items[i] == client_id) {
                    _ = list.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }
    }
};

/// Check if a subscription pattern matches a topic
/// Supports MQTT wildcards:
/// - '+' matches a single level
/// - '#' matches multiple levels (must be at end)
pub fn topicMatches(pattern: []const u8, topic: []const u8) bool {
    return topicMatchesImpl(pattern, topic, 0, 0);
}

fn topicMatchesImpl(pattern: []const u8, topic: []const u8, p_idx: usize, t_idx: usize) bool {
    // Both exhausted - match
    if (p_idx >= pattern.len and t_idx >= topic.len) {
        return true;
    }

    // Pattern exhausted but topic remains - no match
    if (p_idx >= pattern.len) {
        return false;
    }

    // Multi-level wildcard '#' - matches rest of topic
    if (pattern[p_idx] == '#') {
        // '#' must be at end and preceded by '/'
        if (p_idx == pattern.len - 1 and (p_idx == 0 or pattern[p_idx - 1] == '/')) {
            return true;
        }
        return false;
    }

    // Topic exhausted but pattern remains
    if (t_idx >= topic.len) {
        return false;
    }

    // Single-level wildcard '+'
    if (pattern[p_idx] == '+') {
        // Skip to next '/' in topic or end
        var next_t = t_idx;
        while (next_t < topic.len and topic[next_t] != '/') {
            next_t += 1;
        }

        // Find next '/' in pattern or end
        var next_p = p_idx + 1;
        if (next_p < pattern.len and pattern[next_p] == '/') {
            next_p += 1;
        }

        if (next_t < topic.len) {
            // Skip the '/' in topic
            return topicMatchesImpl(pattern, topic, next_p, next_t + 1);
        } else {
            // End of topic
            return topicMatchesImpl(pattern, topic, next_p, next_t);
        }
    }

    // Regular character matching
    if (pattern[p_idx] == topic[t_idx]) {
        return topicMatchesImpl(pattern, topic, p_idx + 1, t_idx + 1);
    }

    return false;
}

// Tests

test "TopicBroker subscribe and getSubscribers" {
    const allocator = std.testing.allocator;
    var broker = TopicBroker.init(allocator);
    defer broker.deinit();

    // Subscribe clients
    try broker.subscribe("sensors/temperature", 1);
    try broker.subscribe("sensors/temperature", 2);
    try broker.subscribe("sensors/humidity", 3);

    // Get subscribers for exact topic
    var subs = try broker.getSubscribers("sensors/temperature", allocator);
    defer subs.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), subs.items.len);
}

test "TopicBroker unsubscribe" {
    const allocator = std.testing.allocator;
    var broker = TopicBroker.init(allocator);
    defer broker.deinit();

    try broker.subscribe("test/topic", 1);
    try broker.subscribe("test/topic", 2);

    try broker.unsubscribe("test/topic", 1);

    var subs = try broker.getSubscribers("test/topic", allocator);
    defer subs.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), subs.items.len);
    try std.testing.expectEqual(@as(usize, 2), subs.items[0]);
}

test "topic matching - exact" {
    try std.testing.expect(topicMatches("sensors/temp", "sensors/temp"));
    try std.testing.expect(!topicMatches("sensors/temp", "sensors/humidity"));
}

test "topic matching - single level wildcard" {
    try std.testing.expect(topicMatches("sensors/+/temperature", "sensors/room1/temperature"));
    try std.testing.expect(topicMatches("sensors/+/temperature", "sensors/room2/temperature"));
    try std.testing.expect(!topicMatches("sensors/+/temperature", "sensors/room1/humidity"));
    try std.testing.expect(!topicMatches("sensors/+/temperature", "sensors/room1/sub/temperature"));
}

test "topic matching - multi level wildcard" {
    try std.testing.expect(topicMatches("sensors/#", "sensors/temp"));
    try std.testing.expect(topicMatches("sensors/#", "sensors/room/temp"));
    try std.testing.expect(topicMatches("sensors/#", "sensors/room/sub/temp"));
    try std.testing.expect(!topicMatches("sensors/#", "devices/temp"));
}

test "topic matching - combined wildcards" {
    try std.testing.expect(topicMatches("+/+/temperature", "sensors/room1/temperature"));
    try std.testing.expect(topicMatches("sensors/+/#", "sensors/room1/temp"));
    try std.testing.expect(topicMatches("sensors/+/#", "sensors/room1/sub/temp"));
}
