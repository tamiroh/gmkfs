# gmkfs

Treat GNU make targets as files: reading a target builds it and returns the
contents of the resulting file.

## Usage

Requires MoonBit and GNU make 4.4 or later (`brew install make` on macOS).

```sh
# List targets (.PHONY targets are excluded)
moon run src/cmd/main -- -C examples/hello ls

# Build a target and read its contents
moon run src/cmd/main -- -C examples/hello cat hello.txt
```

Use `-C DIRECTORY` to select a working directory, `-f MAKEFILE` to select a
Makefile, and `--make PROGRAM` to select GNU make explicitly.
