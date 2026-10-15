///|
const Usage : String = "Usage: gmkfs [-C DIRECTORY] [-f MAKEFILE] [--make PROGRAM] ls | cat TARGET\n"

///|
/// Only unambiguous relative file names are supported by the first prototype.
fn valid_target(name : String) -> Bool {
  !name.is_empty() &&
  !name.has_prefix("-") &&
  !name.has_prefix("/") &&
  !name.contains_any(chars=" \t\r\n:=%\\$#*?[]();|&\u{0000}") &&
  !name.split("/").any(part => part == ".." || part == "." || part == "")
}

///|
/// Read GNU make's expanded database rather than parsing Makefile syntax.
fn targets_from_database(database : String, probe : String) -> Array[String] {
  let targets : Map[String, Bool] = Map([])
  let mut in_files = false
  let mut not_target = false
  let mut current : String? = None
  for line in database.split("\n") {
    if line == "# Files" {
      in_files = true
      continue
    }
    if !in_files {
      continue
    }
    if line.has_prefix("# files hash-table") {
      break
    }
    if line.is_empty() {
      not_target = false
      current = None
    } else if line == "# Not a target:" {
      not_target = true
    } else if line.has_prefix("#  Phony target") ||
      (line.has_prefix("#") && line.contains("(built-in)")) {
      if current is Some(name) {
        targets[name] = false
      }
    } else if !line.has_prefix("#") &&
      !line.has_prefix("\t") &&
      !line.has_prefix(" ") {
      if line.split_once(":") is Some((name, _)) {
        let name = name.to_owned()
        current = Some(name)
        if !targets.contains(name) {
          targets[name] = !not_target &&
            valid_target(name) &&
            name != probe &&
            ![
              ".PHONY", ".SUFFIXES", ".DEFAULT", ".PRECIOUS", ".INTERMEDIATE", ".SECONDARY",
              ".SECONDEXPANSION", ".DELETE_ON_ERROR", ".IGNORE", ".LOW_RESOLUTION_TIME",
              ".SILENT", ".EXPORT_ALL_VARIABLES", ".NOTPARALLEL", ".ONESHELL", ".POSIX",
              ".WAIT", ".NOTINTERMEDIATE",
            ].contains(name)
        }
      }
    }
  }
  let result : Array[String] = []
  for name, visible in targets {
    if visible {
      result.push(name)
    }
  }
  result.sort_by(String::lexical_compare)
  result
}

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
  fail("GNU make with --eval support is required (on macOS: brew install make)")
}

///|
pub async fn run(args : ArrayView[String]) -> Unit {
  let mut directory = "."
  let mut makefile = "Makefile"
  let mut program : String? = None
  let mut i = 0
  while i < args.length() && args[i].has_prefix("-") {
    let option = args[i]
    if option == "--help" || option == "-h" {
      @stdio.stdout.write(Usage)
      return
    }
    guard i + 1 < args.length() else { fail(Usage) }
    match option {
      "-C" => directory = args[i + 1]
      "-f" => makefile = args[i + 1]
      "--make" => program = Some(args[i + 1])
      _ => fail(Usage)
    }
    i += 2
  }
  guard i < args.length() else { fail(Usage) }
  let command = args[i]
  guard (command == "ls" && args.length() == i + 1) ||
    (command == "cat" && args.length() == i + 2) else {
    fail(Usage)
  }
  let target = if command == "cat" { args[i + 1] } else { "" }
  if command == "cat" && !valid_target(target) {
    fail("unsupported target name: \{target}")
  }
  let make = choose_make(program)
  // An isolated goal avoids traversing the default goal, including recursive
  // recipes which GNU make may otherwise execute even in question mode.
  let probe = "__gmkfs_probe_\{@env.now()}__"
  let (status, output, errors) = @process.collect_output(
    make,
    [
      "--no-print-directory",
      "-q",
      "-p",
      "-f",
      makefile,
      "--eval=\{probe}: ;",
      "--",
      probe,
    ],
    cwd=directory,
    extra_env=make_env(),
  )
  @stdio.stderr.write(errors)
  if status != 0 && status != 1 {
    fail("cannot inspect Makefile (make exited \{status})")
  }
  let targets = targets_from_database(output.text(), probe)
  if command == "ls" {
    for name in targets {
      @stdio.stdout.write("\{name}\n")
    }
    return
  }
  guard targets.contains(target) else {
    fail("target is not exposed (unknown, .PHONY, or unsupported): \{target}")
  }
  let status = @process.run(
    make,
    ["--no-print-directory", "-f", makefile, "--", target],
    cwd=directory,
    extra_env=make_env(),
    stdout=@stdio.stderr,
    stderr=@stdio.stderr,
  )
  guard status == 0 else {
    fail("build failed (make exited \{status}): \{target}")
  }
  let path = "\{directory}/\{target}"
  guard @fs.kind(path) == @fs.Regular else {
    fail("target did not produce a regular file: \{target}")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  @stdio.stdout.write_reader(file)
}
