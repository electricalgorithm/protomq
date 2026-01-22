const std = @import("std");
const types = @import("types.zig");
const registry = @import("registry.zig");

/// Token types for .proto parsing
const TokenType = enum {
    Identifier,
    Integer,
    String,
    Syntax,
    Package,
    Message,
    Enum,
    Repeated,
    Optional,
    Required,
    Equals,
    SemiColon,
    OpenBrace,
    CloseBrace,
    EOF,
    Unknown,
};

const Token = struct {
    type: TokenType,
    text: []const u8,
    line: usize,
};

/// Simple Tokenizer for .proto files
const Tokenizer = struct {
    source: []const u8,
    index: usize,
    line: usize,

    pub fn init(source: []const u8) Tokenizer {
        return Tokenizer{
            .source = source,
            .index = 0,
            .line = 1,
        };
    }

    pub fn next(self: *Tokenizer) Token {
        self.skipWhitespace();
        if (self.index >= self.source.len) {
            return Token{ .type = .EOF, .text = "", .line = self.line };
        }

        const start = self.index;
        const char = self.source[self.index];

        // Symbols
        if (char == '=') {
            self.index += 1;
            return self.makeToken(.Equals, start);
        }
        if (char == ';') {
            self.index += 1;
            return self.makeToken(.SemiColon, start);
        }
        if (char == '{') {
            self.index += 1;
            return self.makeToken(.OpenBrace, start);
        }
        if (char == '}') {
            self.index += 1;
            return self.makeToken(.CloseBrace, start);
        }
        if (char == '"') {
            return self.parseString();
        }

        // Identifiers / Keywords
        if (std.ascii.isAlphabetic(char) or char == '_') {
            return self.parseIdentifier();
        }

        // Numbers
        if (std.ascii.isDigit(char)) {
            return self.parseNumber();
        }

        self.index += 1;
        return Token{ .type = .Unknown, .text = self.source[start..self.index], .line = self.line };
    }

    fn skipWhitespace(self: *Tokenizer) void {
        while (self.index < self.source.len) {
            const c = self.source[self.index];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.index += 1;
            } else if (c == '\n') {
                self.index += 1;
                self.line += 1;
            } else if (c == '/' and self.index + 1 < self.source.len and self.source[self.index + 1] == '/') {
                // Comment
                while (self.index < self.source.len and self.source[self.index] != '\n') {
                    self.index += 1;
                }
            } else {
                break;
            }
        }
    }

    fn parseString(self: *Tokenizer) Token {
        const start = self.index;
        self.index += 1; // skip quote
        while (self.index < self.source.len and self.source[self.index] != '"') {
            self.index += 1;
        }
        if (self.index < self.source.len) self.index += 1; // skip closing quote
        return Token{ .type = .String, .text = self.source[start + 1 .. self.index - 1], .line = self.line };
    }

    fn parseIdentifier(self: *Tokenizer) Token {
        const start = self.index;
        while (self.index < self.source.len) {
            const c = self.source[self.index];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '.') {
                self.index += 1;
            } else {
                break;
            }
        }
        const text = self.source[start..self.index];
        var tt: TokenType = .Identifier;

        if (std.mem.eql(u8, text, "syntax")) {
            tt = .Syntax;
        } else if (std.mem.eql(u8, text, "package")) {
            tt = .Package;
        } else if (std.mem.eql(u8, text, "message")) {
            tt = .Message;
        } else if (std.mem.eql(u8, text, "repeated")) {
            tt = .Repeated;
        } else if (std.mem.eql(u8, text, "optional")) {
            tt = .Optional;
        } else if (std.mem.eql(u8, text, "required")) {
            tt = .Required;
        }

        return Token{ .type = tt, .text = text, .line = self.line };
    }

    fn parseNumber(self: *Tokenizer) Token {
        const start = self.index;
        while (self.index < self.source.len and std.ascii.isDigit(self.source[self.index])) {
            self.index += 1;
        }
        return Token{ .type = .Integer, .text = self.source[start..self.index], .line = self.line };
    }

    fn makeToken(self: *Tokenizer, tt: TokenType, start: usize) Token {
        return Token{ .type = tt, .text = self.source[start..self.index], .line = self.line };
    }
};

