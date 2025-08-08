import clip.{type Command}
import clip/opt.{type Opt}

pub type ServerOpts {
  ServerOpts(
    bind_addr: String,
    port: Int,
    welcome_msg: String,
    external_address: String,
    base_dir: String,
  )
}

fn str_opt(name: String, help_text: String, default: String) -> Opt(String) {
  opt.new(name) |> opt.help(help_text) |> opt.default(default)
}

fn int_opt(name: String, help_text: String, default: Int) -> Opt(Int) {
  opt.new(name) |> opt.int |> opt.help(help_text) |> opt.default(default)
}

pub fn command() -> Command(ServerOpts) {
  clip.command({
    use address <- clip.parameter
    use port <- clip.parameter
    use welcome <- clip.parameter
    use external <- clip.parameter
    use base_dir <- clip.parameter

    ServerOpts(address, port, welcome, external, base_dir)
  })
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
}
