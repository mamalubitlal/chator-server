package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
)

const (
	frpWebsocketPath  = "/~!frp"
	tunnelUpgradePath = "/tunnel"
	controlPort       = "7001"
	httpPort          = "8080"
	tunnelPort        = "9999"
)

func main() {
	listenPort := os.Getenv("PORT")
	if listenPort == "" {
		listenPort = "10000"
	}
	ctrlPort := envOr("FRPS_CONTROL_PORT", controlPort)
	vhostPort := envOr("FRPS_VHOST_PORT", httpPort)
	tunPort := envOr("WSTUNNEL_PORT", tunnelPort)

	ln, err := net.Listen("tcp", ":"+listenPort)
	if err != nil {
		fmt.Fprintf(os.Stderr, "demux: listen :%s: %v\n", listenPort, err)
		os.Exit(1)
	}
	defer ln.Close()
	fmt.Fprintf(os.Stderr, "demux: listening :%s → tunnel:%s vhost:%s\n", listenPort, tunPort, vhostPort)

	for {
		conn, err := ln.Accept()
		if err != nil {
			fmt.Fprintf(os.Stderr, "demux: accept: %v\n", err)
			continue
		}
		go handle(conn, ctrlPort, vhostPort, tunPort)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func handle(client net.Conn, ctrlPort, vhostPort, tunPort string) {
	defer client.Close()

	br := bufio.NewReader(client)
	line, err := br.ReadString('\n')
	if err != nil {
		return
	}

	// Log the request line for debugging
	fmt.Fprintf(os.Stderr, "demux: <- %s", strings.TrimRight(line, "\r\n"))

	// Health check → respond 200 directly
	if isHealthCheck(line) {
		fmt.Fprintf(os.Stderr, "demux: health check, responding 200\n")
		io.WriteString(client, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK")
		return
	}

	// Route: tunnel upgrade → wstunnel server, frp control → frps, rest → vhost
	backendPort := vhostPort
	switch {
	case isTunnelUpgrade(line):
		backendPort = tunPort
		fmt.Fprintf(os.Stderr, "demux: -> tunnel:%s\n", tunPort)
	case isFRPControl(line):
		backendPort = ctrlPort
		fmt.Fprintf(os.Stderr, "demux: -> control:%s\n", ctrlPort)
	default:
		fmt.Fprintf(os.Stderr, "demux: -> vhost:%s\n", vhostPort)
	}

	backend, err := net.Dial("tcp", "127.0.0.1:"+backendPort)
	if err != nil {
		fmt.Fprintf(os.Stderr, "demux: dial :%s: %v\n", backendPort, err)
		return
	}
	defer backend.Close()

	// Forward the peeked request line
	if _, err := io.WriteString(backend, line); err != nil {
		return
	}

	// Bidirectional copy
	errc := make(chan error, 1)
	go func() {
		_, err := io.Copy(backend, br)
		errc <- err
	}()
	go func() {
		_, err := io.Copy(client, backend)
		errc <- err
	}()
	<-errc
}

func isHealthCheck(line string) bool {
	fields := strings.Fields(line)
	if len(fields) < 2 {
		return false
	}
	path := fields[1]
	return path == "/" || path == "/health" || path == "/-/healthy"
}

func isFRPControl(line string) bool {
	return strings.Contains(line, frpWebsocketPath)
}

func isTunnelUpgrade(line string) bool {
	return strings.Contains(line, tunnelUpgradePath)
}
