import gleam/bytes_tree
import gleam/int
import gleam/otp/actor
import gleam/result
import gleam/string
import glisten/socket
import glisten/tcp
import logging

pub type PassiveConnState {
  Listening(server: socket.ListenSocket)
  Connected(client: socket.Socket)
}

pub type PassiveConnMessage {
  AcceptConnection
  SendToClient(
    data: bytes_tree.BytesTree,
    reply_sock: socket.Socket,
    reply: String,
  )
  ReceiveFromClient
}

pub fn conn_handle_msg(
  state: PassiveConnState,
  msg: PassiveConnMessage,
) -> actor.Next(PassiveConnState, PassiveConnMessage) {
  case msg {
    AcceptConnection ->
      case state {
        Listening(server) -> {
          case server |> tcp.accept() {
            Ok(sock) -> {
              logging.log(logging.Debug, "PASV connection established")
              actor.continue(Connected(sock))
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
        Connected(_) -> actor.continue(state)
      }

    SendToClient(data, reply_sock, reply) -> {
      let result = case state {
        Connected(client) -> {
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

    ReceiveFromClient -> {
      actor.continue(state)
    }
  }
}
