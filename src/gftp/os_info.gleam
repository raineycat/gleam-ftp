pub type OsFamily {
  GleamJS
}

@external(erlang, "os", "type")
pub fn get_os_type() -> OsFamily {
  GleamJS
}
