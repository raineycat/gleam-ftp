import argv
import clip
import clip/help
import gftp/cli
import gftp/server
import logging

pub fn main() -> Nil {
  logging.configure()
  logging.set_level(logging.Debug)

  logging.log(logging.Info, "Starting gFTP")

  let arg = argv.load()
  let result =
    cli.command()
    |> clip.help(help.simple(arg.program, "Run the gFTP server"))
    |> clip.run(arg.arguments)

  case result {
    Ok(opts) -> {
      logging.log(logging.Debug, "Loaoded CLI args")
      server.run_server(opts)
    }
    Error(e) -> {
      logging.log(logging.Critical, "Failed to parse arguments: " <> e)
      panic
    }
  }
}
