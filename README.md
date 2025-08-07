# Gleam FTP Server

![Version](https://img.shields.io/badge/Version-1.0.0-pink)

A simple FTP server written in Gleam

```sh
# Run the server on port 2100
gleam run -- --port 2100
```

### Available options:
- `--address`: The address to bind to (default: `0.0.0.0`)
- `--port`: The port the server listens on (default: `21`)
- `--welcome`: The welcome message to send to clients (default: `GleamFTP Server`)
- `--external-address`: The public IP of the server, sent to clients when connecting with passive mode (default: `127.0.0.1`)
- `--help`: Shows more info about the command line options