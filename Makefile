# Athena — Makefile
PREFIX    ?= /usr
BIN_DIR   := $(PREFIX)/bin
CONF_DIR  := /etc/athena
SYSTEMD   := /etc/systemd/system

.PHONY: all install uninstall

all:
	@echo "make install    -- Install Athena"
	@echo "make uninstall  -- Uninstall Athena"

install:
	@[ $$(id -u) -eq 0 ] || { echo "Error: must be run as root."; exit 1; }
	install -d -m 755 $(CONF_DIR)
	[ -f $(CONF_DIR)/athena.conf ] || install -m 640 athena.conf $(CONF_DIR)/athena.conf
	install -m 755 athena-server $(BIN_DIR)/athena-server
	install -m 755 athena        $(BIN_DIR)/athena
	install -m 644 athena.service $(SYSTEMD)/athena.service
	systemctl daemon-reload
	systemctl enable --now athena.service
	@echo "Athena installed -- conf: $(CONF_DIR)/athena.conf | logs: journalctl -u athena -f"

uninstall:
	@[ $$(id -u) -eq 0 ] || { echo "Error: must be run as root."; exit 1; }
	systemctl disable --now athena.service 2>/dev/null || true
	rm -f $(SYSTEMD)/athena.service
	systemctl daemon-reload
	rm -f $(BIN_DIR)/athena-server $(BIN_DIR)/athena
	nft delete table inet athena 2>/dev/null || true
	rm -rf $(CONF_DIR)
	@echo "Athena uninstalled."
