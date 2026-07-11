# Makefile — Desafio DevOps (Bookinfo / Istio / Kubernetes)
#
# Uso principal:
#   make bootstrap   -> monta o ambiente inteiro do zero, do zero absoluto
#   make destroy      -> derruba tudo
#   make dashboards    -> reabre os túneis de acesso (Grafana/Kiali/Prometheus)
#   make resume         -> retoma o ambiente após reiniciar a máquina
#
# Cada alvo abaixo também pode ser rodado isoladamente, na ordem numérica
# dos scripts, se precisar reexecutar só uma etapa específica.

SHELL := /usr/bin/env bash
SCRIPTS := scripts

.PHONY: bootstrap up install-tools cluster istio bookinfo routing enduser \
        observability ratelimit logging mtls traffic dashboards kubectl-env \
        resume destroy down help

help:
	@echo "Alvos disponíveis:"
	@echo "  make bootstrap (ou: make up)   - monta o ambiente inteiro (00 a 09, em ordem)"
	@echo "  make destroy   (ou: make down) - derruba o cluster inteiro"
	@echo "  make install-tools   - instala kubectl/kind/istioctl/helm (versões fixas)"
	@echo "  make cluster         - cria o cluster Kind"
	@echo "  make istio           - instala o Istio + namespaces"
	@echo "  make bookinfo        - aplica a aplicação Bookinfo"
	@echo "  make routing         - aplica o roteamento por host (Escopo 1/3)"
	@echo "  make enduser         - aplica o roteamento por end-user (Escopo 2/3)"
	@echo "  make observability   - instala Prometheus/Grafana/Kiali + dashboards"
	@echo "  make ratelimit       - aplica o rate limiting por serviço (Escopo 3/3)"
	@echo "  make logging         - instala Loki/Promtail"
	@echo "  make mtls            - aplica mTLS STRICT + regressao dos 3 escopos"
	@echo "  make traffic         - gera tráfego de teste (60s, popula os dashboards)"
	@echo "  make dashboards      - reabre os túneis de acesso aos dashboards"
	@echo "  make kubectl-env     - configura alias/env var do kubectl (k + KUBECONFIG)"
	@echo "  make resume          - retoma o ambiente após reiniciar a máquina"

up: bootstrap

bootstrap: install-tools cluster istio bookinfo routing enduser observability ratelimit logging mtls kubectl-env
	@echo ""
	@echo ">>> Ambiente completo. Rode 'make traffic' para gerar tráfego de teste,"
	@echo ">>> ou acesse os dashboards diretamente (túneis já abertos por 'observability')."

install-tools:
	$(SCRIPTS)/00-install-tools.sh

cluster:
	$(SCRIPTS)/01-create-cluster.sh

istio:
	$(SCRIPTS)/02-install-istio.sh

bookinfo:
	$(SCRIPTS)/03-deploy-bookinfo.sh

routing:
	$(SCRIPTS)/04-apply-routing.sh

enduser:
	$(SCRIPTS)/05-apply-enduser-routing.sh

observability:
	$(SCRIPTS)/06-install-observability.sh

traffic:
	$(SCRIPTS)/07-generate-traffic.sh 60

ratelimit:
	$(SCRIPTS)/08-apply-ratelimit.sh

logging:
	$(SCRIPTS)/09-install-logging.sh

mtls:
	$(SCRIPTS)/10-apply-mtls.sh

dashboards:
	$(SCRIPTS)/access-dashboards.sh

kubectl-env:
	$(SCRIPTS)/configure-kubectl-env.sh

resume:
	$(SCRIPTS)/resume-cluster.sh

down: destroy

destroy:
	$(SCRIPTS)/99-destroy.sh