const std = @import("std");
const config = @import("config.zig");
const logger = @import("logger.zig");
const quote_store = @import("quote_store.zig");
const selector = @import("selector.zig");
const tcp_server = @import("servers/tcp.zig");
const udp_server = @import("servers/udp.zig");

const Configuration = config.Configuration;
const QuoteStore = quote_store.QuoteStore;
const Selector = selector.Selector;
const Logger = logger.Logger;
const TcpServer = tcp_server.TcpServer;
const UdpServer = udp_server.UdpServer;

// Re-export modules for integration testing
pub const modules = struct {
    pub const Config = config;
    pub const QuoteStoreModule = quote_store;
    pub const SelectorModule = selector;
    pub const TcpServerModule = tcp_server;
    pub const UdpServerModule = udp_server;
};

/// Global flag for graceful shutdown (accessed by signal handler)
var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);

/// Signal handler for SIGTERM and SIGINT
fn signalHandler(sig: c_int) callconv(.c) void {
    _ = sig;
    running.store(false, .seq_cst);
}

/// Setup signal handlers for graceful shutdown
fn setupSignalHandlers() void {
    const mask: std.posix.sigset_t = std.posix.sigemptyset();
    const handler = std.posix.Sigaction{
        .handler = .{ .handler = signalHandler },
        .mask = mask,
        .flags = 0,
    };

    // Handle SIGTERM (docker stop, kill)
    std.posix.sigaction(std.posix.SIG.TERM, &handler, null);

    // Handle SIGINT (Ctrl+C)
    std.posix.sigaction(std.posix.SIG.INT, &handler, null);
}

/// Main entry point for quotez QOTD service
pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    var log = Logger.init();

    // Load configuration
    const config_path = "quotez.toml";
    var cfg = Configuration.load(allocator, config_path) catch |err| {
        log.err("config_error", .{
            .reason = "failed to load configuration",
            .path = config_path,
            .err = @errorName(err),
        });
        std.process.exit(1);
    };
    defer cfg.deinit();

    // Validate configuration
    if (cfg.directories.len == 0) {
        log.err("config_error", .{ .reason = "no quote directories specified" });
        std.process.exit(1);
    }

    // Log service startup
    log.info("service_start", .{
        .version = "1.0.0",
        .tcp_port = cfg.tcp_port,
        .udp_port = cfg.udp_port,
    });

    // Initialize quote store
    var store = QuoteStore.init(allocator);
    defer store.deinit();

    // Build initial quote collection
    store.build(cfg.directories) catch |err| {
        log.err("quote_store_build_error", .{
            .err = @errorName(err),
        });
        std.process.exit(1);
    };

    // Initialize selector
    var sel = Selector.init(allocator, cfg.selection_mode, store.count()) catch |err| {
        log.err("selector_init_error", .{
            .err = @errorName(err),
        });
        std.process.exit(1);
    };
    defer sel.deinit();

    // Initialize TCP server
    var tcp = TcpServer.init(
        allocator,
        cfg.host,
        cfg.tcp_port,
        &store,
        &sel,
    ) catch |err| {
        log.err("tcp_init_error", .{ .err = @errorName(err) });
        std.process.exit(1);
    };
    defer tcp.deinit();

    tcp.listen() catch |err| {
        log.err("tcp_listen_error", .{
            .err = @errorName(err),
            .port = cfg.tcp_port,
        });
        std.process.exit(1);
    };

    // Initialize UDP server
    var udp = UdpServer.init(
        allocator,
        cfg.host,
        cfg.udp_port,
        &store,
        &sel,
    ) catch |err| {
        log.err("udp_init_error", .{ .err = @errorName(err) });
        std.process.exit(1);
    };
    defer udp.deinit();

    udp.listen() catch |err| {
        log.err("udp_listen_error", .{
            .err = @errorName(err),
            .port = cfg.udp_port,
        });
        std.process.exit(1);
    };

    log.info("service_ready", .{
        .quotes = store.count(),
        .mode = cfg.selection_mode.asString(),
        .tcp_port = cfg.tcp_port,
        .udp_port = cfg.udp_port,
    });

    // Setup signal handlers for graceful shutdown
    setupSignalHandlers();
    log.info("signal_handlers_installed", .{});

    // Main event loop with poll() multiplexing
    // TODO: Implement file watcher integration (Phase 8)

    // Setup poll file descriptors
    var poll_fds = [_]std.posix.pollfd{
        .{ .fd = tcp.getSocket(), .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = udp.getSocket(), .events = std.posix.POLL.IN, .revents = 0 },
    };

    while (running.load(.seq_cst)) {
        // Wait for activity on either socket (100ms timeout)
        const poll_result = std.posix.poll(&poll_fds, 100) catch |err| {
            // EINTR is expected when signal is received
            if (err == error.Interrupted) continue;
            log.warn("poll_error", .{ .err = @errorName(err) });
            continue;
        };

        if (poll_result > 0) {
            // Check TCP socket
            if (poll_fds[0].revents & std.posix.POLL.IN != 0) {
                _ = tcp.acceptOne() catch |err| {
                    log.warn("tcp_accept_loop_error", .{ .err = @errorName(err) });
                };
            }

            // Check UDP socket
            if (poll_fds[1].revents & std.posix.POLL.IN != 0) {
                _ = udp.handleOne() catch |err| {
                    log.warn("udp_handle_loop_error", .{ .err = @errorName(err) });
                };
            }
        }

        // Reset revents for next poll
        poll_fds[0].revents = 0;
        poll_fds[1].revents = 0;

        // TODO: Check for file changes at polling interval
    }

    log.info("service_shutdown", .{});
}

test "basic test" {
    try std.testing.expect(true);
}
