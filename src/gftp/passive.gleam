import gftp/cli
import gftp/state
import gftp/utils
import gleam/bytes_tree
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten/socket
import glisten/socket/options
import glisten/tcp
import logging

pub fn handle_begin_passive(
  state: state.ClientState,
  opts: cli.ServerOpts,
) -> Result(#(String, state.ClientState), String) {
  use addr <- result.try(
    case utils.string_to_ipv4_address(opts.external_address) {
      Ok(a) -> Ok(a)
      Error(_) -> Error("504 Invalid listen address")
    },
  )

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
        actor.new(state.Listening(s))
        |> actor.on_message(conn_handle_msg)
        |> actor.start()

      case actor {
        Ok(a) -> {
          let state =
            state.ClientState(..state, data_conn: state.Passive(a.data))
          a.data |> actor.send(state.AcceptConnection)
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

pub fn conn_handle_msg(
  state: state.PassiveConnState,
  msg: state.PassiveConnMessage,
) -> actor.Next(state.PassiveConnState, state.PassiveConnMessage) {
  case msg {
    state.AcceptConnection ->
      case state {
        state.Listening(server) -> {
          case server |> tcp.accept() {
            Ok(sock) -> {
              logging.log(logging.Debug, "PASV connection established")
              actor.continue(state.Connected(sock))
            }
            Error(e) -> {
              logging.log(
                logging.Warning,
                "Failed to accept PASV connection: " <> string.inspect(e),
              )
              actor.continue(state)
            }
          }
        }
        state.Connected(_) -> actor.continue(state)
      }

    state.SendToClient(data, reply_sock, reply) -> {
      let result = case state {
        state.Connected(client) -> {
          use _ <- result.try(client |> tcp.send(data))
          use _ <- result.try(client |> tcp.close())
          Ok(Nil)
        }
        _ -> Error(socket.Closed)
      }

      case result {
        Ok(_) -> {
          logging.log(
            logging.Debug,
            "Sent "
              <> int.to_string(bytes_tree.byte_size(data))
              <> " bytes over PASV",
          )

          let _ = tcp.send(reply_sock, bytes_tree.from_string(reply <> "\r\n"))
          Nil
        }

        Error(e) -> {
          logging.log(
            logging.Warning,
            "Failed to transmit data over PASV: " <> string.inspect(e),
          )
          let _ =
            tcp.send(
              reply_sock,
              bytes_tree.from_string("425 Failed to transfer\r\n"),
            )
          Nil
        }
      }

      actor.continue(state)
    }

    state.ReceiveFromClient(callback, reply_sock) -> {
      let result = case state {
        state.Connected(client) -> {
          use data <- result.try(
            client |> tcp.receive(0) |> result.map_error(string.inspect),
          )
          logging.log(logging.Debug, "Got PASV data: " <> string.inspect(data))
          use _ <- result.try(
            client |> tcp.close() |> result.map_error(string.inspect),
          )
          Ok(bytes_tree.from_bit_array(data))
        }
        _ -> Error("Passive not connected")
      }

      case result {
        Ok(data) -> {
          logging.log(
            logging.Debug,
            "Received "
              <> int.to_string(bytes_tree.byte_size(data))
              <> " bytes over PASV",
          )

          let reply = callback(data)
          let _ = tcp.send(reply_sock, bytes_tree.from_string(reply <> "\r\n"))
          Nil
        }

        Error(e) -> {
          logging.log(
            logging.Warning,
            "Failed to receive data over PASV: " <> e,
          )

          let _ =
            tcp.send(
              reply_sock,
              bytes_tree.from_string("425 Failed to transfer\r\n"),
            )
          Nil
        }
      }

      actor.continue(state)
    }
  }
}
