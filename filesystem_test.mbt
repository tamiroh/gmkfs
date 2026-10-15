///|
/// Exercise the public API without CLI arguments or terminal output.
async test "filesystem exposes readable files and accepts a caller-owned log sink" {
  let directory = @fs.tmpdir(prefix="gmkfs-api-")
  defer @fs.rmdir(directory, recursive=true)
  @fs.write_file(
    "\{directory}/Custom.mk",
    "output.txt: input.txt\n\t@echo build-log\n\t@cp input.txt output.txt\n.PHONY: clean\nclean:\n\t@rm -f output.txt\n",
  )
  @fs.write_file("\{directory}/input.txt", "hello from the library")
  let diagnostics = @process.redirect_to_file(
    "\{directory}/diagnostics.log",
    shared=true,
  )
  defer diagnostics.close()
  let filesystem = @gmkfs.FileSystem::open(
    directory~,
    makefile="Custom.mk",
    diagnostics~,
  )
  assert_eq(filesystem.list(), ["output.txt"])
  assert_false(@fs.exists("\{directory}/output.txt"))
  let file = filesystem.open_file("output.txt")
  defer file.close()
  assert_eq(file.read_exactly_at(4, position=6L), b"from")
  assert_eq(file.read_all().text(), "hello from the library")
  assert_true(
    @fs.read_file("\{directory}/diagnostics.log").text().contains("build-log"),
  )
}
