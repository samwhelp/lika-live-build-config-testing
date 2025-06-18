
default: help
.PHONY: default

help:
	@echo 'Usage:'
	@echo '	$$ make [action]'
	@echo
	@echo 'Ex:'
	@echo '	$$ make'
	@echo '	$$ make help'
	@echo
	@echo '	$$ make build'
	@echo
.PHONY: help




build:
	@./build.sh
.PHONY: build




xfce:
	sudo ./steps.sh --debug --verbose --variant xfce
.PHONY: xfce


kde:
	sudo ./steps.sh --debug --verbose --variant kde
.PHONY: kde


mate:
	sudo ./steps.sh --debug --verbose --variant mate
.PHONY: mate


gnome:
	sudo ./steps.sh --debug --verbose --variant gnome
.PHONY: gnome


i3:
	sudo ./steps.sh --debug --verbose --variant i3
.PHONY: i3


e17:
	sudo ./steps.sh --debug --verbose --variant e17
.PHONY: e17


minimal:
	sudo ./steps.sh --debug --verbose --variant minimal
.PHONY: minimal
