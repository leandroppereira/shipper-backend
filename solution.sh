#!/usr/bin/env bash
# ==============================================================================
# Prova S2I OpenShift (sem fork): prepara ambiente + build S2I via Binary Build
# + publica no projeto indigo + testa com curl (comando do enunciado)
#
# Uso:
#   ./lab_s2i_shipper_backend.sh prepare
#   ./lab_s2i_shipper_backend.sh solve
#
# O que o script faz no "solve":
#  - clona o repo oficial localmente
#  - altera .s2i/bin/run para exportar SERVER_PORT=8081 (mudança pedida)
#  - cria BuildConfig S2I com --binary usando openshift/golang:1.18-ubi9:latest
#  - start-build --from-dir (usa o código local)
#  - tag para o namespace indigo
#  - testa com curl https://shipper-backend-indigo.apps.<domain>?id=0001
# ==============================================================================

set -euo pipefail

APP="shipper-backend"
BUILD_NS="indigo-build"
RUNTIME_NS="indigo"

BUILDER_ISTAG_NS="openshift"
BUILDER_ISTAG_NAME="golang:1.18-ubi9"   # tag latest implícita no ISTag

REPO_URL="https://github.com/leandroppereira/shipper-backend.git"
WORKDIR="${WORKDIR:-/tmp/shipper-backend-lab}"
SRC_DIR="${WORKDIR}/shipper-backend"

need_oc() {
  command -v oc >/dev/null 2>&1 || { echo "ERRO: oc não encontrado no PATH."; exit 1; }
  oc whoami >/dev/null 2>&1 || { echo "ERRO: você não está logado. Rode: oc login ..."; exit 1; }
}

ensure_project() {
  local ns="$1"
  oc new-project "$ns" >/dev/null 2>&1 || true
}

ensure_sa() {
  local ns="$1"
  local sa="$2"
  if ! oc -n "$ns" get sa "$sa" >/dev/null 2>&1; then
    echo "  Criando ServiceAccount ${ns}/${sa}"
    oc -n "$ns" create sa "$sa" >/dev/null
  else
    echo "  ServiceAccount ${ns}/${sa} já existe"
  fi
}

prepare_env() {
  echo "==> [PREP] Validando acesso ao oc"
  need_oc

  echo "==> [PREP] Descobrindo domínio base do cluster (apps...)"
  DOMAIN="$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
  echo "  DOMAIN=${DOMAIN}"

  echo "==> [PREP] Criando projetos (se já existirem, mantém)"
  ensure_project "${BUILD_NS}"
  ensure_project "${RUNTIME_NS}"

  echo "==> [PREP] Garantindo ServiceAccounts do cenário (cria se não existir)"
  ensure_sa "${RUNTIME_NS}" "indigo"
  ensure_sa "${BUILD_NS}" "indigo-build"

  echo "==> [PREP] Checando ImageStreamTag do builder exigido: ${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}"
  if ! oc get istag -n "${BUILDER_ISTAG_NS}" "${BUILDER_ISTAG_NAME}" >/dev/null 2>&1; then
    echo "ERRO: não encontrei istag ${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}"
    echo "Sem isso não dá para cumprir o enunciado (S2I builder)."
    exit 1
  fi

  echo "==> [PREP] Permissão: SA ${BUILD_NS}/indigo-build pode puxar builder do namespace ${BUILDER_ISTAG_NS}"
  oc policy add-role-to-user system:image-puller -z indigo-build -n "${BUILDER_ISTAG_NS}" >/dev/null 2>&1 || true

  echo "==> [PREP] Criando ImageStreams locais (saída do build e consumo no runtime)"
  oc -n "${BUILD_NS}" get is "${APP}" >/dev/null 2>&1 || oc -n "${BUILD_NS}" create is "${APP}" >/dev/null
  oc -n "${RUNTIME_NS}" get is "${APP}" >/dev/null 2>&1 || oc -n "${RUNTIME_NS}" create is "${APP}" >/dev/null

  echo "==> [PREP] Permissão: SA ${RUNTIME_NS}/indigo pode puxar imagens do projeto ${BUILD_NS}"
  oc policy add-role-to-user system:image-puller -z indigo -n "${BUILD_NS}" >/dev/null 2>&1 || true

  echo "==> [PREP] Preparando runtime (Deployment/Service/Route) no projeto ${RUNTIME_NS}"
  if ! oc -n "${RUNTIME_NS}" get deploy "${APP}" >/dev/null 2>&1 && \
     ! oc -n "${RUNTIME_NS}" get dc "${APP}" >/dev/null 2>&1; then
    oc -n "${RUNTIME_NS}" create deployment "${APP}" --image="${APP}:latest" >/dev/null
  fi

  # Porta do enunciado (SERVER_PORT=8081)
  oc -n "${RUNTIME_NS}" set port deployment/"${APP}" --port=8081 --name=http >/dev/null 2>&1 || true

  if ! oc -n "${RUNTIME_NS}" get svc "${APP}" >/dev/null 2>&1; then
    oc -n "${RUNTIME_NS}" expose deployment "${APP}" --port=8081 --target-port=8081 --name="${APP}" >/dev/null
  fi

  HOST="${APP}-${RUNTIME_NS}.apps.${DOMAIN}"
  if ! oc -n "${RUNTIME_NS}" get route "${APP}" >/dev/null 2>&1; then
    oc -n "${RUNTIME_NS}" create route edge "${APP}" --service="${APP}" --hostname="${HOST}" >/dev/null
  fi

  echo
  echo "=============================================="
  echo "AMBIENTE PREPARADO"
  echo "- Build project:        ${BUILD_NS}"
  echo "- Runtime project:      ${RUNTIME_NS}"
  echo "- Builder ISTag:        ${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME} (tag latest)"
  echo "- SA build:             ${BUILD_NS}/indigo-build"
  echo "- SA runtime:           ${RUNTIME_NS}/indigo"
  echo "- Route (prova):        https://${HOST}"
  echo "=============================================="
  echo
}

