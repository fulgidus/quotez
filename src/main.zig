const std = @import("std");
const config = @import("config.zig");
const logger = @import("logger.zig");
const quote_store = @import("quote_store.zig");
const selector = @import("selector.zig");
const tcp_server = @import("servers/tcp.zig");
const udp_server = @import("servers/udp.zig");
const watcher = @import("watcher.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var log = logger.Logger.init();

    // Log startup
    log.info("startup", .{ .service = "quotez", .version = "0.1.0" });

    // Parse CLI arguments for config file path
    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config_path: []const u8 = "quotez.toml";
    var show_help = false;

    // Process arguments (skip args[0] which is the binary name)
    if (args.len > 1) {
        const first_arg = args[1];
        if (std.mem.eql(u8, first_arg, "--help") or std.mem.eql(u8, first_arg, "-h")) {
            show_help = true;
        } else {
            config_path = first_arg;
        }
    }

    // Handle help flag
    if (show_help) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Usage: quotez [CONFIG_PATH]\n", .{});
        std.process.exit(0);
    }

    // Load configuration
    var cfg = config.Configuration.load(allocator, config_path) catch |err| {
        log.err("fatal", .{
            .reason = "failed to load configuration",
            .file = config_path,
            .err = @errorName(err),
        });
        std.process.exit(1);
    };
    defer cfg.deinit();

    // Initialize quote store
    var store = quote_store.QuoteStore.init(allocator);
    defer store.deinit();

    // Build quote store from configured directories
    store.build(cfg.directories) catch |err| {
        log.err("fatal", .{
            .reason = "failed to build quote store",
            .err = @errorName(err),
        });
        std.process.exit(1);
    };

    // Verify we have quotes
    if (store.isEmpty()) {
        log.warn("empty_quote_store", .{
            .directories = cfg.directories.len,
            .message = "no quotes loaded, service will respond with empty responses",
        });
    }

    // Initialize selector with the configured mode
    var sel = try selector.Selector.init(allocator, cfg.selection_mode, store.count());
    defer sel.deinit();

    log.info("initialization_complete", .{
        .quotes = store.count(),
        .mode = cfg.selection_mode.asString(),
        .tcp_port = cfg.tcp_port,
        .udp_port = cfg.udp_port,
        .polling_interval = cfg.polling_interval,
    });

    // Initialize TCP server
    var tcp = tcp_server.TcpServer.init(
        allocator,
        cfg.host,
        cfg.tcp_port,
        &store,
        &sel,
    ) catch |err| {
        log.err("fatal", .{
            .reason = "failed to start TCP server",
            .host = cfg.host,
            .port = cfg.tcp_port,
            .err = @errorName(err),
        });
        std.process.exit(1);
    };
    defer tcp.deinit();

    // Initialize UDP server
    var udp = udp_server.UdpServer.init(
        allocator,
        cfg.host,
        cfg.udp_port,
        &store,
        &sel,
    ) catch |err| {
        log.err("fatal", .{
            .reason = "failed to start UDP server",
            .host = cfg.host,
            .port = cfg.udp_port,
            .err = @errorName(err),
        });
        std.process.exit(1);
    };
    defer udp.deinit();

    log.info("service_ready", .{
        .tcp_port = cfg.tcp_port,
        .udp_port = cfg.udp_port,
        .quotes_loaded = store.count(),
    });

    // Initialize FileWatcher for hot reload
    var file_watcher = try watcher.FileWatcher.init(
        allocator,
        cfg.directories,
        @as(u64, cfg.polling_interval),  // Cast u32 to u64
    );
    defer file_watcher.deinit();

    // Setup signal handling for graceful shutdown
    var shutdown_requested = std.atomic.Value(bool).init(false);
    try setupSignalHandlers(&shutdown_requested);

    // Run event loop with poll() for both TCP and UDP
    runEventLoop(&tcp, &udp, &file_watcher, &store, &sel, &cfg, &log, &shutdown_requested) catch |err| {
        log.err("fatal", .{
            .reason = "event loop error",
            .err = @errorName(err),
        });
        std.process.exit(1);
    };

    log.info("shutdown", .{ .reason = "graceful shutdown complete" });
}

