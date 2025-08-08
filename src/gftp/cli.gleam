import clip.{type Command}
import clip/flag.{type Flag}
import clip/opt.{type Opt}
import gleam/list
import gleam/string

pub type ServerOpts {
  ServerOpts(
    bind_addr: String,
    port: Int,
    welcome_msg: String,
    external_address: String,
    base_dir: String,
    allowed_logins: List(#(String, String)),
    allow_anon: Bool,
    anons_can_write: Bool,
    read_only: Bool,
  )
}

fn str_opt(name: String, help_text: String, default: String) -> Opt(String) {
  opt.new(name) |> opt.help(help_text) |> opt.default(default)
}

fn int_opt(name: String, help_text: String, default: Int) -> Opt(Int) {
  opt.new(name) |> opt.int |> opt.help(help_text) |> opt.default(default)
}

fn flag_opt(name: String, help_text: String) -> Flag {
  flag.new(name) |> flag.help(help_text)
}

pub fn command() -> Command(ServerOpts) {
  clip.command({
    use allow_anon <- clip.parameter
    use anons_can_write <- clip.parameter
    use read_only <- clip.parameter
    use bind_addr <- clip.parameter
    use port <- clip.parameter
    use welcome_msg <- clip.parameter
    use external_address <- clip.parameter
    use base_dir <- clip.parameter
    use logins <- clip.parameter

    let login_list =
      logins
      |> string.split(",")
      |> list.map(fn(x) {
        case x |> string.split(":") {
          [user, pw] -> #(user, pw)
          _ -> panic as "Invalid login given!"
        }
      })

    ServerOpts(
      bind_addr:,
      port:,
      welcome_msg:,
      external_address:,
      base_dir:,
      allowed_logins: login_list,
      allow_anon:,
      anons_can_write:,
      read_only:,
    )
  })
  |> clip.flag(flag_opt("allow-anon", "Allow anonymous client connections"))
  |> clip.flag(flag_opt(
    "anons-can-write",
    "Allow anonymous clients to perform create/write/delete operations",
  ))
  |> clip.flag(flag_opt(
    "read-only",
    "Block all create/write/delete operations to the server",
  ))
  |> clip.opt(str_opt("address", "The address to bind to", "0.0.0.0"))
  |> clip.opt(int_opt("port", "The port to listen on", 21))
  |> clip.opt(str_opt(
    "welcome",
    "The welcome message to send to connecting clients",
    "GleamFTP Server",
  ))
  |> clip.opt(str_opt(
    "external-address",
    "The server's public IPv4 address, sent to passive mode clients",
    "127.0.0.1",
  ))
  |> clip.opt(str_opt("base-dir", "The base directory to serve files from", "."))
  |> clip.opt(str_opt(
    "allowed-logins",
    "A list of users and passwords to allow logins from. Format: 'user1:pw1,user2:pw2'",
    "root:root",
  ))
}
