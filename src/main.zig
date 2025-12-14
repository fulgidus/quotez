const std = @import("std");
const config = @import("config.zig");
const logger = @import("logger.zig");
const quote_store = @import("quote_store.zig");
const selector = @import("selector.zig");
const tcp_server = @import("servers/tcp.zig");
const udp_server = @import("servers/udp.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var log = logger.Logger.init();

    // Log startup
    log.info("startup", .{ .service = "quotez", .version = "0.1.0" });

    // Load configuration from quotez.toml
    const config_path = "quotez.toml";
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
    var sel = selector.Selector.init(allocator, cfg.selection_mode, store.count());
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

    // TODO: Phase 8 - Start file watcher for hot reload

    // Run event loop with poll() for both TCP and UDP
    runEventLoop(&tcp, &udp, &log) catch |err| {
        log.err("fatal", .{
            .reason = "event loop error",
            .err = @errorName(err),
        });
        std.process.exit(1);
    };

    log.info("shutdown", .{ .reason = "server stopped" });
}

/// Event loop using poll() to multiplex TCP and UDP servers
fn runEventLoop(
    tcp: *tcp_server.TcpServer,
    udp: *udp_server.UdpServer,
    log: *logger.Logger,
) !void {
    log.info("event_loop_started", .{
        .tcp_fd = tcp.socket.stream.handle,
        .udp_fd = udp.socket,
    });

    // Set up poll file descriptors
    var poll_fds = [_]std.posix.pollfd{
        .{
            .fd = tcp.socket.stream.handle,
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
    while (true) {
        // Wait for events on either socket (timeout: -1 = infinite)
        const ready = try std.posix.poll(&poll_fds, -1);

        if (ready == 0) continue; // Timeout (shouldn't happen with infinite timeout)

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
