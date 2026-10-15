.PHONY: all clean

all: hello.txt

hello.txt: source.txt
	@echo 'Building hello.txt' >&2
	tr '[:lower:]' '[:upper:]' < source.txt > hello.txt

clean:
	rm -f hello.txt
