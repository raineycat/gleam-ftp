import gleam/int
import gleam/list
import gleam/string
import glisten/socket/options

pub fn ftp_encode_port_num(port: Int) -> #(Int, Int) {
  #(port / 256, port % 256)
}

pub fn ftp_decode_port_num(a: Int, b: Int) -> Int {
  a * 256 + b
}

pub fn string_to_ipv4_address(addr: String) -> options.IpAddress {
  case addr |> string.split(".") |> list.map(int.parse) {
    [Ok(h1), Ok(h2), Ok(h3), Ok(h4)] -> options.IpV4(h1, h2, h3, h4)
    _ -> panic as { "Invalid IPv4 address: " <> addr }
  }
}

pub fn unquote(s: String) -> String {
  case string.starts_with(s, "\"") && string.starts_with(s, "\"") {
    True -> s |> string.drop_start(1) |> string.drop_end(1)
    False -> s
  }
}

pub fn normalise_newlines(text: String) -> String {
  text |> string.replace("\r\n", "\n") |> string.replace("\n", "\r\n")
}
