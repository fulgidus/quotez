const std = @import("std");

pub const socket_t = std.posix.socket_t;
pub const socklen_t = std.posix.socklen_t;
pub const sockaddr = std.posix.sockaddr;

pub const SocketError = error{ AddressFamilyNotSupported, PermissionDenied, ProtocolNotSupported, SystemResources, Unexpected };
pub fn socket(domain: u32, socket_type: u32, protocol: u32) SocketError!socket_t {
    const rc = std.c.socket(@intCast(domain), @intCast(socket_type), @intCast(protocol));
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .AFNOSUPPORT => return error.AddressFamilyNotSupported,
        .PROTONOSUPPORT => return error.ProtocolNotSupported,
        .NOBUFS, .NOMEM => return error.SystemResources,
        .PERM, .ACCES => return error.PermissionDenied,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub fn close(fd: socket_t) void {
    _ = std.c.close(fd);
}

pub const SetSockOptError = error{ AlreadyConnected, InvalidProtocolOption, TimeoutTooBig, SystemResources, PermissionDenied, OperationUnsupported, NetworkDown, FileDescriptorNotASocket, SocketNotBound, NoDevice, Unexpected };
pub fn setsockopt(fd: socket_t, level: i32, optname: u32, opt: []const u8) SetSockOptError!void {
    switch (std.posix.errno(std.c.setsockopt(fd, level, optname, opt.ptr, @intCast(opt.len)))) {
        .SUCCESS => {},
        .ISCONN => return error.AlreadyConnected,
        .NOPROTOOPT => return error.InvalidProtocolOption,
        .DOM => return error.TimeoutTooBig,
        .NOMEM, .NOBUFS => return error.SystemResources,
        .PERM => return error.PermissionDenied,
        .OPNOTSUPP => return error.OperationUnsupported,
        .NETDOWN => return error.NetworkDown,
        .NOTSOCK => return error.FileDescriptorNotASocket,
        .INVAL => return error.SocketNotBound,
        .NODEV => return error.NoDevice,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const BindError = error{ AddressInUse, AddressNotAvailable, PermissionDenied, Unexpected };
pub fn bind(fd: socket_t, address: ?*const sockaddr, address_len: socklen_t) BindError!void {
    switch (std.posix.errno(std.c.bind(fd, address, address_len))) {
        .SUCCESS => {},
        .ADDRINUSE => return error.AddressInUse,
        .ADDRNOTAVAIL => return error.AddressNotAvailable,
        .ACCES => return error.PermissionDenied,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const ListenError = error{ AddressInUse, OperationNotSupported, Unexpected };
pub fn listen(fd: socket_t, backlog: u31) ListenError!void {
    switch (std.posix.errno(std.c.listen(fd, backlog))) {
        .SUCCESS => {},
        .ADDRINUSE => return error.AddressInUse,
        .OPNOTSUPP => return error.OperationNotSupported,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const AcceptError = error{ WouldBlock, ConnectionAborted, FileDescriptorNotASocket, ProcessFdQuotaExceeded, SystemFdQuotaExceeded, SystemResources, Unexpected };
pub fn accept(sockfd: socket_t, addr: ?*sockaddr, addrlen: ?*socklen_t, flags: u32) AcceptError!socket_t {
    const rc = if (flags == 0) std.c.accept(sockfd, addr, addrlen) else std.c.accept4(sockfd, addr, addrlen, flags);
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .AGAIN => return error.WouldBlock,
        .CONNABORTED => return error.ConnectionAborted,
        .NOTSOCK => return error.FileDescriptorNotASocket,
        .MFILE => return error.ProcessFdQuotaExceeded,
        .NFILE => return error.SystemFdQuotaExceeded,
        .NOBUFS, .NOMEM => return error.SystemResources,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const ConnectError = error{ WouldBlock, ConnectionRefused, ConnectionTimedOut, NetworkUnreachable, Unexpected };
pub fn connect(sockfd: socket_t, sock_addr: *const sockaddr, addrlen: socklen_t) ConnectError!void {
    switch (std.posix.errno(std.c.connect(sockfd, sock_addr, addrlen))) {
        .SUCCESS => {},
        .AGAIN, .INPROGRESS => return error.WouldBlock,
        .CONNREFUSED => return error.ConnectionRefused,
        .TIMEDOUT => return error.ConnectionTimedOut,
        .NETUNREACH => return error.NetworkUnreachable,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const SendError = error{ BrokenPipe, ConnectionResetByPeer, WouldBlock, MessageTooBig, NetworkUnreachable, UnreachableAddress, Unexpected };
pub fn send(sockfd: socket_t, buf: []const u8, flags: u32) SendError!usize {
    const rc = std.c.send(sockfd, buf.ptr, buf.len, flags);
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .PIPE => return error.BrokenPipe,
        .CONNRESET => return error.ConnectionResetByPeer,
        .AGAIN => return error.WouldBlock,
        .MSGSIZE => return error.MessageTooBig,
        .NETUNREACH => return error.NetworkUnreachable,
        .HOSTUNREACH => return error.UnreachableAddress,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const RecvError = error{ WouldBlock, ConnectionResetByPeer, Unexpected };
pub fn recv(sockfd: socket_t, buf: []u8, flags: u32) RecvError!usize {
    const rc = std.c.recv(sockfd, buf.ptr, buf.len, @intCast(flags));
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .AGAIN => return error.WouldBlock,
        .CONNRESET => return error.ConnectionResetByPeer,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const SendToError = SendError;
pub fn sendto(sockfd: socket_t, buf: []const u8, flags: u32, dest_addr: ?*const sockaddr, addrlen: socklen_t) SendToError!usize {
    const rc = std.c.sendto(sockfd, buf.ptr, buf.len, flags, dest_addr, addrlen);
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .PIPE => return error.BrokenPipe,
        .CONNRESET => return error.ConnectionResetByPeer,
        .AGAIN => return error.WouldBlock,
        .MSGSIZE => return error.MessageTooBig,
        .NETUNREACH => return error.NetworkUnreachable,
        .HOSTUNREACH => return error.UnreachableAddress,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const RecvFromError = error{ WouldBlock, ConnectionRefused, ConnectionResetByPeer, Unexpected };
pub fn recvfrom(sockfd: socket_t, buf: []u8, flags: u32, src_addr: ?*sockaddr, addrlen: ?*socklen_t) RecvFromError!usize {
    const rc = std.c.recvfrom(sockfd, buf.ptr, buf.len, flags, src_addr, addrlen);
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .AGAIN => return error.WouldBlock,
        .CONNREFUSED => return error.ConnectionRefused,
        .CONNRESET => return error.ConnectionResetByPeer,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}

pub const FcntlError = error{ PermissionDenied, BadFileDescriptor, Unexpected };
pub fn fcntl(fd: socket_t, cmd: c_int, arg: usize) FcntlError!usize {
    const rc = std.c.fcntl(fd, cmd, arg);
    switch (std.posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        .ACCES => return error.PermissionDenied,
        .BADF => return error.BadFileDescriptor,
        else => |err| return std.posix.unexpectedErrno(err),
    }
}
