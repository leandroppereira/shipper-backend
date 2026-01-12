#!/usr/bin/env bash
set -euo pipefail

APP="shipper-backend"
BUILD_NS="indigo-build"
RUNTIME_NS="indigo"

BUILDER_ISTAG_NS="openshift"
BUILDER_ISTAG_NAME="golang:1.18-ubi9"   # tag latest implícita

INITIAL_APP_REPO="https://github.com/leandroppereira/shipper-backend-initial-build"

echo "==> Descobrindo domínio base do cluster (apps...)"
DOMAIN="$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')"

# Evita host do tipo apps.apps.<...>
if [[ "${DOMAIN}" == apps.* ]]; then
  HOST="${APP}-${RUNTIME_NS}.${DOMAIN}"
else
  HOST="${APP}-${RUNTIME_NS}.apps.${DOMAIN}"
fi

echo "DOMAIN=${DOMAIN}"
echo "HOST=${HOST}"

echo "==> Criando projetos (se já existirem, ok)"
oc new-project "${RUNTIME_NS}" >/dev/null 2>&1 || true
oc new-project "${BUILD_NS}"  >/dev/null 2>&1 || true

echo "==> Garantindo ServiceAccounts do cenário (cria se não existir)"
oc -n "${RUNTIME_NS}" get sa indigo >/dev/null 2>&1 || oc -n "${RUNTIME_NS}" create sa indigo >/dev/null
oc -n "${BUILD_NS}"  get sa indigo-build >/dev/null 2>&1 || oc -n "${BUILD_NS}" create sa indigo-build >/dev/null

echo "==> Checando ImageStreamTag do builder: ${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}"
if ! oc get istag -n "${BUILDER_ISTAG_NS}" "${BUILDER_ISTAG_NAME}" >/dev/null 2>&1; then
  echo "ERRO: Não encontrei istag ${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}"
  exit 1
fi

echo "==> Permissão: SA ${BUILD_NS}/indigo-build pode puxar o builder do namespace ${BUILDER_ISTAG_NS}"
oc policy add-role-to-user system:image-puller -z indigo-build -n "${BUILDER_ISTAG_NS}" >/dev/null 2>&1 || true

echo "==> Permissão: SA ${RUNTIME_NS}/indigo pode puxar imagens do projeto ${BUILD_NS}"
oc policy add-role-to-user system:image-puller -z indigo -n "${BUILD_NS}" >/dev/null 2>&1 || true

echo "==> Criando ImageStream ${APP} no build e no runtime (se não existir)"
oc -n "${BUILD_NS}"  get is "${APP}" >/dev/null 2>&1 || oc -n "${BUILD_NS}"  create is "${APP}" >/dev/null
oc -n "${RUNTIME_NS}" get is "${APP}" >/dev/null 2>&1 || oc -n "${RUNTIME_NS}" create is "${APP}" >/dev/null

echo "==> (Indigo) Garantindo que a aplicação inicial exista (repo initial-build)"
# Se não existir DC nem Deployment com o nome do app, cria.
if ! oc -n "${RUNTIME_NS}" get dc "${APP}" >/dev/null 2>&1 && \
   ! oc -n "${RUNTIME_NS}" get deploy "${APP}" >/dev/null 2>&1; then
  oc -n "${RUNTIME_NS}" new-app --name="${APP}" \
    --image-stream="${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME}" \
    "${INITIAL_APP_REPO}" >/dev/null
fi

echo "==> (Indigo) Garantindo Service ${APP} apontando para o app"
if ! oc -n "${RUNTIME_NS}" get svc "${APP}" >/dev/null 2>&1; then
  if oc -n "${RUNTIME_NS}" get dc "${APP}" >/dev/null 2>&1; then
    oc -n "${RUNTIME_NS}" expose dc/"${APP}" --port=8081 --target-port=8081 --name="${APP}" >/dev/null
  else
    oc -n "${RUNTIME_NS}" expose deploy/"${APP}" --port=8081 --target-port=8081 --name="${APP}" >/dev/null
  fi
fi

echo "==> (Indigo) Garantindo Route ${APP} com hostname no padrão da prova"
# Se não existir route, cria; se existir, recria com host correto (sem patch JSON)
if oc -n "${RUNTIME_NS}" get route "${APP}" >/dev/null 2>&1; then
  oc -n "${RUNTIME_NS}" delete route "${APP}" >/dev/null
fi
oc -n "${RUNTIME_NS}" create route edge "${APP}" --service="${APP}" --hostname="${HOST}" >/dev/null

echo "==> (Indigo) Aguardando rollout do app inicial"
if oc -n "${RUNTIME_NS}" get dc "${APP}" >/dev/null 2>&1; then
  oc -n "${RUNTIME_NS}" rollout status dc/"${APP}" --timeout=240s || true
else
  oc -n "${RUNTIME_NS}" rollout status deploy/"${APP}" --timeout=240s || true
fi

echo
echo "=============================================="
echo "SETUP CONCLUÍDO (cenário pronto)"
echo "- Runtime project:   ${RUNTIME_NS} (app inicial publicado)"
echo "- Build project:     ${BUILD_NS} (pronto para a prova)"
echo "- Builder ISTag:     ${BUILDER_ISTAG_NS}/${BUILDER_ISTAG_NAME} (latest)"
echo "- Route (prova):     https://${HOST}"
echo "=============================================="

