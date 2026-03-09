#!/bin/bash

# ==========================================
# 0. 설정 변수 및 현재 경로 저장
# ==========================================
GRAFANA_SVC="grafana-service"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"
GRAFANA_PORT="3000"
PROMETHEUS_URL="http://prometheus-service:9090"
DASHBOARD_FILE="grafana.json"

# YAML 및 JSON 파일들이 위치한 현재 디렉터리 경로를 저장해 둡니다.
ORIGINAL_DIR=$(pwd)

# ==========================================
# 1. Google Cloud CLI 및 GKE Auth 플러그인 설치
# ==========================================
echo "🚀 [Phase 1] Google Cloud CLI 다운로드 및 설치를 시작합니다..."
cd ~
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz
tar -xf google-cloud-cli-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh --quiet

# 비대화형(non-interactive) 스크립트에서는 source ~/.bashrc 가 무시될 수 있으므로
# 아래 명령어들에서 ~/google-cloud-sdk/bin/ 절대 경로를 직접 사용합니다.
echo "🚀 GKE Auth Plugin을 설치합니다..."
~/google-cloud-sdk/bin/gcloud components install gke-gcloud-auth-plugin --quiet
~/google-cloud-sdk/bin/gke-gcloud-auth-plugin --version

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# ==========================================
# 2. GKE 클러스터 자격 증명 획득
# ==========================================
echo "🚀 [Phase 2] GKE 클러스터(vllm-cluster) 자격 증명을 가져옵니다..."
~/google-cloud-sdk/bin/gcloud container clusters get-credentials vllm-cluster --zone us-central1-a

# ==========================================
# 3. 쿠버네티스 리소스 배포
# ==========================================
echo "🚀 [Phase 3] 쿠버네티스 리소스를 배포합니다..."
# YAML 파일이 있던 원래 폴더로 복귀
cd "$ORIGINAL_DIR"

kubectl apply -f vllm.yaml
kubectl apply -f prometheus.yaml
kubectl apply -f grafana.yaml

# 파드들이 생성될 수 있는 최소한의 시간을 줍니다.
sleep 3

# ==========================================
# 4. EXTERNAL-IP 할당 대기
# ==========================================
echo "⏳ [Phase 4] [$GRAFANA_SVC]의 EXTERNAL-IP 할당을 대기 중입니다..."

while true; do
  EXTERNAL_IP=$(kubectl get svc $GRAFANA_SVC | awk 'NR==2 {print $4}')
  
  if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "<pending>" ] && [ "$EXTERNAL_IP" != "<none>" ]; then
    echo "✅ EXTERNAL-IP 할당 완료: $EXTERNAL_IP"
    break
  fi
  
  echo "   아직 할당되지 않았습니다 (<pending>). 5초 후 다시 확인합니다..."
  sleep 5
done

GRAFANA_API_URL="http://${GRAFANA_USER}:${GRAFANA_PASS}@${EXTERNAL_IP}:${GRAFANA_PORT}"

# ==========================================
# 5. Grafana API 서버 준비 상태 대기 (Health Check)
# ==========================================
echo "⏳ [Phase 5] Grafana API 서버가 시작될 때까지 대기합니다 (이 작업은 수십 초 이상 걸릴 수 있습니다)..."

while ! curl -s -f -o /dev/null "${GRAFANA_API_URL}/api/health"; do
  echo "   Grafana가 아직 준비되지 않았습니다. 5초 후 다시 확인합니다..."
  sleep 5
done
echo "✅ Grafana API 서버 준비 완료!"

# ==========================================
# 6. Prometheus 데이터 소스 추가
# ==========================================
echo "🚀 [Phase 6] Prometheus 데이터 소스를 추가합니다..."
curl -s -X POST "${GRAFANA_API_URL}/api/datasources" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "'"${PROMETHEUS_URL}"'",
    "access": "proxy",
    "isDefault": true
  }'
echo -e "\n✅ 데이터 소스 추가 완료!"

# ==========================================
# 7. 대시보드 Import
# ==========================================
if [ -f "$DASHBOARD_FILE" ]; then
  echo "🚀 [$DASHBOARD_FILE] 파일을 사용하여 대시보드를 생성합니다..."
  
  jq '{dashboard: (. | .id = null), overwrite: true, folderId: 0}' "$DASHBOARD_FILE" > payload.json
  
  curl -s -X POST "${GRAFANA_API_URL}/api/dashboards/db" \
    -H "Content-Type: application/json" \
    -d @payload.json
    
  rm -f payload.json
  echo -e "\n✅ 대시보드 Import 완료!"
else
  echo "❌ 오류: $DASHBOARD_FILE 파일을 찾을 수 없어 대시보드 생성을 건너뜁니다."
fi

echo "🎉 모든 클러스터 셋업 및 Grafana 설정이 완료되었습니다!"
echo "👉 브라우저에서 접속: http://${EXTERNAL_IP}:${GRAFANA_PORT}"