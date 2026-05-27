package main

import (
	"flag"
	"log"
	"net"
	"net/http"
	"net/url"
	"sync"

	"github.com/gorilla/websocket"
)

func main() {
	listen := flag.String("listen", ":7002", "Local TCP listen address")
	target := flag.String("target", "wss://chator-frp.onrender.com/frpws", "Target WebSocket URL")
	origin := flag.String("origin", "https://chator-frp.onrender.com", "Origin header")
	flag.Parse()

	targetURL, err := url.Parse(*target)
	if err != nil {
		log.Fatalf("invalid target URL: %v", err)
	}

	l, err := net.Listen("tcp", *listen)
	if err != nil {
		log.Fatalf("listen error: %v", err)
	}
	defer l.Close()

	log.Printf("listening on %s → %s (origin: %s)", *listen, *target, *origin)

	header := http.Header{}
	header.Set("Origin", *origin)

	for {
		conn, err := l.Accept()
		if err != nil {
			log.Printf("accept error: %v", err)
			continue
		}
		go handle(conn, targetURL, header)
	}
}

func handle(local net.Conn, targetURL *url.URL, header http.Header) {
	defer local.Close()

	ws, _, err := websocket.DefaultDialer.Dial(targetURL.String(), header)
	if err != nil {
		log.Printf("ws dial error: %v", err)
		return
	}
	defer ws.Close()

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		for {
			_, data, err := ws.ReadMessage()
			if err != nil {
				return
			}
			if _, err := local.Write(data); err != nil {
				return
			}
		}
	}()

	go func() {
		defer wg.Done()
		buf := make([]byte, 32*1024)
		for {
			n, err := local.Read(buf)
			if err != nil {
				return
			}
			if err := ws.WriteMessage(websocket.BinaryMessage, buf[:n]); err != nil {
				return
			}
		}
	}()

	wg.Wait()
}
