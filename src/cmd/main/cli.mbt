///|
const Usage : String = "Usage: gmkfs [-C DIRECTORY] [-f MAKEFILE] [--make PROGRAM] ls | cat TARGET\n"

///|
async fn run(args : ArrayView[String]) -> Unit {
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
  let filesystem = @filesystem.FileSystem::open(
    directory~,
    makefile~,
    program?,
    diagnostics=@stdio.stderr,
  )
  if command == "ls" {
    for name in filesystem.list() {
      @stdio.stdout.write("\{name}\n")
    }
  } else {
    let file = filesystem.open_file(target)
    defer file.close()
    @stdio.stdout.write_reader(file)
  }
}
