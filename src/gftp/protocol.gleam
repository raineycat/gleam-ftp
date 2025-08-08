import birl
import filepath
import gftp/cli
import gftp/os_info
import gftp/passive
import gftp/state
import gftp/utils
import gleam/bytes_tree
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten
import glisten/socket
import glisten/tcp
import logging
import mug
import simplifile

pub fn handle_cmd(
  cmd: List(String),
  state: state.ClientState,
  opts: cli.ServerOpts,
) -> Result(#(String, state.ClientState), String) {
  case cmd {
    ["SYST"] ->
      Ok(#(
        "215 UNIX Type: L8 | " <> string.inspect(os_info.get_os_type()),
        state,
      ))

    ["STAT"] ->
      Ok(#(
        "211- gFTP Status:\r\n Gleam/Erlang server on "
          <> string.inspect(os_info.get_os_type())
          <> "\r\n MOTD: "
          <> opts.welcome_msg
          <> "\r\n Address: "
          <> opts.external_address
          <> "\r\n Server: https://github.com/raineycat/gleam-ftp\r\n "
          <> get_status_string(state)
          <> "\r\n211 End of status",
        state,
      ))

    ["FEAT"] ->
      Ok(#(
        "211-Extensions supported:\r\n " <> "SIZE" <> "\r\n211 End extensions",
        state,
      ))

    ["HELP", ..] ->
      Ok(#(
        "214 For help, see: https://en.wikipedia.org/wiki/List_of_FTP_commands",
        state,
      ))

    ["NOOP"] -> Ok(#("200 No-op", state))

    ["PWD"] | ["XPWD"] -> Ok(#("257 \"" <> state.working_dir <> "\"", state))

    ["CWD", ..rest] | ["XCWD", ..rest] -> {
      let dir = rest |> string.join(" ")
      let dir = case filepath.is_absolute(dir) {
        True -> dir
        False -> filepath.join(state.working_dir, dir)
      }
      let dir = case filepath.expand(dir) {
        Ok(new) -> new
        Error(_) -> dir
      }

      logging.log(logging.Debug, "Client CWD to: " <> dir)
      let state = state.ClientState(..state, working_dir: dir)
      Ok(#("250 Changed working directory", state))
    }

    ["CDUP"] -> {
      let dir = filepath.directory_name(state.working_dir)
      let dir = case filepath.expand(dir) {
        Ok(new) -> new
        Error(_) -> dir
      }

      logging.log(logging.Debug, "Client CWD to: " <> dir)
      let state = state.ClientState(..state, working_dir: dir)
      Ok(#("250 Changed working directory", state))
    }

    ["TYPE", new_type] -> {
      let new_type = case new_type {
        "A" -> Ok(state.Text)
        "I" -> Ok(state.Binary)
        unknown -> {
          logging.log(logging.Warning, "Unknown transfer type: " <> unknown)
          Error(unknown)
        }
      }

      case new_type {
        Ok(t) ->
          Ok(#(
            "200 Changed transfer type",
            state.ClientState(..state, transfer_type: t),
          ))

        Error(_) -> Error("504 Unknown transfer type")
      }
    }

    ["OPTS", "UTF8", mode] -> {
      logging.log(logging.Debug, "UTF-8 support: " <> mode)
      let encoding = case mode {
        "ON" -> state.UTF8
        _ -> state.Ascii
      }
      let state = state.ClientState(..state, encoding: encoding)
      Ok(#("200 Done", state))
    }

    ["OPTS", ..params] -> {
      logging.log(
        logging.Warning,
        "Unknown option: " <> string.join(params, ": "),
      )
      Error("504 Unknown option")
    }

    ["USER", username] -> {
      logging.log(logging.Info, "User '" <> username <> "' is trying to log in")
      let state =
        state.ClientState(..state, auth: state.Authenticating(username))
      Ok(#("331 Password required", state))
    }

    ["PASS", password] ->
      case state.auth {
        state.Authenticating(username) ->
          handle_login(state, opts, username, password)
        _ -> Error("500 Invalid state")
      }

    ["QUIT"] -> {
      logging.log(logging.Info, "Client disconnected")
      Ok(#(
        "221 Goodbye!",
        state.ClientState(..state, auth: state.Unauthenticated, closing: True),
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

    ["PASV"] -> passive.handle_begin_passive(state, opts)

    ["LIST"] -> {
      case state.auth {
        state.Authenticated(_username) -> {
          let path = transform_path(opts, state.working_dir)
          case read_dir_ex(path) {
            Ok(dir_list) ->
              transmit_on_data_ch(
                state,
                bytes_tree.from_string(string.join(dir_list, "\r\n") <> "\r\n"),
                "226 Finished transfer",
              )
            Error(e) -> {
              logging.log(
                logging.Warning,
                "Failed to list dir: " <> path <> ": " <> string.inspect(e),
              )
              Error("451 Failed to list dir: " <> string.inspect(e))
            }
          }
        }
        _ -> Error("530 Please login first")
      }
    }

    ["NLST"] -> {
      case state.auth {
        state.Authenticated(_username) -> {
          let path = transform_path(opts, state.working_dir)
          case simplifile.read_directory(path) {
            Ok(dir_list) ->
              transmit_on_data_ch(
                state,
                bytes_tree.from_string(string.join(dir_list, "\r\n") <> "\r\n"),
                "226 Finished transfer",
              )
            Error(e) -> {
              logging.log(
                logging.Warning,
                "Failed to list dir: " <> path <> ": " <> string.inspect(e),
              )
              Error("451 Failed to list dir: " <> string.inspect(e))
            }
          }
        }
        _ -> Error("530 Please login first")
      }
    }

    ["ALLO"] -> Ok(#("202 Obsolete", state))

    ["SIZE", path] -> {
      let path = path |> utils.unquote()
      Error("502 Command not implemented: " <> path)
    }

    ["RETR", path] -> {
      let path =
        path
        |> utils.unquote()
        |> filepath.join(state.working_dir, _)
        |> transform_path(opts, _)
      logging.log(logging.Debug, "Client get file: " <> path)

      case
        case state.transfer_type {
          state.Text -> handle_text_read(path)
          state.Binary -> handle_binary_read(path)
        }
      {
        Ok(data) -> transmit_on_data_ch(state, data, "226 Finished transfer")
        Error(e) -> {
          logging.log(
            logging.Warning,
            "Failed to transmit file: " <> string.inspect(e),
          )
          Error("502 TODO")
        }
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
  state: state.ClientState,
  opts: cli.ServerOpts,
  username: String,
  password: String,
) -> Result(#(String, state.ClientState), String) {
  let res =
    opts.allowed_logins
    |> list.find(fn(login) {
      let #(actual_user, actual_pw) = login
      actual_user == username && actual_pw == password
    })

  case res {
    Ok(login) -> {
      let #(actual_user, _) = login
      logging.log(
        logging.Info,
        "User '" <> actual_user <> "' logged in successfully",
      )
      let state =
        state.ClientState(..state, auth: state.Authenticated(actual_user))
      Ok(#("230 Logged in!", state))
    }
    Error(_) -> Error("430 Invalid UN/PW")
  }
}

fn handle_begin_active(
  addr: glisten.IpAddress,
  port: Int,
  state: state.ClientState,
) -> Result(#(String, state.ClientState), String) {
  logging.log(
    logging.Debug,
    "Using active channel to "
      <> string.inspect(addr)
      <> " on port "
      <> int.to_string(port),
  )

  Ok(#(
    "200 Accepted",
    state.ClientState(..state, data_conn: state.Active(addr, port)),
  ))
}

fn transmit_on_data_ch(
  state: state.ClientState,
  data: bytes_tree.BytesTree,
  resp: String,
) -> Result(#(String, state.ClientState), String) {
  case state.data_conn {
    state.Passive(sub) -> {
      sub
      |> actor.send(state.SendToClient(data, state.sock, resp))
      Ok(#("150 Sending over passive connection...", state))
    }
    state.Active(addr, port) -> {
      case mug.new(glisten.ip_address_to_string(addr), port) |> mug.connect() {
        Ok(sock) -> {
          process.spawn(fn() {
            active_send_handler(
              sock,
              data,
              state.sock,
              bytes_tree.from_string(resp <> "\r\n"),
            )
          })
          Ok(#("150 Sending over active connection...", state))
        }
        Error(e) ->
          Error("500 Failed to connect to active socket: " <> string.inspect(e))
      }
    }
    _ -> Error("450 No valid data connection")
  }
}

fn active_send_handler(
  data_sock: mug.Socket,
  data: bytes_tree.BytesTree,
  reply_sock: socket.Socket,
  reply: bytes_tree.BytesTree,
) {
  case data_sock |> mug.send(bytes_tree.to_bit_array(data)) {
    Ok(_) -> {
      let _ = data_sock |> mug.shutdown()
      let _ = reply_sock |> tcp.send(reply)
      Nil
    }
    Error(e) ->
      logging.log(
        logging.Warning,
        "Failed to send over active conn: " <> string.inspect(e),
      )
  }
}

fn get_status_string(state: state.ClientState) -> String {
  "Auth: "
  <> string.inspect(state.auth)
  <> "; Type: "
  <> string.inspect(state.transfer_type)
  <> "; Encoding: "
  <> string.inspect(state.encoding)
  <> ";"
}

fn transform_path(opts: cli.ServerOpts, path: String) -> String {
  let path = case filepath.is_absolute(path) {
    True -> path |> string.drop_start(1)
    False -> path
  }

  let path = filepath.join(opts.base_dir, path)

  let path = case filepath.expand(path) {
    Ok(p) -> p
    Error(_) -> path
  }

  logging.log(logging.Debug, "Transformed path: " <> path)
  path
}

fn read_dir_ex(path: String) -> Result(List(String), simplifile.FileError) {
  use files <- result.try(simplifile.read_directory(path))
  Ok(
    files
    |> list.map(fn(name) {
      let item_path = filepath.join(path, name)
      get_ls_file_info(item_path)
    })
    |> list.filter(fn(x) { result.is_ok(x) })
    |> list.map(fn(x) { result.unwrap(x, "") }),
  )
}

fn get_ls_file_info(item_path: String) {
  use info <- result.try(simplifile.file_info(item_path))
  let _perms = simplifile.file_info_permissions(info)

  use is_dir <- result.try(simplifile.is_directory(item_path))
  let dir_marker = case is_dir {
    True -> "d"
    False -> "-"
  }
  // todo: actual permission reporting
  let permission_string = case is_dir {
    True -> "rwxr-xr-x"
    False -> "rw-r--r--"
  }
  let size_string = info.size |> int.to_string() |> string.pad_start(13, " ")
  let modified_at = birl.from_unix(info.mtime_seconds)
  let modified_day = modified_at |> birl.get_day()

  Ok(
    dir_marker
    <> permission_string
    <> " 1 root root "
    <> size_string
    <> " "
    <> birl.short_string_month(modified_at)
    <> " "
    <> int.to_string(modified_day.date)
    <> "  "
    <> int.to_string(modified_day.year)
    <> " "
    <> filepath.base_name(item_path),
  )
}

fn handle_binary_read(
  real_path: String,
) -> Result(bytes_tree.BytesTree, simplifile.FileError) {
  case simplifile.read_bits(real_path) {
    Ok(data) -> Ok(bytes_tree.from_bit_array(data))
    Error(e) -> Error(e)
  }
}

fn handle_text_read(
  real_path: String,
) -> Result(bytes_tree.BytesTree, simplifile.FileError) {
  case simplifile.read(real_path) {
    Ok(text) ->
      Ok(bytes_tree.from_string(
        { text |> utils.normalise_newlines() } <> "\r\n",
      ))
    Error(e) -> Error(e)
  }
}
