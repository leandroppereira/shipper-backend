#!/usr/bin/env bash
set -euo pipefail

APP=shipper-backend
BUILD_NS=indigo-build
RUNTIME_NS=indigo

echo "==> Apagando recursos do runtime (${RUNTIME_NS})"

if oc get project "${RUNTIME_NS}" >/dev/null 2>&1; then
  oc -n "${RUNTIME_NS}" delete route "${APP}" --ignore-not-found
  oc -n "${RUNTIME_NS}" delete svc "${APP}" --ignore-not-found
  oc -n "${RUNTIME_NS}" delete deploy "${APP}" --ignore-not-found
  oc -n "${RUNTIME_NS}" delete dc "${APP}" --ignore-not-found
  oc -n "${RUNTIME_NS}" delete is "${APP}" --ignore-not-found
  oc -n "${RUNTIME_NS}" delete sa indigo --ignore-not-found
else
  echo "  Namespace ${RUNTIME_NS} não existe, pulando."
fi

echo "==> Apagando recursos de build (${BUILD_NS})"

if oc get project "${BUILD_NS}" >/dev/null 2>&1; then
  oc -n "${BUILD_NS}" delete bc "${APP}" --ignore-not-found
  oc -n "${BUILD_NS}" delete build -l buildconfig="${APP}" --ignore-not-found
  oc -n "${BUILD_NS}" delete is "${APP}" --ignore-not-found
  oc -n "${BUILD_NS}" delete sa indigo-build --ignore-not-found
else
  echo "  Namespace ${BUILD_NS} não existe, pulando."
fi

echo "==> Removendo permissões de image-puller concedidas para este cenário"

# Remove permissão do builder (openshift -> indigo-build)
oc policy remove-role-from-user system:image-puller -z indigo-build -n openshift || true

# Remove permissão do runtime (indigo -> indigo-build)
oc policy remove-role-from-user system:image-puller -z indigo -n indigo-build || true

echo
echo "==> (Opcional) Apagar os projetos inteiros"
echo "    Para apagar tudo, rode manualmente:"
echo "      oc delete project ${RUNTIME_NS}"
echo "      oc delete project ${BUILD_NS}"
echo
echo "Limpeza concluída."
