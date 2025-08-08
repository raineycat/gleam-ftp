import gleam/bytes_tree
import gleam/erlang/process
import glisten
import glisten/socket

pub type ClientState {
  ClientState(
    sock: socket.Socket,
    auth: AuthState,
    closing: Bool,
    working_dir: String,
    transfer_type: TransferType,
    data_conn: DataConnection,
    encoding: EncodingType,
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

pub type EncodingType {
  Ascii
  UTF8
}

pub type DataConnection {
  None
  Passive(conn: process.Subject(PassiveConnMessage))
  Active(addr: glisten.IpAddress, port: Int)
}

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

pub fn new_client(sock: socket.Socket) -> ClientState {
  ClientState(
    sock:,
    auth: Unauthenticated,
    closing: False,
    working_dir: "/",
    transfer_type: Text,
    data_conn: None,
    encoding: Ascii,
  )
}
