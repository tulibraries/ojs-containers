.DEFAULT_GOAL := help

# Select the project-specific Compose environment file. Local development uses
# .env when present; fresh checkouts and CI fall back to the safe template.
#   make ENV_FILE=.env.tupj.local up
ENV_FILE ?= $(if $(wildcard .env),.env,.env.example)
COMPOSE := ENV_FILE=$(ENV_FILE) docker compose --env-file $(ENV_FILE)
APP_SERVICE ?= app
IMAGE ?= local/ojs:3_4_0-9

.PHONY: help config build rebuild up down restart ps logs shell scheduled jobs scan

help:
	@echo "OJS container commands"
	@echo "  make ENV_FILE=.env.tupj.local config    Validate Compose configuration"
	@echo "  make ENV_FILE=.env.tupj.local build     Build the application image"
	@echo "  make ENV_FILE=.env.tupj.local up        Start the stack"
	@echo "  make ENV_FILE=.env.tupj.local down      Stop the stack"
	@echo "  make ENV_FILE=.env.tupj.local restart   Rebuild and restart the app"
	@echo "  make ENV_FILE=.env.tupj.local logs      Follow application logs"
	@echo "  make ENV_FILE=.env.tupj.local shell     Open a www-data shell"
	@echo "  make ENV_FILE=.env.tupj.local scheduled Run OJS scheduled tasks"
	@echo "  make ENV_FILE=.env.tupj.local jobs      Run queued OJS jobs"
	@echo "  make IMAGE=... scan                      Scan an image with Trivy"

config:
	$(COMPOSE) config --quiet

build:
	$(COMPOSE) build $(APP_SERVICE)

rebuild:
	$(COMPOSE) build --no-cache $(APP_SERVICE)

up:
	$(COMPOSE) up

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) up -d --build $(APP_SERVICE)

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs -f --tail=100 $(APP_SERVICE)

shell:
	$(COMPOSE) exec --user www-data $(APP_SERVICE) sh

scheduled:
	$(COMPOSE) exec -T --user www-data $(APP_SERVICE) pkp-run-scheduled

jobs:
	$(COMPOSE) exec -T --user www-data $(APP_SERVICE) sh -lc 'cd /var/www/html/ojs && php lib/pkp/tools/jobs.php run'

scan:
	trivy image --scanners vuln $(IMAGE)
