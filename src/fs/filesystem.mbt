///|
/// A Makefile-backed filesystem rooted at a fixed working directory.
/// Diagnostics are routed to the caller's sink, never directly to stdio.
/// The caller owns the sink and must keep it open while using this filesystem.
/// File/pipe redirections must be created with `shared=true` for reuse across
/// make invocations. Standard IO sinks are already reusable.
pub struct FileSystem {
  priv directory : String
  priv makefile : String
  priv program : String
  priv diagnostics : &@process.ProcessOutput
}

///|
/// Resolve the working directory and select GNU make once per instance.
pub async fn FileSystem::open(
  directory~ : String = ".",
  makefile~ : String = "Makefile",
  program? : String,
  diagnostics~ : &@process.ProcessOutput,
) -> FileSystem {
  let directory = @host_fs.realpath(directory)
  let program = choose_make(program)
  { directory, makefile, program, diagnostics, }
}

///|
/// List supported explicit targets, excluding .PHONY and make special targets.
pub async fn FileSystem::list(self : FileSystem) -> Array[String] {
  // An isolated goal avoids traversing the default goal, including recursive
  // recipes which GNU make may otherwise execute even in question mode.
  let probe = "__gmkfs_probe_\{@env.now()}__"
  let (status, output) = @process.collect_stdout(
    self.program,
    [
      "--no-print-directory",
      "-q",
      "-p",
      "-f",
      self.makefile,
      "--eval=\{probe}: ;",
      "--",
      probe,
    ],
    cwd=self.directory,
    stderr=self.diagnostics,
    extra_env=make_env(),
  )
  if status != 0 && status != 1 {
    fail("cannot inspect Makefile (make exited \{status})")
  }
  targets_from_database(output.text(), probe)
}

///|
/// Build a visible target and open its generated file for reading.
/// The caller owns the returned file and must close it. It supports streaming
/// and positional reads, so adapters do not need to buffer the entire output.
/// Concurrent builds are not serialized by this prototype.
pub async fn FileSystem::open_file(
  self : FileSystem,
  target : String,
) -> @host_fs.File {
  guard valid_target(target) else { fail("unsupported target name: \{target}") }
  guard self.list().contains(target) else {
    fail("target is not exposed (unknown, .PHONY, or unsupported): \{target}")
  }
  let status = @process.run(
    self.program,
    ["--no-print-directory", "-f", self.makefile, "--", target],
    cwd=self.directory,
    extra_env=make_env(),
    stdout=self.diagnostics,
    stderr=self.diagnostics,
  )
  guard status == 0 else {
    fail("build failed (make exited \{status}): \{target}")
  }
  let path = "\{self.directory}/\{target}"
  guard @host_fs.kind(path) == @host_fs.Regular else {
    fail("target did not produce a regular file: \{target}")
  }
  @host_fs.open(path, mode=ReadOnly)
}
