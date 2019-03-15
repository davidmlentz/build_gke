# build_gke
A script to create a GKE cluster with Istio, bookinfo, and the Datadog Agent

Before running this script:
1. Install gcloud sdk
1. Execute the command to log in to your gcloud account: `gcloud auth login`
1. Install kubectl: `brew install kubernetes-cli`

Clone this repo. `cd` into the directory that creates. Then execute `./create_gke_cluster.sh`.
