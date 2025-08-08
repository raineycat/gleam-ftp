# Gleam FTP Server

![Version](https://img.shields.io/badge/Version-1.0.0-pink)
![License](https://img.shields.io/badge/License-LGPL_3.0-green)

A simple FTP server written in Gleam

```sh
# Run the server with some example arguments
gleam run -- --port 2100 --base-dir ./data --welcome "My FTP Server" --allowed-logins "me:hunter2"
```

### Available options:
- `--allow-anon`: Allows anonymous connections to the server
- `--read-only`: Rejects create/write/delete actions sent by clients
- `--address`: The address to bind to (default: `0.0.0.0`)
- `--port`: The port the server listens on (default: `21`)
- `--welcome`: The welcome message to send to clients (default: `GleamFTP Server`)
- `--external-address`: The public IP of the server, sent to clients when connecting with passive mode (default: `127.0.0.1`)
- `--base-dir`: The directory to serve files from (default: `.`)
- `--allowed-logins`: A list of users and passwords to authorise logins against. Format: `username:password,user2:pass2` (default: `root:root`)
- `--help`: Shows more info about the command line options