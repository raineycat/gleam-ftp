import gftp/cli
import gftp/protocol
import gftp/state
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process
import gleam/list
import gleam/result
import gleam/string
import glisten/socket
import glisten/socket/options.{ActiveMode, Passive}
import glisten/tcp
import logging

pub fn run_server(opts: cli.ServerOpts) {
  case tcp.listen(opts.port, [ActiveMode(Passive)]) {
    Ok(listener) -> {
      process.spawn(fn() { acceptor_loop(listener, opts) })
      Nil
    }
    Error(e) ->
      logging.log(
        logging.Critical,
        "Failed to bind socket: " <> string.inspect(e),
      )
  }

  logging.log(logging.Debug, "Created socket listener")
  process.sleep_forever()
}

fn acceptor_loop(listener: socket.ListenSocket, opts: cli.ServerOpts) {
  case tcp.accept(listener) {
    Ok(connection) -> {
      process.spawn(fn() { client_proc(connection, opts) })
      acceptor_loop(listener, opts)
    }
    Error(e) ->
      logging.log(
        logging.Error,
        "Failed to accept connection: " <> string.inspect(e),
      )
  }
}

fn client_proc(client: socket.Socket, opts: cli.ServerOpts) {
  logging.log(
    logging.Debug,
    "New client connected: " <> string.inspect(tcp.peername(client)),
  )

  let _ =
    tcp.send(
      client,
      bytes_tree.from_string("220 " <> opts.welcome_msg <> "\r\n"),
    )

  client_loop(client, opts, state.new_client(client))
}

fn client_loop(
  client: socket.Socket,
  opts: cli.ServerOpts,
  state: state.ClientState,
) {
  let resp = case tcp.receive(client, 0) {
    Ok(data) -> {
      case parse_command(data) {
        Ok(cmd) -> {
          logging.log(logging.Debug, "Got cmd: " <> string.inspect(cmd))
          protocol.handle_cmd(cmd, state, opts)
        }
        Error(_) -> {
          logging.log(
            logging.Warning,
            "Failed to parse FTP command. Raw: " <> string.inspect(data),
          )
          Error("500 Unparseable command")
        }
      }
    }

    Error(e) -> Error("500 Failed to recieve command: " <> string.inspect(e))
  }

  let _ =
    tcp.send(client, case resp {
      Ok(#(text, _)) -> bytes_tree.from_string(text <> "\r\n")
      Error(msg) -> bytes_tree.from_string(msg <> "\r\n")
    })

  case state.closing {
    True -> {
      let _ = tcp.close(client)
      Nil
    }
    False ->
      client_loop(client, opts, case resp {
        Ok(#(_, new_state)) -> new_state
        Error(_) -> state
      })
  }
}

fn parse_command(data: BitArray) -> Result(List(String), Nil) {
  use str <- result.try(bit_array.to_string(data))
  Ok(
    str
    // remove newline
    |> string.drop_end(1)
    |> string.split(" ")
    |> list.map(fn(x) { x |> string.trim() }),
  )
}
