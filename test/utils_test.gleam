import gftp/utils
import gleam/int
import glisten/socket/options

pub fn port_num_encoding_test() {
  assert utils.ftp_encode_port_num(1234) == #(4, 210)

  assert utils.ftp_decode_port_num(4, 210) == 1234

  let test_port = int.random(65_535)
  let test_port_encoded = utils.ftp_encode_port_num(test_port)
  assert test_port
    == utils.ftp_decode_port_num(test_port_encoded.0, test_port_encoded.1)
}

pub fn string_to_ipv4_test() {
  let assert Ok(options.IpV4(127, 0, 0, 1)) =
    utils.string_to_ipv4_address("127.0.0.1")
  let assert Ok(options.IpV4(0, 0, 0, 0)) =
    utils.string_to_ipv4_address("0.0.0.0")

  let assert Error(_) = utils.string_to_ipv4_address("")
  let assert Error(_) = utils.string_to_ipv4_address("localhost")
  let assert Error(_) = utils.string_to_ipv4_address("1.2.3")
  let assert Error(_) = utils.string_to_ipv4_address("1.2.3.4.5")
}

pub fn unquote_test() {
  let assert "" = utils.unquote("")
  let assert "xyz" = utils.unquote("xyz")
  let assert "\"xyz" = utils.unquote("\"xyz")
  let assert "xyz" = utils.unquote("\"xyz\"")
  let assert "xyz\"" = utils.unquote("\"xyz\"\"")
}

pub fn normalise_newlines_test() {
  let assert "" = utils.normalise_newlines("")
  let assert "\r\n" = utils.normalise_newlines("\n")
  let assert "\r\ntest\r\n" = utils.normalise_newlines("\ntest\r\n")
  let assert "\r\n\r\n\r\n" = utils.normalise_newlines("\n\r\n\n")
}
