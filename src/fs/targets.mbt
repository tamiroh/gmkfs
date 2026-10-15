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
