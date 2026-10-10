```
                                                   
 ad88888ba                     88    ad88          
 d8"     "8b                    ""   d8"     ,d     
 Y8,                                 88      88     
 `Y8aaaaa,   8b      db      d8 88 MM88MMM MM88MMM  
   `"""""8b, `8b    d88b    d8' 88   88      88     
         `8b  `8b  d8'`8b  d8'  88   88      88     
 Y8a     a8P   `8bd8'  `8bd8'   88   88      88,    
  "Y88888P"      YP      YP     88   88      "Y888  
                                                    
                                                    
                                                                          
   ,ad8888ba,                          88                                 
  d8"'    `"8b                         88                                 
 d8'                                   88                                 
 88             ,adPPYba,  8b,dPPYba,  88,dPPYba,   ,adPPYba, 8b,dPPYba,  
 88      88888 a8"     "8a 88P'    "8a 88P'    "8a a8P_____88 88P'   "Y8  
 Y8,        88 8b       d8 88       d8 88       88 8PP""""""" 88          
  Y8a.    .a88 "8a,   ,a8" 88b,   ,a8" 88       88 "8b,   ,aa 88          
   `"Y88888P"   `"YbbdP"'  88`YbbdP"'  88       88  `"Ybbd8"' 88          
                           88                                             
                           88 
```

# Swift-Gopher

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnavanchauhan%2Fswift-gopher%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/navanchauhan/swift-gopher)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fnavanchauhan%2Fswift-gopher%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/navanchauhan/swift-gopher)

* swift-gopher : Gopher server implementation written in Swift
* swiftGopherClient: Gopher client library written in Swift ( w/ Support for Network.Framework on Apple platforms)

This package also provides GopherHelpers which may be useful while building a client. A PoC client for iOS/macOS/iPadOS called `iGopherBrowser` uses both `GopherHelpers` and `swiftGopherClient`

You can interact with my hosted gopher server at [gopher://gopher.navan.dev](gopher://gopher.navan.dev) or [https://gopher.navan.dev](https://gopher.navan.dev)

```
USAGE: swift-gopher [--gopher-host-name <gopher-host-name>] [--host <host>] [--port <port>] [--gopher-data-dir <gopher-data-dir>] [--disable-search] [--disable-gophermap] [--http-port <http-port>] [--http-allow-remote-hosts] [--http-allow-all-ports]

OPTIONS:
  -g, --gopher-host-name <gopher-host-name>
                          Hostname used for generating selectors (default: localhost)
  -h, --host <host>       (default: 0.0.0.0)
  -p, --port <port>       (default: 8080)
  -d, --gopher-data-dir <gopher-data-dir>
                          Data directory to map (default: ./example-gopherdata)
  --disable-search        Disable full-text search feature
  --disable-gophermap     Disable reading gophermap files to override automatic generation
  --http-port <http-port> Also serve an HTTP proxy for browsing gopher in a web browser on this port
  --http-allow-remote-hosts
                          Let the HTTP proxy fetch from other gopher servers, not just this one
  --http-allow-all-ports  Let the HTTP proxy connect to remote gopher servers on ports other than 70
  -h, --help
```

## Get Started
```
git clone https://github.com/navanchauhan
cd swift-gopher
swift build -c release && swift run swift-gopher
```

Then, you can either use lynx or curl (or other Gopher clients) to connect to the server.

```
lynx gopher://localhost:8080
# Or,
curl gopher://localhost:8080
```

**Note: Depending on user privileges, you may not be able to bind to port 70.**

To give privilege to the binary on Linux, you can use the following command:

```bash
sudo setcap CAP_NET_BIND_SERVICE=+eip ./.build/release/swift-gopher
```

You can also refer to the systemd file below to grant the binary the same privileges

## Deploying

### Systemd

Sample systemd file:

```
[Unit]
Description=Swift-Gopher

[Service]
ExecStart=/home/swift-gopher/swift-gopher/.build/release/swift-gopher --port 70 --gopher-host-name gopher.navan.dev --gopher-data-dir /home/swift-gopher/gopher_data
User=swift-gopher
Group=swift-gopher
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

## HTTP Proxy

Pass `--http-port` to serve your gopherhole to web browsers as plain, script-free HTML alongside the gopher server:

```
swift run swift-gopher --http-port 8081
# Then open http://localhost:8081
```

Menus, text files and search (type 7) are rendered as HTML, images are shown inline, and other files are offered as downloads. Proxy URLs mirror `gopher://` URLs, e.g. `http://localhost:8081/localhost:8080/0/hello_world.txt`.

By default the proxy only serves this server's own content, read directly without a network round trip, and links to other gopher servers are left as `gopher://` links. To browse the rest of gopherspace through it:

* `--http-allow-remote-hosts` lets it fetch from other gopher servers on port 70. Responses are cached in memory for 5 minutes, and requests time out after 15 seconds or 16 MB.
* `--http-allow-all-ports` additionally allows remote servers on other ports.

Remote hosts that resolve to loopback, private, link-local or other reserved addresses are always refused, so the proxy can't be used to reach your internal network. There is no TLS support; put Caddy or another reverse proxy in front of it to serve HTTPS.

Alternatively, you can self host one of these standalone proxies:

* [gophper-proxy](https://github.com/muffinista/gophper-proxy)
* [gopher-proxy](https://hackage.haskell.org/package/gopher-proxy)
* [gopherproxy-c](https://git.codemadness.org/gopherproxy-c/)

## TODO:

- [x] Add Tests
- [x] Add CI
- [x] Automatic Versioning
- [ ] Verify Compatibility with other Gopher Clients
- [ ] Support Gemini Protocol
- [x] Add a client library
- [x] Add native HTTP handler
- [ ] Guestbook
