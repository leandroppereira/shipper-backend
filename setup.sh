#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Prova S2I OpenShift – Shipper Backend
# Prepara o ambiente + resolve (build S2I) + testa com curl
#
# Uso:
#   ./lab_s2i_shipper_backend.sh prepare
#   ./lab_s2i_shipper_backend.sh solve
# ==============================================================================

APP="shipper-backend"
BUILD_NS="indigo-build"
RUNTIME_NS="indigo"

BUILDER_ISTAG_NS="openshift"
BUILDER_ISTAG_NAME="golang:1.18-ubi9"   # tag latest implícita

REPO_URL="https://github.com/leandroppereira/shipper-backend.git"
WORKDIR="/tmp/shipper-backend-lab"
SRC_DIR="${WORKDIR}/shipper-backend"

# ------------------------------------------------------------------------------
need_oc() {
  command -v oc >/dev/null 2>&1 || { echo "ERRO: oc não encontrado"; exit 1; }
  oc whoami >/dev/null 2>&1 || { echo "ERRO: não logado no cluster"; exit 1; }
}

ensure_project() {
  oc new-project "$1" >/dev/null 2>&1 || true
}

ensure_sa() {
  if ! oc -n "$1" get sa "$2" >/dev/null 2>&1; then
    oc -n "$1" create sa "$2" >/dev/null
  fi
}

# ------------------------------------------------------------------------------
prepare_env() {
  need_oc

  DOMAIN="$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"

  ensure_project "${BUILD_NS}"
  ensure_project "${RUNTIME_NS}"

  ensure_sa "${BUILD_NS}" "indigo-build"
  ensure_sa "${RUNTIME_NS}" "indigo"

  oc get istag -n "${BUILDER_ISTAG_NS}" "${BUILDER_ISTAG_NAME}" >/dev/null

  oc policy add-role-to-user system:image-puller -z indigo-build -n "${BUILDER_ISTAG_NS}" >/dev/null 2>&1 || true
  oc policy add-role-to-user system:image-puller -z indigo -n "${BUILD_NS}" >/dev/null 2>&1 || true

  oc -n "${BUILD_NS}" get is "${APP}" >/dev/null 2>&1 || oc -n "${BUILD_NS}" create is "${APP}" >/dev/null
  oc -n "${RUNTIME_NS}" get is "${APP}" >/dev/null 2>&1 || oc -n "${RUNTIME_NS}" create is "${APP}" >/dev/null

  if ! oc -n "${RUNTIME_NS}" get deploy "${APP}" >/dev/null 2>&1; then
    oc -n "${RUNTIME_NS}" create deployment "${APP}" --image="${APP}:latest" >/dev/null
  fi

  oc -n "${RUNTIME_NS}" set port deployment/"${APP}" --port=8081 --name=http >/dev/null 2>&1 || true
  oc -n "${RUNTIME_NS}" get svc "${APP}" >/dev/null 2>&1 || \
    oc -n "${RUNTIME_NS}" expose deployment "${APP}" --port=8081 --target-port=8081 --name="${APP}" >/dev/null

  HOST="${APP}-${RUNTIME_NS}.apps.${DOMAIN}"
  oc -n "${RUNTIME_NS}" get route "${APP}" >/dev/null 2>&1 || \
    oc -n "${RUNTIME_NS}" create route edge "${APP}" --service="${APP}" --hostname="${HOST}" >/dev/null

  echo "Route: https://${HOST}"
}

# ------------------------------------------------------------------------------
clone_and_patch() {
  mkdir -p "${WORKDIR}"

  if [[ -d "${SRC_DIR}/.git" ]]; then
    git -C "${SRC_DIR}" pull --rebase
  else
    git clone "${REPO_URL}" "${SRC_DIR}"
  fi

  RUN_FILE="${SRC_DIR}/.s2i/bin/run"

  if ! grep -q '^export SERVER_PORT=8081$' "${RUN_FILE}"; then
    cp "${RUN_FILE}" "${RUN_FILE}.bak"
    tmp="$(mktemp)"
    if head -n1 "${RUN_FILE}" | grep -q '^#!'; then
      awk 'NR==1{print;print "export SERVER_PORT=8081";next}{print}' "${RUN_FILE}" > "${tmp}"
    else
      { echo "export SERVER_PORT=8081"; cat "${RUN_FILE}"; } > "${tmp}"
    fi
    mv "${tmp}" "${RUN_FILE}"
  fi

  chmod +x "${SRC_DIR}/.s2i/bin/"*
}

# ------------------------------------------------------------------------------
build_and_deploy() {
  if ! oc -n "${BUILD_NS}" get bc "${APP}" >/dev/null 2>&1; then
    oc -n "${BUILD_NS}" new-build --name="${APP}" \
      --image-stream="${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}" \
      --binary=true >/dev/null
  fi

  oc -n "${BUILD_NS}" start-build "${APP}" --from-dir="${SRC_DIR}" --follow
  oc tag "${BUILD_NS}/${APP}:latest" "${RUNTIME_NS}/${APP}:latest"
  oc -n "${RUNTIME_NS}" rollout status deployment/"${APP}" --timeout=180s || true
}

# ------------------------------------------------------------------------------
test_app() {
  DOMAIN="$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"
  URL="https://${APP}-${RUNTIME_NS}.apps.${DOMAIN}?id=0001"

  echo "curl ${URL}"
  curl -sk "${URL}"
}

# ------------------------------------------------------------------------------
case "${1:-prepare}" in
  prepare)
    prepare_env
    ;;
  solve)
    prepare_env
    clone_and_patch
    build_and_deploy
    test_app
    ;;
  *)
    echo "Use: $0 prepare | solve"
    exit 1
    ;;
esac

