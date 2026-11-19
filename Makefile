# Athena — Makefile
PREFIX    ?= /usr
BIN_DIR   := $(DESTDIR)$(PREFIX)/bin
DATA_DIR  := $(DESTDIR)$(PREFIX)/share/athena
CONF_DIR  := $(DESTDIR)/etc/athena
SYSTEMD   := $(DESTDIR)/etc/systemd/system
STATE_DIR := $(DESTDIR)/var/lib/athena
RUN_DIR   := /run/athena

.PHONY: all install uninstall check unit integration clean

all:
	@echo "make install      -- Install Athena"
	@echo "make uninstall    -- Uninstall Athena"
	@echo "make check        -- ShellCheck + unit tests"
	@echo "make integration  -- End-to-end tests (real nftables, private netns)"

install:
	@[ $$(id -u) -eq 0 ] || { echo "Error: must be run as root."; exit 1; }
	@command -v nft >/dev/null || { echo "Error: nftables (nft) is required."; exit 1; }
	@command -v journalctl >/dev/null || { echo "Error: systemd-journald is required."; exit 1; }
	install -d -m 755 $(BIN_DIR) $(DATA_DIR) $(CONF_DIR) $(SYSTEMD)
	install -d -m 700 $(STATE_DIR)
	if [ -f $(CONF_DIR)/athena.conf ]; then \
		echo "Keeping existing $(CONF_DIR)/athena.conf"; \
		echo "  (compare it with ./athena.conf: new options have defaults)"; \
	else \
		install -m 640 athena.conf $(CONF_DIR)/athena.conf; \
	fi
	install -m 644 VERSION $(DATA_DIR)/VERSION
	install -m 755 athena-server $(BIN_DIR)/athena-server
	install -m 755 athena $(BIN_DIR)/athena
	install -m 644 athena.service $(SYSTEMD)/athena.service
ifeq ($(DESTDIR),)
	systemctl daemon-reload
	systemctl enable --now athena.service
	@echo "Athena installed -- conf: $(CONF_DIR)/athena.conf | bans: athena -l | logs: journalctl -t athena -f"
else
	@echo "DESTDIR set: files staged in $(DESTDIR), systemctl skipped"
endif

uninstall:
	@[ $$(id -u) -eq 0 ] || { echo "Error: must be run as root."; exit 1; }
	systemctl disable --now athena.service 2>/dev/null || true
	rm -f $(SYSTEMD)/athena.service
	systemctl daemon-reload 2>/dev/null || true
	rm -f $(BIN_DIR)/athena-server $(BIN_DIR)/athena
	rm -rf $(DATA_DIR) $(CONF_DIR) $(STATE_DIR) $(RUN_DIR)
	nft delete table inet athena 2>/dev/null || true
	@echo "Athena uninstalled."

check:
	shellcheck -s bash -S warning athena athena-server tests/*.sh
	bash tests/unit.sh

unit:
	bash tests/unit.sh

integration:
	bash tests/integration.sh

clean:
	rm -f tests/*.log
