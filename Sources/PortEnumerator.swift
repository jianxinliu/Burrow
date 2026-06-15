//
//  PortEnumerator.swift
//  Burrow
//
//  Native listening-port enumeration (roadmap C.10): proc_listpids → per-pid
//  fd scan → socket fdinfo, no shelling out to lsof, no elevation for the
//  user's own processes. Feeds PortInspector (sort + kill-safety) and the
//  ports pane / burrow_ports tool.
//
//  NOTE (hand-test): native C-interop, runtime-unverifiable in CI (no
//  guaranteed listening sockets). Verify the port list matches `lsof -i -P`
//  on a real machine.
//

import Foundation
import Darwin

enum PortEnumerator {
    static func listening(currentUID: uid_t = getuid()) -> [ListeningPort] {
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
                let proto: String
                let lportRaw: Int32
                if psi.soi_kind == Int32(SOCKINFO_TCP) {
                    guard si.psi.soi_proto.pri_tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
                    proto = "tcp"
                    lportRaw = si.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport
                } else if psi.soi_kind == Int32(SOCKINFO_IN) {
                    lportRaw = si.psi.soi_proto.pri_in.insi_lport
                    guard lportRaw != 0 else { continue }   // only bound UDP sockets
                    proto = "udp"
                } else {
                    continue
                }
                // insi_lport holds the port in network byte order in its low 16 bits.
                let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: lportRaw)))
                guard port > 0 else { continue }

                if name == nil { name = Self.processName(pid) }
                if uid == nil { uid = Self.processUID(pid) }
                out.append(ListeningPort(pid: Int(pid), process: name ?? "pid \(pid)",
                                         port: port, proto: proto,
                                         address: "*", uid: Int(uid ?? 0)))
            }
        }
        return PortInspector.sorted(out)
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
