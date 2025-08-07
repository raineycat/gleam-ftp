import gftp/cli
import gftp/os_info
import gftp/passive
import gftp/utils
import gleam/bytes_tree
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/string
import glisten
import glisten/socket
import glisten/socket/options
import glisten/tcp
import logging
import mug

pub type ClientState {
  ClientState(
    sock: socket.Socket,
    auth: AuthState,
    closing: Bool,
    working_dir: String,
    transfer_type: TransferType,
    data_conn: DataConnection,
  )
}

pub type AuthState {
  Unauthenticated
  Authenticating(username: String)
  Authenticated(username: String)
}

pub type TransferType {
  Text
  Binary
}

pub type DataConnection {
  None
  Passive(conn: process.Subject(passive.PassiveConnMessage))
  Active(addr: glisten.IpAddress, port: Int, conn: Option(mug.Socket))
}

pub fn new_client(sock: socket.Socket) -> ClientState {
  ClientState(
    sock:,
    auth: Unauthenticated,
    closing: False,
    working_dir: "/",
    transfer_type: Text,
    data_conn: None,
  )
}

pub fn handle_cmd(
  cmd: List(String),
  state: ClientState,
  opts: cli.ServerOpts,
) -> Result(#(String, ClientState), String) {
  case cmd {
    ["SYST"] -> Ok(#("215 " <> string.inspect(os_info.get_os_type()), state))

    ["FEAT"] -> Ok(#("202 Not supported", state))

    ["PWD"] | ["XPWD"] -> Ok(#("257 \"" <> state.working_dir <> "\"", state))

    ["CWD", ..rest] | ["XCWD", ..rest] -> {
      let dir = rest |> string.join(" ")
      logging.log(logging.Debug, "CLient CWD to: " <> dir)
      let state = ClientState(..state, working_dir: dir)
      Ok(#("250 Changed working directory", state))
    }

    ["TYPE", new_type] -> {
      let new_type = case new_type {
        "A" -> Ok(Text)
        "I" -> Ok(Binary)
        unknown -> {
          logging.log(logging.Warning, "Unknown transfer type: " <> unknown)
          Error(unknown)
        }
      }

      case new_type {
        Ok(t) ->
          Ok(#(
            "200 Changed transfer type",
            ClientState(..state, transfer_type: t),
          ))

        Error(_) -> Error("504 Unknown transfer type")
      }
    }

    ["USER", username] -> {
      logging.log(
        logging.Debug,
        "User '" <> username <> "' is trying to log in",
      )
      let state = ClientState(..state, auth: Authenticating(username))
      Ok(#("331 Password required", state))
    }

    ["PASS", password] ->
      case state.auth {
        Authenticating(username) -> handle_login(state, username, password)
        _ -> Error("500 Invalid state")
      }

    ["QUIT"] -> {
      Ok(#(
        "221 Goodbye!",
        ClientState(..state, auth: Unauthenticated, closing: True),
      ))
    }

    ["PORT", data] -> {
      case data |> string.split(",") |> list.map(int.parse) {
        [Ok(h1), Ok(h2), Ok(h3), Ok(h4), Ok(p1), Ok(p2)] ->
          handle_begin_active(
            glisten.IpV4(h1, h2, h3, h4),
            utils.ftp_decode_port_num(p1, p2),
            state,
          )
        _ -> Error("504 Invalid parameters")
      }
    }

    ["PASV"] -> handle_begin_passive(state, opts)

    ["LIST"] -> {
      case state.auth {
        Authenticated(_username) -> {
          case state.data_conn {
            Passive(sub) -> {
              let data =
                bytes_tree.from_string(
                  "-rw-r--r-- 1 user group 1234 Aug  7 12:00 file.txt\r\ndrwxr-xr-x 2 user group 4096 Aug  7 12:01 folder\r\n",
                )
              sub
              |> actor.send(passive.SendToClient(data, state.sock, "226 Done"))
              Ok(#("150 Sending over passive connection...", state))
            }
            _ -> Error("450 No valid data connection")
          }
        }
        _ -> Error("530 Please login first")
      }
    }

    unknown -> {
      logging.log(
        logging.Warning,
        "Unknown FTP command: " <> string.inspect(unknown),
      )
      Error("502 Unknown command")
    }
  }
}

fn handle_login(
  state: ClientState,
  username: String,
  password: String,
) -> Result(#(String, ClientState), String) {
  let actual_pw = username <> "!"
  case password {
    pw if actual_pw == pw -> {
      logging.log(
        logging.Info,
        "User '" <> username <> "' logged in successfully",
      )
      let state = ClientState(..state, auth: Authenticated(username))
      Ok(#("230 Logged in!", state))
    }
    _ -> Error("430 Invalid UN/PW")
  }
}

fn handle_begin_active(
  addr: glisten.IpAddress,
  port: Int,
  state: ClientState,
) -> Result(#(String, ClientState), String) {
  logging.log(
    logging.Debug,
    "Using active channel to "
      <> string.inspect(addr)
      <> " on port "
      <> int.to_string(port),
  )

  Ok(#(
    "200 Accepted",
    ClientState(..state, data_conn: Active(addr, port, option.None)),
  ))
}

fn handle_begin_passive(
  state: ClientState,
  opts: cli.ServerOpts,
) -> Result(#(String, ClientState), String) {
  let addr = utils.string_to_ipv4_address(opts.external_address)
  let sock =
    tcp.listen(0, [
      options.ActiveMode(options.Passive),
      options.Ip(options.Address(addr)),
    ])

  case sock {
    Ok(s) -> {
      let addr_nums = case addr {
        options.IpV4(a, b, c, d) ->
          [a, b, c, d] |> list.map(int.to_string) |> string.join(",")
        options.IpV6(a, b, c, d, e, f, g, h) ->
          [a, b, c, d, e, f, g, h]
          |> list.map(int.to_string)
          |> string.join(",")
      }

      let assert Ok(#(_, actual_port)) = tcp.sockname(s)
      let port_nums =
        utils.ftp_encode_port_num(actual_port)
        |> fn(x) { [x.0, x.1] }
        |> list.map(int.to_string)
        |> string.join(",")

      let actor =
        actor.new(passive.Listening(s))
        |> actor.on_message(passive.conn_handle_msg)
        |> actor.start()

      case actor {
        Ok(a) -> {
          let state = ClientState(..state, data_conn: Passive(a.data))
          a.data |> actor.send(passive.AcceptConnection)
          Ok(#("227 " <> addr_nums <> "," <> port_nums, state))
        }
        Error(e) -> {
          logging.log(
            logging.Error,
            "Failed to start passive connection actor: " <> string.inspect(e),
          )
          Error("500 Actor start failed")
        }
      }
    }
    Error(e) -> Error("500 failed to listen: " <> string.inspect(e))
  }
}
