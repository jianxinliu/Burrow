//
//  PortEnumerator.swift
//  Burrow
//
//  Native socket enumeration (roadmap C.10, extended): proc_listpids → per-pid
//  fd scan → socket fdinfo, no shelling out to lsof, no elevation for the
//  user's own processes. Captures both LISTENing sockets and (optionally)
//  ESTABLISHED connections with their remote endpoint, so the Ports pane can
//  show "what's accepting" and "what's talking to whom." Feeds PortInspector
//  (sort / kill-safety / conflicts) and the ports pane / burrow_ports tool.
//
//  NOTE (hand-test): native C-interop, runtime-unverifiable in CI (no
//  guaranteed sockets). Verify the list + remote endpoints vs `lsof -i -P`.
//

import Foundation
import Darwin

enum PortEnumerator {
    /// Listening sockets only — the original behavior the kill flow + MCP
    /// `burrow_ports` rely on.
    static func listening(currentUID: uid_t = getuid()) -> [ListeningPort] {
        connections(currentUID: currentUID, includeEstablished: false)
    }

    /// Listening sockets, plus established TCP connections (with remote
    /// endpoint) when `includeEstablished` is set.
    static func connections(currentUID: uid_t = getuid(), includeEstablished: Bool = true) -> [ListeningPort] {
        var out: [ListeningPort] = []
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids,
                                  Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard bytes > 0 else { return [] }
        let pidCount = Int(bytes) / MemoryLayout<pid_t>.stride

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            let fdBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard fdBytes > 0 else { continue }
            let fdCount = Int(fdBytes) / MemoryLayout<proc_fdinfo>.stride
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
            let gotFds = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, fdBytes)
            guard gotFds > 0 else { continue }

            var name: String?
            var uid: uid_t?
            for f in 0..<(Int(gotFds) / MemoryLayout<proc_fdinfo>.stride) {
                guard fds[f].proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }
                var si = socket_fdinfo()
                let r = proc_pidfdinfo(pid, fds[f].proc_fd, PROC_PIDFDSOCKETINFO,
                                       &si, Int32(MemoryLayout<socket_fdinfo>.stride))
                guard r >= Int32(MemoryLayout<socket_fdinfo>.stride) else { continue }

                let psi = si.psi
                var entry: (port: Int, proto: String, local: String, state: ConnState,
                            remoteAddr: String?, remotePort: Int?)?

                if psi.soi_kind == Int32(SOCKINFO_TCP) {
                    let tcp = si.psi.soi_proto.pri_tcp
                    let ini = tcp.tcpsi_ini
                    let lport = Self.port(ini.insi_lport)
                    if tcp.tcpsi_state == Int32(TSI_S_LISTEN) {
                        guard lport > 0 else { continue }
                        entry = (lport, "tcp", Self.localAddr(ini), .listen, nil, nil)
                    } else if includeEstablished, tcp.tcpsi_state == Int32(TSI_S_ESTABLISHED) {
                        let rport = Self.port(ini.insi_fport)
                        entry = (lport, "tcp", Self.localAddr(ini), .established,
                                 Self.remoteAddr(ini), rport)
                    } else {
                        continue
                    }
                } else if psi.soi_kind == Int32(SOCKINFO_IN) {
                    let ini = si.psi.soi_proto.pri_in
                    let lport = Self.port(ini.insi_lport)
                    guard lport > 0 else { continue }   // only bound UDP sockets
                    entry = (lport, "udp", Self.localAddr(ini), .listen, nil, nil)
                } else {
                    continue
                }

                guard let e = entry else { continue }
                if name == nil { name = Self.processName(pid) }
                if uid == nil { uid = Self.processUID(pid) }
                out.append(ListeningPort(pid: Int(pid), process: name ?? "pid \(pid)",
                                         port: e.port, proto: e.proto,
                                         address: e.local, uid: Int(uid ?? 0),
                                         state: e.state, remoteAddress: e.remoteAddr,
                                         remotePort: e.remotePort))
            }
        }
        return PortInspector.sorted(PortInspector.deduped(out))
    }

    /// insi_lport / insi_fport hold the port in network byte order in their low
    /// 16 bits.
    private static func port(_ raw: Int32) -> Int {
        Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: raw)))
    }

    /// Local address of an in_sockinfo, "*" for the any-address bind.
    private static func localAddr(_ ini: in_sockinfo) -> String {
        let v6 = ini.insi_vflag & 0x02 != 0
        let s = v6 ? ipv6(ini.insi_laddr.ina_6) : ipv4(ini.insi_laddr.ina_46.i46a_addr4)
        return (s == "0.0.0.0" || s == "::" || s.isEmpty) ? "*" : s
    }

    /// Foreign (peer) address of an established in_sockinfo.
    private static func remoteAddr(_ ini: in_sockinfo) -> String {
        let v6 = ini.insi_vflag & 0x02 != 0
        return v6 ? ipv6(ini.insi_faddr.ina_6) : ipv4(ini.insi_faddr.ina_46.i46a_addr4)
    }

    // `insi_laddr` / `insi_faddr` import as anonymous unions (not a shared
    // `in4in6_addr` type), so the IPv4/IPv6 members are read at the call site
    // and the printable conversion is done per-family here.
    private static func ipv4(_ addr: in_addr) -> String {
        var a = addr
        var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &a, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return "" }
        return String(cString: buf)
    }
    private static func ipv6(_ addr: in6_addr) -> String {
        var a = addr
        var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &a, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil else { return "" }
        return String(cString: buf)
    }

    private static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        let n = proc_name(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : "pid \(pid)"
    }

    private static func processUID(_ pid: pid_t) -> uid_t {
        var info = proc_bsdinfo()
        let r = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.stride))
        return r > 0 ? info.pbi_uid : 0
    }
}
