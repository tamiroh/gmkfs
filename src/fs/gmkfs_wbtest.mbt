///|
test "target names cannot become make options or variable assignments" {
  for name in ["-f", "X=value", "../escape", "/absolute", "a b", "a\nb", "%.o"] {
    assert_false(valid_target(name))
  }
  assert_true(valid_target("build/hello.txt"))
  assert_true(valid_target(".hidden"))
}

///|
test "database hides phony targets, source files, special and builtin rules" {
  let database =
    #|# Files
    #|
    #|hello.txt: source.txt
    #|#  File has not been updated.
    #|
    #|clean:
    #|#  Phony target (prerequisite of .PHONY).
    #|
    #|# Not a target:
    #|source.txt:
    #|
    #|.PHONY: clean
    #|
    #|probe:
    #|
    #|# Not a target:
    #|.c.o:
    #|#  recipe to execute (built-in):
    #|
    #|# files hash-table stats:
  assert_eq(targets_from_database(database, "probe"), ["hello.txt"])
}
