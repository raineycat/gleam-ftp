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
