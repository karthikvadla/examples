# Intel-optimized Inceptionv3 on Kubeflow using KFServing

This example guides you through the process of taking a pre-trained InceptionV3 from [Model Zoo for Intel® Architecture](https://github.com/IntelAI/models/blob/master/benchmarks/image_recognition/tensorflow/inceptionv3/README.md#fp32-inference-instructions),
modifying it to run better within Kubeflow and serving it.

## Prerequisites

Before we get started there are a few requirements.

### Deploy Kubeflow

Follow the [Getting Started Guide](https://www.kubeflow.org/docs/started/getting-started/) to deploy Kubeflow.

### Local Setup

You also need the following command line tools (Latest Versions):

- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [kustomize](https://kustomize.io/)
- [pip](https://pypi.org/project/pip/)
- [virtualenv](https://packaging.python.org/guides/installing-using-pip-and-virtual-environments/)

To convert frozen graph to `SavedModel` format and run the client at the end of the example, you must have [requirements.txt](requirements.txt) intalled in your active python environment.

```
sudo apt-get install -y python python-pip
pip install virtualenv

virtualenv venv_inceptionv3

source venv_inceptionv3/bin/activate
pip install -r requirements.txt
```

NOTE: These instructions rely on Github, and may cause issues if behind a firewall with many Github users.


### Build and Push Intel Optimized Tensorflow Serving Image
* We have provided a script (`build_mkl_tfserving_image.sh`) to build intel-optimized tensorflow serving image. or For manual instructions follow [this](https://github.com/IntelAI/models/blob/master/docs/general/tensorflow_serving/InstallationGuide.md#step-1-build-tensorflow-serving-docker-image).
* First time build takes longer, but all consecutive builds should be faster as docker uses cached layers.
* After image is built, push it your public registry. We will use this image in future steps
```
VERSION=1.13.0
TAG=intel-mkl-${VERSION}
DOCKER_URL=docker.io/karthikvadla/kfserving
MKL_IMAGE_TAG=${DOCKER_URL}:${TAG}

TF_SERVING_VERSION=${VERSION} MKL_IMAGE_TAG=${MKL_IMAGE_TAG} bash build_mkl_tfserving_image.sh

docker push ${MKL_IMAGE_TAG}
```
*NOTE:*
Registry - `docker.io`,
Account - `karthikvadla`,
Repositry - `kfserving`,
Tag - `intel-mkl-${VERSIO}`


### Download Pre-trained model and convert it to SavedModel format
```
curl -O https://storage.googleapis.com/intel-optimized-tensorflow/models/inceptionv3_fp32_pretrained_model.pb

python model_graph_to_saved_model.py --import_path inceptionv3_fp32_pretrained_model.pb
```

### Upload SavedModel to GCS

* Follow instrcutions from [here](https://cloud.google.com/storage/docs/creating-buckets#storage-create-bucket-console) to create bucket in GCS
* Create a folder named `inceptionv3` inside your bucket
* Now upload `/tmp/1` into `inceptionv3` folder created above.
* The number 1 is a version number auto-generated by TensorFlow.
```
BUCKET=kvadla
MODEL_PATH=inceptionv3
EXPORT_DIR=gs://${BUCKET}/${MODEL_PATH}
```
Your `gustil ls` should look similar to below strcuture.
```
❯❯❯ gsutil ls -r ${EXPORT_DIR}
gs://kvadla/inceptionv3/:
gs://kvadla/inceptionv3/

gs://kvadla/inceptionv3/1/:
gs://kvadla/inceptionv3/1/saved_model.pb

gs://kvadla/inceptionv3/1/variables/:
gs://kvadla/inceptionv3/1/variables/
```

### Preparing your Kubernetes Cluster

In the following instructions we will install our required components to a single namespace.  For these instructions we will assume the chosen namespace is `kubeflow`.

```
kubectl config set-context $(kubectl config current-context) --namespace=kubeflow
```

### Serving Model on GCS
To serve model follow the instructions below.

Enter the `serving/GCS` from the `inceptionv3` application directory.
```
cd serving/GCS
```
Set a different name for the tf-serving.
```
kustomize edit add configmap inceptionv3-map-serving --from-literal=name=inceptionv3-gcs-dist```
```
Set your model path
```
kustomize edit add configmap inceptionv3-map-serving --from-literal=modelBasePath=${EXPORT_DIR}
```

Set OMP_NUM_THREADS, TENSORFLOW_INTER_OP_PARALLELISM, TENSORFLOW_INTRA_OP_PARALLELISM.

Do `lscpu` on one of the Google Compute Node and set values.

`OMP_NUM_THREADS` - <No.of total physical cores>

`TENSORFLOW_INTER_OP_PARALLELISM` - <No.of Sockets>

`TENSORFLOW_INTRA_OP_PARALLELISM` - <No.of total physical cores>

```
OMP_NUM_THREADS=2
TENSORFLOW_INTER_OP_PARALLELISM=1
TENSORFLOW_INTRA_OP_PARALLELISM=2

kustomize edit add configmap inceptionv3-map-serving --from-literal=OMP_NUM_THREADS=${OMP_NUM_THREADS}
kustomize edit add configmap inceptionv3-map-serving --from-literal=TENSORFLOW_INTER_OP_PARALLELISM=${TENSORFLOW_INTER_OP_PARALLELISM}
kustomize edit add configmap inceptionv3-map-serving --from-literal=TENSORFLOW_INTRA_OP_PARALLELISM=${TENSORFLOW_INTRA_OP_PARALLELISM}

```

Deploy it, and run a service to make the deployment accessible to other pods in the cluster

```
kustomize build . |kubectl apply -f -
```

You can check the deployment by running

```
kubectl describe deployments inceptionv3-gcs-dist
```

The service should make the `inceptionv3-gcs-dist` deployment accessible over port 9000

```
kubectl describe service inceptionv3-gcs-dist
```

### Check Pod is Running
```
POD_NAME=$(kubectl get pods --selector=app=inceptionv3 --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

kubectl logs -f ${POD_NAME}
```
Output:
```
...
2019-06-10 22:44:26.180124: I external/org_tensorflow/tensorflow/cc/saved_model/loader.cc:285] SavedModel load for tags { serve }; Status: success. Took 1880903 microseconds.
2019-06-10 22:44:26.558636: I tensorflow_serving/servables/tensorflow/saved_model_warmup.cc:101] No warmup data file found at gs://kvadla/inceptionv3/1/assets.extra/tf_serving_warmup_requests
2019-06-10 22:44:27.411891: I tensorflow_serving/core/loader_harness.cc:86] Successfully loaded servable version {name: inceptionv3 version: 1}
2019-06-10 22:44:27.472020: I tensorflow_serving/model_servers/server.cc:313] Running gRPC ModelServer at 0.0.0.0:9000 ...
2019-06-10 22:44:27.483710: I tensorflow_serving/model_servers/server.cc:333] Exporting HTTP/REST API at:localhost:8500 ...
[evhttp_server.cc : 237] RAW: Entering the event loop ...
```
### Port Forward
Now port-forward to test the prediction
```
POD_NAME=$(kubectl get pods --selector=app=inceptionv3 --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')

kubectl port-forward ${POD_NAME} 8500:9000
```
Output:
```
Forwarding from 127.0.0.1:8500 -> 9000
Forwarding from [::1]:8500 -> 9000
```

### Predict
```
python image_recognition_client.py --model inceptionv3
```
Output:
```
...
    float_val: 7.56564134008e-07
    float_val: 6.91181753609e-07
    float_val: 1.3730318642e-06
    float_val: 5.56109171157e-06
    float_val: 6.40515224859e-07
    float_val: 2.25296626013e-05
    float_val: 2.65208727797e-05
  }
}
model_spec {
  name: "inceptionv3"
  version {
    value: 1
  }
  signature_name: "serving_default"
}

Predicted class:  286
```

### Cleanup
```
kubectl delete deploy inceptionv3-gcs-dist
kubectl delete service inceptionv3-gcs-dist
kubectl delete cm inceptionv3-deploy-config
```