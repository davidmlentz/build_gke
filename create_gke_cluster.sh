#!/bin/bash
#
# From https://cloud.google.com/kubernetes-engine/docs/tutorials/installing-istio
# From https://istio.io/docs/examples/bookinfo/
#

echo "Please provide the name of the cluster being created:"
read MY_CLUSTER_NAME

echo "Please provide the email address for your GCP account:"
read GCP_EMAIL

echo "Please provide your DD API key:"
read MY_DD_API_KEY

echo "Please provide the name of the GCP project in which to build the cluster:"
read MY_GCP_PROJECT

echo "In which zone do you want to build the cluster (e.g., us-west1-b):"
read MY_GCP_ZONE

gcloud config set account $GCP_EMAIL
gcloud config set project $MY_GCP_PROJECT
# Next command creates the cluster.
# The app won't work if the machine type is smaller than an n1-standard-2.
# This is set as an autoscaling group with init size of 4.
gcloud container clusters create $MY_CLUSTER_NAME --enable-autoscaling --min-nodes=4 --max-nodes=6 --machine-type=n1-standard-2 --num-nodes=4 --no-enable-legacy-authorization --project $MY_GCP_PROJECT --zone=$MY_GCP_ZONE --image-type ubuntu
gcloud container clusters list > clusternames_data
grep "$MY_CLUSTER_NAME" clusternames_data
if [ $? -ne 0 ]; then
	echo "Failed to add the cluster"
else
	gcloud container clusters get-credentials $MY_CLUSTER_NAME --zone $MY_GCP_ZONE --project $MY_GCP_PROJECT
	kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin   --user="$(gcloud config get-value core/account)"
	curl -L https://git.io/getLatestIstio | ISTIO_VERSION=1.1.3 sh -
	cd istio-1.1.3/
	export PATH=$PWD/bin:$PATH
	kubectl apply -f install/kubernetes/istio-demo-auth.yaml
	kubectl apply -f <(istioctl kube-inject -f samples/bookinfo/platform/kube/bookinfo.yaml)
	kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
	#kubectl get svc istio-ingressgateway -n istio-system
fi
rm -f clusternames_data

curl https://gist.githubusercontent.com/davidmlentz/5d620644563d64d95adff8b36e90c500/raw/2b48837b8ec9da34a93f3b01cf93c56dc7e1a301/datadog-agent.yaml | sed "s/^\(.*\)value: <MY_DD_API_KEY>/\1value: $MY_DD_API_KEY/" > datadog-agent.yaml

while [ ! -f datadog-agent.yaml ]; do
        sleep 2
done;

TELEMETRY_IP=`kubectl get svc istio-telemetry -n istio-system -o=json | grep '"clusterIP"' | sed 's/[^0-9.]//g'`
sed -i '' "s/%%TELEMETRY_IP%%/$TELEMETRY_IP/g" datadog-agent.yaml

PROMETHEUS_IP=`kubectl get svc prometheus -n istio-system -o=json | grep '"clusterIP"' | sed 's/[^0-9.]//g'`
sed -i '' "s/%%PROMETHEUS_IP%%/$PROMETHEUS_IP/g" datadog-agent.yaml

kubectl create --save-config -f datadog-agent.yaml

helm template install/kubernetes/helm/istio-init --name istio-init --namespace istio-system | kubectl apply -f -
helm template install/kubernetes/helm/istio --name istio --namespace istio-system --set pilot.traceSampling=100.0 --set global.proxy.tracer=datadog | kubectl apply -f -

sleep 2

ready=0

while [ $ready -eq 0 ]; do
  data=`kubectl get pods | awk '{print $3}'`
  while IFS= read -r line
    do
      if [[ $line == 'STATUS' ]]; then
        continue
      elif [[ $line != 'Running' ]]; then
        ready=0
        mydate=`date +"%T"`
        echo "$mydate Waiting. Pod status is \"$line\""
        sleep 8
        continue 2
      fi
    done <<< "$data"
    ready=1
done;

INGRESS_IP=`kubectl get svc istio-ingressgateway -n istio-system -o=json | grep '"ip"' | sed 's/[^0-9.]//g'`

echo "This test app is available at $INGRESS_IP"
echo "You can test it with this command, which should return a \"200\":"
echo "curl -I http://$INGRESS_IP/productpage"
