///|
fn make_env() -> Map[String, String] {
  // Inherited dry-run/question flags must never turn a read into stale output.
  {
    "LC_ALL": "C",
    "MAKEFLAGS": "",
    "MFLAGS": "",
    "GNUMAKEFLAGS": "",
    "MAKEOVERRIDES": "",
  }
}

///|
async fn choose_make(requested : String?) -> String {
  let candidates = match requested {
    Some(program) => [program]
    None => ["gmake", "make"]
  }
  for program in candidates {
    let version = try {
      let (code, output, _) = @process.collect_output(
        program,
        ["--version"],
        extra_env=make_env(),
      )
      if code == 0 {
        output.text()
      } else {
        ""
      }
    } catch {
      _ => ""
    }
    if version.has_prefix("GNU Make ") && !version.has_prefix("GNU Make 3.") {
      let (code, help, _) = @process.collect_output(
        program,
        ["--help"],
        extra_env=make_env(),
      )
      if code == 0 && help.text().contains("--eval") {
        return program
      }
    }
  }
  fail("GNU make with --eval support is required")
}