clone_and_patch_source() {
  echo "==> [SOLVE] Preparando código-fonte local (sem fork)"
  mkdir -p "${WORKDIR}"

  if [[ -d "${SRC_DIR}/.git" ]]; then
    echo "  Repo já existe em ${SRC_DIR} (fazendo git pull)"
    git -C "${SRC_DIR}" pull --rebase
  else
    echo "  Clonando ${REPO_URL} em ${SRC_DIR}"
    git clone "${REPO_URL}" "${SRC_DIR}"
  fi

  echo "==> [SOLVE] Aplicando alteração exigida: SERVER_PORT=8081 no .s2i/bin/run"
  if [[ ! -f "${SRC_DIR}/.s2i/bin/run" ]]; then
    echo "ERRO: não encontrei ${SRC_DIR}/.s2i/bin/run"
    exit 1
  fi

  # Insere export no topo (idempotente)
  if ! grep -q '^export SERVER_PORT=8081' "${SRC_DIR}/.s2i/bin/run"; then
    cp -a "${SRC_DIR}/.s2i/bin/run" "${SRC_DIR}/.s2i/bin/run.bak"
    # coloca logo após o shebang, se existir; senão, no início
    if head -n1 "${SRC_DIR}/.s2i/bin/run" | grep -q '^#!'; then
      sed -i '2iexport SERVER_PORT=8081' "${SRC_DIR}/.s2i/bin/run"
    else
      sed -i '1iexport SERVER_PORT=8081' "${SRC_DIR}/.s2i/bin/run"
    fi
    echo "  OK: adicionou export SERVER_PORT=8081 (backup em run.bak)"
  else
    echo "  OK: export SERVER_PORT=8081 já estava presente"
  fi

  chmod +x "${SRC_DIR}/.s2i/bin/run" "${SRC_DIR}/.s2i/bin/assemble" 2>/dev/null || true
}

create_binary_buildconfig() {
  echo "==> [SOLVE] Criando BuildConfig S2I (Binary Build) no ${BUILD_NS}"
  # Enunciado:
  # - build em indigo-build
  # - imagens e assets com nome shipper-backend
  # - estender do ISTag latest de openshift/golang:1.18-ubi9
  #
  # Aqui criamos BC com source binary para não depender de fork.
  if ! oc -n "${BUILD_NS}" get bc "${APP}" >/dev/null 2>&1; then
    oc -n "${BUILD_NS}" new-build --name="${APP}" \
      --image-stream="${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}" \
      --binary=true >/dev/null
  else
    echo "  BuildConfig ${BUILD_NS}/${APP} já existe"
  fi
}

run_build_and_deploy() {
  echo "==> [SOLVE] Disparando o build S2I a partir do diretório local"
  oc -n "${BUILD_NS}" start-build "${APP}" --from-dir="${SRC_DIR}" --follow

  echo "==> [SOLVE] Publicando a imagem no projeto runtime (${RUNTIME_NS}) via tag"
  oc tag "${BUILD_NS}/${APP}:latest" "${RUNTIME_NS}/${APP}:latest"

  echo "==> [SOLVE] Aguardando rollout do deployment no runtime"
  oc -n "${RUNTIME_NS}" rollout status deployment/"${APP}" --timeout=180s || true
}

test_solution() {
  echo
  echo "==> [TEST] Comando do enunciado (curl) + comparação visual"
  DOMAIN="$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
  HOST="${APP}-${RUNTIME_NS}.apps.${DOMAIN}"
  TEST_URL="https://${HOST}?id=0001"

  echo "  curl ${TEST_URL}"
  RESP="$(curl -sk "${TEST_URL}" || true)"
  echo "${RESP}"

  echo
  echo "==> [TEST] Resposta esperada:"
  cat <<'EOF'
{
  "shipper_id": "0001",
  "company_name": "ParcelLite",
  "phone": "+1-407-555-0111"
}
EOF
}

solve() {
  clone_and_patch_source
  create_binary_buildconfig
  run_build_and_deploy
  test_solution
}

ACTION="${1:-prepare}"

case "${ACTION}" in
  prepare)
    prepare_env
    ;;
  solve)
    prepare_env
    solve
    ;;
  *)
    echo "Uso:"
    echo "  $0 prepare"
    echo "  $0 solve"
    exit 1
    ;;
esac

