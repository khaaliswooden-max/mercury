# Makefile for the AWS F1 host test program.
# Run on the F1 instance after `git clone https://github.com/aws/aws-fpga`
# and `source sdk_setup.sh`.

SDK_DIR ?= $(WORKDIR)/aws-fpga/sdk

CFLAGS  ?= -Wall -Wextra -O2 -std=gnu99
CFLAGS  += -I$(SDK_DIR)/userspace/include
LDLIBS  += -lfpga_mgmt -lpci

test_mercury: test_mercury.c
	$(CC) $(CFLAGS) $< -o $@ $(LDLIBS)

clean:
	rm -f test_mercury

.PHONY: clean
