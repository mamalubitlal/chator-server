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
	frpWebsocketPath = "/~!frp"
	controlPort      = "7001"
	httpPort         = "8080"
)

func main() {
	listenPort := os.Getenv("PORT")
	if listenPort == "" {
		listenPort = "10000"
	}
	ctrlPort := envOr("FRPS_CONTROL_PORT", controlPort)
	vhostPort := envOr("FRPS_VHOST_PORT", httpPort)

	ln, err := net.Listen("tcp", ":"+listenPort)
	if err != nil {
		fmt.Fprintf(os.Stderr, "demux: listen :%s: %v\n", listenPort, err)
		os.Exit(1)
	}
	defer ln.Close()
	fmt.Fprintf(os.Stderr, "demux: listening :%s → control:%s http:%s\n", listenPort, ctrlPort, vhostPort)

	for {
		conn, err := ln.Accept()
		if err != nil {
			fmt.Fprintf(os.Stderr, "demux: accept: %v\n", err)
			continue
		}
		go handle(conn, ctrlPort, vhostPort)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func handle(client net.Conn, ctrlPort, vhostPort string) {
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

	// Route to frps control or vhost HTTP
	backendPort := vhostPort
	if isFRPControl(line) {
		backendPort = ctrlPort
		fmt.Fprintf(os.Stderr, "demux: -> control:%s\n", ctrlPort)
	} else {
		fmt.Fprintf(os.Stderr, "demux: -> http:%s\n", vhostPort)
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
