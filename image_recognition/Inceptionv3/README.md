### Build image
VERSION=1.13.0
TAG=intel-mkl-${VERSION}
DOCKER_URL=docker.io/karthikvadla/kfserving
MKL_IMAGE_TAG=${DOCKER_URL}:${TAG}


TF_SERVING_VERSION=${VERSION} MKL_IMAGE_TAG=${MKL_IMAGE_TAG} bash build_mkl_tfserving_image.sh

docker push ${DOCKER_URL}:${TAG}

### Download model
curl -O https://storage.googleapis.com/intel-optimized-tensorflow/models/inceptionv3_fp32_pretrained_model.pb

### config map

BUCKET=kvadla
MODEL_PATH=inceptionv3
EXPORT_DIR=gs://${BUCKET}/${MODEL_PATH}
gsutil ls -r ${EXPORT_DIR}


OMP_NUM_THREADS=2
TENSORFLOW_INTER_OP_PARALLELISM=1
TENSORFLOW_INTRA_OP_PARALLELISM=2

kustomize edit add configmap inceptionv3-map-serving --from-literal=name=inceptionv3-gcs-dist

kustomize edit add configmap inceptionv3-map-serving --from-literal=modelBasePath=${EXPORT_DIR}

kustomize edit add configmap inceptionv3-map-serving --from-literal=OMP_NUM_THREADS=${OMP_NUM_THREADS}
kustomize edit add configmap inceptionv3-map-serving --from-literal=TENSORFLOW_INTER_OP_PARALLELISM=${TENSORFLOW_INTER_OP_PARALLELISM}
kustomize edit add configmap inceptionv3-map-serving --from-literal=TENSORFLOW_INTRA_OP_PARALLELISM=${TENSORFLOW_INTRA_OP_PARALLELISM}


### build and deploy

kustomize build . |kubectl apply -f -


kubectl describe deployments inceptionv3-gcs-dist

kubectl describe service inceptionv3-gcs-dist


### check pod is running
POD_NAME=$(kubectl get pods --selector=app=inceptionv3 --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
kubectl logs -f ${POD_NAME}

cleanup
------

kubectl delete deploy inceptionv3-gcs-dist
kubectl delete service inceptionv3-gcs-dist



### port forward
POD_NAME=$(kubectl get pods --selector=app=inceptionv3 --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

kubectl port-forward ${POD_NAME} 8500:8500


### predict

pip install virtualenv
virtualenv venv_inceptionv3

source venv_inceptionv3/bin/activate
pip install -r requirements.txt


### test
python image_recognition_client.py --model inceptionv3