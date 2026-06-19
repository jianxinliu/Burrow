//
//  PortLookup.swift
//  Burrow
//
//  Offline "what is this port" lookup. A small curated table of the
//  well-known port numbers a developer actually meets — web servers, databases,
//  dev servers, mail, etc. — so the Ports pane can label a row without any
//  network call. Port numbers and their conventional service are public facts;
//  this is a hand-picked subset, not the full IANA registry.
//

import Foundation

enum PortLookup {
    /// Conventional service for a well-known port, or nil if we don't curate it.
    static func service(for port: Int) -> String? { table[port] }

    private static let table: [Int: String] = [
        20: "FTP data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP",
        53: "DNS", 67: "DHCP", 68: "DHCP", 69: "TFTP", 80: "HTTP",
        88: "Kerberos", 110: "POP3", 111: "rpcbind", 119: "NNTP", 123: "NTP",
        137: "NetBIOS", 138: "NetBIOS", 139: "NetBIOS", 143: "IMAP", 161: "SNMP",
        389: "LDAP", 443: "HTTPS", 445: "SMB", 465: "SMTPS", 514: "syslog",
        515: "LPD", 548: "AFP", 587: "SMTP submission", 631: "IPP/CUPS",
        636: "LDAPS", 873: "rsync", 989: "FTPS data", 990: "FTPS", 993: "IMAPS",
        995: "POP3S",
        // Databases
        1433: "MS SQL Server", 1521: "Oracle DB", 3306: "MySQL/MariaDB",
        5432: "PostgreSQL", 5984: "CouchDB", 6379: "Redis",
        7077: "Spark", 8086: "InfluxDB", 9042: "Cassandra", 9200: "Elasticsearch",
        9300: "Elasticsearch", 11211: "Memcached", 27017: "MongoDB",
        // Messaging / infra
        2181: "ZooKeeper", 4222: "NATS", 5672: "AMQP/RabbitMQ", 5671: "AMQPS",
        9092: "Kafka", 15672: "RabbitMQ admin", 25565: "Minecraft",
        // Web / dev servers
        1080: "SOCKS proxy", 1234: "dev server", 2375: "Docker", 2376: "Docker TLS",
        3000: "dev server (Node/Rails)", 3001: "dev server", 4000: "dev server",
        4200: "Angular dev", 5000: "dev server (Flask/AirPlay)", 5173: "Vite dev",
        5500: "Live Server", 6006: "Storybook", 8000: "dev server (Django)",
        8025: "Mailpit/MailHog", 8080: "HTTP alt / dev", 8081: "dev server",
        8443: "HTTPS alt", 8888: "Jupyter / dev", 9000: "dev server (PHP/SonarQube)",
        9090: "Prometheus", 9229: "Node debugger", 9091: "Transmission",
        // Apple / mac
        3283: "Apple Remote Desktop", 5900: "VNC/Screen Sharing", 7000: "AirPlay",
        49152: "AirPlay (dynamic)",
        // Tunnels / VPN
        500: "IKE/IPsec", 1194: "OpenVPN", 1701: "L2TP", 1723: "PPTP", 4500: "IPsec NAT-T",
        51820: "WireGuard",
    ]
}