/// Parser for .proto content
pub const ProtoParser = struct {
    allocator: std.mem.Allocator,
    tokenizer: Tokenizer,
    current_token: Token,
    package_name: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) ProtoParser {
        var tokenizer = Tokenizer.init(source);
        const first = tokenizer.next();
        return ProtoParser{
            .allocator = allocator,
            .tokenizer = tokenizer,
            .current_token = first,
        };
    }

    fn advance(self: *ProtoParser) void {
        self.current_token = self.tokenizer.next();
    }

    fn expect(self: *ProtoParser, tt: TokenType) !void {
        if (self.current_token.type == tt) {
            self.advance();
        } else {
            std.debug.print("Expected {}, got {} at line {}\n", .{ tt, self.current_token.type, self.current_token.line });
            return error.UnexpectedToken;
        }
    }

    /// Parse content and register messages
    pub fn parse(self: *ProtoParser, reg: *registry.SchemaRegistry) !void {
        while (self.current_token.type != .EOF) {
            switch (self.current_token.type) {
                .Syntax => try self.parseSyntax(),
                .Package => try self.parsePackage(),
                .Message => try self.parseMessage(reg),
                .SemiColon => self.advance(),
                else => {
                    // Skip unknown or error
                    // std.debug.print("Unexpected token at top level: {s}\n", .{self.current_token.text});
                    self.advance();
                },
            }
        }
    }

    fn parseSyntax(self: *ProtoParser) !void {
        self.advance(); // syntax
        try self.expect(.Equals);
        if (self.current_token.type == .String) {
            // Check "proto3"
            self.advance();
        } else {
            return error.ExpectedSyntaxVer;
        }
        try self.expect(.SemiColon);
    }

    fn parsePackage(self: *ProtoParser) !void {
        self.advance(); // package
        if (self.current_token.type == .Identifier) {
            // Store package name
            // For now we don't store it persistently in this struct because parser is transient?
            // Or we should?
            // Let's assume simplistic package handling for now
            self.package_name = self.current_token.text;
            self.advance();
        } else {
            return error.ExpectedPackageName;
        }
        try self.expect(.SemiColon);
    }

    fn parseMessage(self: *ProtoParser, reg: *registry.SchemaRegistry) !void {
        self.advance(); // message
        if (self.current_token.type != .Identifier) return error.ExpectedMessageName;

        const short_name = self.current_token.text;
        self.advance();

        try self.expect(.OpenBrace);

        var msg_def = try types.MessageDefinition.init(self.allocator, short_name);
        errdefer msg_def.deinit(self.allocator);

        // Populate full name if package exists?
        // Current implementation of MessageDefinition only stores name.
        // We should probably store fully qualified name in registry key.

        while (self.current_token.type != .CloseBrace and self.current_token.type != .EOF) {
            try self.parseField(&msg_def);
        }

        try self.expect(.CloseBrace);

        // Register the message pointer
        const ptr = try self.allocator.create(types.MessageDefinition);
        ptr.* = msg_def;
        try reg.registerMessage(ptr);
    }

    fn parseField(self: *ProtoParser, msg: *types.MessageDefinition) !void {
        // Label?
        var label: types.FieldLabel = .Optional;
        if (self.current_token.type == .Repeated) {
            label = .Repeated;
            self.advance();
        } else if (self.current_token.type == .Optional) {
            label = .Optional;
            self.advance();
        } else if (self.current_token.type == .Required) {
            label = .Required;
            self.advance();
        }

        // Type
        if (self.current_token.type != .Identifier) return error.ExpectedFieldType;
        const type_str = self.current_token.text;
        self.advance();

        // Name
        if (self.current_token.type != .Identifier) return error.ExpectedFieldName;
        const name = self.current_token.text;
        self.advance();

        try self.expect(.Equals);

        // Tag
        if (self.current_token.type != .Integer) return error.ExpectedFieldTag;
        const tag = try std.fmt.parseInt(u32, self.current_token.text, 10);
        self.advance();

        try self.expect(.SemiColon);

        // Resolve Type
        const field_type = mapType(type_str);

        const field = types.FieldDefinition{
            .name = try self.allocator.dupe(u8, name),
            .tag = tag,
            .type = field_type,
            .label = label,
            .type_name = if (field_type == .Message) try self.allocator.dupe(u8, type_str) else null,
        };

        try msg.fields.put(tag, field);
    }

    fn mapType(name: []const u8) types.FieldType {
        if (std.mem.eql(u8, name, "double")) return .Double;
        if (std.mem.eql(u8, name, "float")) return .Float;
        if (std.mem.eql(u8, name, "int32")) return .Int32;
        if (std.mem.eql(u8, name, "int64")) return .Int64;
        if (std.mem.eql(u8, name, "uint32")) return .UInt32;
        if (std.mem.eql(u8, name, "uint64")) return .UInt64;
        //        if (std.mem.eql(u8, name, "sint32")) return .SInt32;
        //        if (std.mem.eql(u8, name, "sint64")) return .SInt64;
        if (std.mem.eql(u8, name, "fixed32")) return .Fixed32;
        if (std.mem.eql(u8, name, "fixed64")) return .Fixed64;
        if (std.mem.eql(u8, name, "bool")) return .Bool;
        if (std.mem.eql(u8, name, "string")) return .String;
        if (std.mem.eql(u8, name, "bytes")) return .Bytes;

        // Default to message if unknown primitive
        return .Message;
    }
};

test "Proto Parser - Basic Message" {
    const allocator = std.testing.allocator;
    var reg = registry.SchemaRegistry.init(allocator);
    defer reg.deinit();

    const proto_source =
        \\syntax = "proto3";
        \\package test.pkg;
        \\
        \\message Person {
        \\  string name = 1;
        \\  int32 id = 2;
        \\  repeated string email = 3;
        \\}
    ;

    var p = ProtoParser.init(allocator, proto_source);
    try p.parse(&reg);

    // Verify
    const msg = reg.getMessage("Person");
    try std.testing.expect(msg != null);

    const def = msg.?;
    try std.testing.expectEqualStrings("Person", def.name);

    const f1 = def.fields.get(1).?;
    try std.testing.expectEqualStrings("name", f1.name);
    try std.testing.expectEqual(types.FieldType.String, f1.type);

    const f2 = def.fields.get(2).?;
    try std.testing.expectEqualStrings("id", f2.name);
    try std.testing.expectEqual(types.FieldType.Int32, f2.type);

    const f3 = def.fields.get(3).?;
    try std.testing.expectEqualStrings("email", f3.name);
    try std.testing.expectEqual(types.FieldLabel.Repeated, f3.label);
}