/// Setup signal handlers for graceful shutdown
fn setupSignalHandlers(shutdown_requested: *std.atomic.Value(bool)) !void {
    // Register SIGTERM handler
    const sigterm_action = std.posix.Sigaction{
        .handler = .{ .handler = handleShutdownSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.TERM, &sigterm_action, null);

    // Register SIGINT handler (Ctrl+C)
    const sigint_action = std.posix.Sigaction{
        .handler = .{ .handler = handleShutdownSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sigint_action, null);

    // Store the shutdown flag pointer for signal handlers
    shutdown_flag = shutdown_requested;
}

/// Global shutdown flag for signal handlers
var shutdown_flag: ?*std.atomic.Value(bool) = null;

/// Signal handler for SIGTERM and SIGINT
fn handleShutdownSignal(_: std.posix.SIG) callconv(.c) void {
    if (shutdown_flag) |flag| {
        flag.store(true, .seq_cst);
    }
}

/// Event loop using poll() to multiplex TCP and UDP servers
fn runEventLoop(
    tcp: *tcp_server.TcpServer,
    udp: *udp_server.UdpServer,
    file_watcher: *watcher.FileWatcher,
    store: *quote_store.QuoteStore,
    sel: *selector.Selector,
    cfg: *config.Configuration,
    log: *logger.Logger,
    shutdown_requested: *std.atomic.Value(bool),
) !void {
    log.info("event_loop_started", .{
        .tcp_fd = tcp.socket,
        .udp_fd = udp.socket,
    });

    // Set up poll file descriptors
    var poll_fds = [_]std.posix.pollfd{
        .{
            .fd = tcp.socket,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = udp.socket,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    // Event loop
    while (!shutdown_requested.load(.seq_cst)) {
        // Wait for events on either socket (timeout: 1000ms to check shutdown flag periodically)
        const ready = std.posix.poll(&poll_fds, 1000) catch |err| {
            // Interrupted by signal is expected during shutdown
            if (err == error.SignalInterrupt) {
                if (shutdown_requested.load(.seq_cst)) {
                    log.info("shutdown_signal_received", .{});
                    break;
                }
                continue;
            }
            return err;
        };

        if (ready == 0) {
            // Poll timeout - check for file changes
            if (try file_watcher.check()) {
                log.info("hot_reload_triggered", .{});
                try store.build(cfg.directories);
                try sel.reset(store.count());
                log.info("hot_reload_complete", .{ .quotes = store.count() });
            }
            continue;
        }

        // Check TCP socket
        if (poll_fds[0].revents & std.posix.POLL.IN != 0) {
            tcp.acceptAndServe() catch |err| {
                log.warn("tcp_serve_error", .{ .err = @errorName(err) });
            };
        }

        // Check UDP socket
        if (poll_fds[1].revents & std.posix.POLL.IN != 0) {
            udp.receiveAndRespond() catch |err| {
                log.warn("udp_serve_error", .{ .err = @errorName(err) });
            };
        }

        // Check for errors
        if (poll_fds[0].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP) != 0) {
            log.err("tcp_socket_error", .{ .revents = poll_fds[0].revents });
            return error.TcpSocketError;
        }
        if (poll_fds[1].revents & (std.posix.POLL.ERR | std.posix.POLL.HUP) != 0) {
            log.err("udp_socket_error", .{ .revents = poll_fds[1].revents });
            return error.UdpSocketError;
        }

        // Reset revents for next iteration
        poll_fds[0].revents = 0;
        poll_fds[1].revents = 0;
    }
}

// Module exports for tests
pub const config_mod = config;
pub const logger_mod = logger;
pub const quote_store_mod = quote_store;
pub const selector_mod = selector;
pub const tcp_server_mod = tcp_server;
pub const udp_server_mod = udp_server;
pub const watcher_mod = watcher;
