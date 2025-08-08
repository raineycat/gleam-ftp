import gleam/int
import gleam/list
import gleam/result
import gleam/string
import glisten/socket/options
import simplifile

pub fn ftp_encode_port_num(port: Int) -> #(Int, Int) {
  #(port / 256, port % 256)
}

pub fn ftp_decode_port_num(a: Int, b: Int) -> Int {
  a * 256 + b
}

pub fn string_to_ipv4_address(addr: String) -> Result(options.IpAddress, Nil) {
  case addr |> string.split(".") |> list.map(int.parse) {
    [Ok(h1), Ok(h2), Ok(h3), Ok(h4)] -> Ok(options.IpV4(h1, h2, h3, h4))
    _ -> Error(Nil)
  }
}

pub fn unquote(s: String) -> String {
  case string.starts_with(s, "\"") && string.ends_with(s, "\"") {
    True -> s |> string.drop_start(1) |> string.drop_end(1)
    False -> s
  }
}

pub fn normalise_newlines(text: String) -> String {
  text |> string.replace("\r\n", "\n") |> string.replace("\n", "\r\n")
}

pub fn fs_exists(path: String) -> Bool {
  simplifile.is_file(path) |> result.unwrap(False)
  || simplifile.is_directory(path) |> result.unwrap(False)
  || simplifile.is_symlink(path) |> result.unwrap(False)
}
