# Cloud TPU 및 vLLM 실습
-   https://github.com/cheeunlim/tpu-training-serving


# 목표

Cloud TPU 를 이용하여 GPT2 모델을 Scratch 로 학습 및 vLLM 서빙 테스트를 합니다.

-   JAX 프레임워크를 이용해 TPU 에서 GPT2 아키텍쳐 기반의 sLLM 을 학습합니다.
-   TPU 에서 학습한 모델을 GPU 기반의 vLLM 에서 서빙 테스트를 합니다.
-   오픈 모델들을 Vertex AI 환경에서 GPU 및 TPU 를 이용해 vLLM 서빙 테스트를 합니다.
-   GKE 환경에서 Prometheus, Grafana 를 이용한 vLLM 서빙 환경 구성 및 스트레스 테스트를 합니다.


# Task 1. JAX 프레임워크를 이용해 TPU 에서 GPT2 아키텍쳐 기반의 sLLM 학습

Google Cloud 콘솔에서 'tpu' 를 타이핑 하면 나오는 TPUs 를 클릭합니다.


![image](https://raw.githubusercontent.com/jk1333/handson/main/images/5/1.png)

External IP 를 기록해 두고, 화면의 우측 'SSH' 버튼을 클릭, 'Authorize' 버튼을 클릭 후 Shell 로 진입합니다.

(v6e-1와 v5e-1 모두 생성된 상태라면 v6e-1 을 이용합니다.)

![image](https://raw.githubusercontent.com/jk1333/handson/main/images/5/2.png)

Shell 환경에서 아래의 명령어를 실행합니다.

```
pip install jupyterlab
export PATH="$HOME/.local/bin:$PATH"
jupyter lab --ip 0.0.0.0 --port 8080
```

실행이 완료되면 아래와 같은 JupyterLab 실행 링크가 출력됩니다.
```
http://127.0.0.1:8080/lab?token=b608d06bbd65a41a643c96fa691b2ac74c4ea527fcd99511
```

127.0.0.1 의 IP 주소를 위에서 기록한 External IP 값으로 대체 후 JupyterLab 환경으로 이동합니다.

JupyterLab 페이지가 열리면 Terminal 을 실행, 아래의 명령어로 실습 자료를 다운받습니다.

```
git clone https://github.com/cheeunlim/tpu-training-serving
```

자료 다운로드가 완료되면 아래의 노트북 파일을 열어 실습을 진행합니다.

```
training/JAX_for_LLM_pretraining.ipynb
```

# Task 2. TPU 에서 학습한 모델을 GPU 기반의 vLLM 에서 서빙

본 실습에서는 Task 1 에서 학습한 모델을 NVIDIA L4 GPU 를 이용하여 vLLM 서빙을 합니다.

Task 1 을 성공적으로 마쳤다면, 프로젝트 이름으로 생성된 GCS 버킷에 GPT2/model.safetensors 파일이 생성됩니다.

이 모델 폴더를 GPU 가 탑재된 VM 에서 vLLM 을 이용해 서빙하기 위해 Vertex AI Workbench 환경을 이용합니다.

검색창에서 'workbench' 를 타이핑 하고 나오는 메뉴를 클릭합니다.

![image](https://raw.githubusercontent.com/jk1333/handson/main/images/5/3.png)

Workbench 메뉴로 진입하면 이미 생성된 인스턴스의 Open JupyterLab 버튼을 클릭합니다.

![image](https://raw.githubusercontent.com/jk1333/handson/main/images/5/4.png)

JupyterLab 페이지가 열리면 Terminal 을 실행, 아래의 명령어로 실습 자료를 다운받습니다.

```
git clone https://github.com/cheeunlim/tpu-training-serving
```

자료 다운로드가 완료되면 아래의 노트북 파일을 열어 실습을 진행합니다.

```
serving/python/vLLM_LoadTest.ipynb
```

# Task 3. 오픈 모델들을 Vertex AI 환경에서 GPU 및 TPU 를 이용해 vLLM 서빙

아래의 노트북 파일을 열어 실습을 진행합니다.

두 실습은 독립 실행이 가능하기 때문에 동시에 실행할 수 있습니다.

(TPU 의 경우 Resource 부족 문제로 실패할 수 있습니다.)

```
serving/vertexai/handson-gpu.ipynb
```

```
serving/vertexai/handson-tpu.ipynb
```

# Task 4. GKE 환경에서 Prometheus, Grafana 를 이용한 vLLM 서빙 환경 구성 및 스트레스 테스트

터미널 환경을 실행 후 아래의 명령어를 실행하여 샘플 vLLM 및 모니터링을 위한 Prometheus, Grafana 를 구성합니다.

```
cd ~/tpu-training-serving/serving/gke
chmod +x cluster.sh
./cluster.sh
```

구성이 완료되면 Grafana 대시보드 URL 이 출력됩니다.

이 URL 로 진입 후, admin/admin 으로 로그인, Dashboard -> vLLM 메뉴로 예제 대시보드로 이동합니다.

대시보드의 model_name 에 다음의 값을 입력합니다.
```
mistralai/Mistral-7B-v0.1
```

vLLM 서버가 Online 상태가 될때 까지 약 5분 정도 기다립니다.

아래의 명령어를 실행하여 샘플 트래픽을 vLLM 으로 주입, Dashboard 상에 vLLM 의 트래픽 처리 상태를 확인합니다.

```
kubectl port-forward svc/vllm-service 8000:8000 &
vllm bench serve \
  --backend openai \
  --base-url http://localhost:8000 \
  --model "mistralai/Mistral-7B-v0.1" \
  --dataset-name random \
  --random-input-len 256 \
  --random-output-len 128 \
  --num-prompts 1000 \
  --max-concurrency 32
```