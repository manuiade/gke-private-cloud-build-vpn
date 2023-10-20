#!/bin/bash

PROJECT_ID=$1
PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format='get(projectNumber)')"

gcloud config set project $PROJECT_ID

VPC_PRIVATE_POOL=private-pool-network
VPC_GKE=gke-network
VPC_GKE_SUBNETWORK=gke-subnet
GKE_SUBNET_RANGE=10.100.0.0/20

REGION=europe-west1
CLUSTER=cicd-cluster
ZONE=europe-west1-b
CLUSTER_CONTROL_PLANE_CIDR=172.16.0.32/28
WORKER_POOL=cicd-worker-pool

VPC_PEERING_RANGE=private-pool-gke-peering
PRIVATE_POOL_NETWORK=192.168.0.0
PRIVATE_POOL_PREFIX=16

GW_PRIVATE_POOL=gw-private-pool
GW_GKE=gw-gke
ROUTER_PRIVATE_POOL=router-private-pool
ROUTER_GKE=router-gke
NAT_GKE=nat-gke
ASN_PRIVATE_POOL=65001
ASN_GKE=65002
TUNNEL_PRIVATE_POOL_IF0=tunnel-private-pool-if0
TUNNEL_PRIVATE_POOL_IF1=tunnel-private-pool-if1
TUNNEL_GKE_IF0=tunnel-gke-if0
TUNNEL_GKE_IF1=tunnel-gke-if1

VPN_SHARED_SECRET=$(openssl rand -base64 24)

IP_PRIVATE_POOL_IF0=169.254.0.1
IP_PRIVATE_POOL_IF1=169.254.1.1
IP_GKE_IF0=169.254.0.2
IP_GKE_IF1=169.254.1.2
MASK_LENGTH=30

ROUTER_PRIVATE_POOL_IF0=router-private-pool-if0
PEER_PRIVATE_POOL_IF0=peer-private-pool-if0

ROUTER_PRIVATE_POOL_IF1=router-private-pool-if1
PEER_PRIVATE_POOL_IF1=peer-private-pool-if1

ROUTER_GKE_IF0=router-gke-if0
PEER_GKE_IF0=peer-gke-if0

ROUTER_GKE_IF1=router-gke-if1
PEER_GKE_IF1=peer-gke-if1

APP_REPO=cicd-app
ENV_REPO=cicd-env
APP_IMAGE=cicd-image
APP_TRIGGER=cicd-app-trigger
ENV_TRIGGER=cicd-env-trigger

# Create the 2 VPC
gcloud compute networks create $VPC_PRIVATE_POOL \
    --subnet-mode=custom

gcloud compute networks create $VPC_GKE \
    --subnet-mode=custom

# Create subnetwork
gcloud compute networks subnets create $VPC_GKE_SUBNETWORK \
    --network=$VPC_GKE \
    --range=$GKE_SUBNET_RANGE \
    --region=$REGION

# Create private cluster
gcloud container clusters create $CLUSTER \
  --zone $ZONE \
  --network $VPC_GKE \
  --subnetwork $VPC_GKE_SUBNETWORK \
  --enable-stackdriver-kubernetes \
  --enable-network-policy \
  --enable-private-nodes \
  --master-ipv4-cidr $CLUSTER_CONTROL_PLANE_CIDR \
  --enable-ip-alias \
  --enable-master-authorized-networks \
  --enable-private-endpoint

# Retrieve the vpc network of control plane and export custom routes
GKE_PEERING_NAME=$(gcloud container clusters describe $CLUSTER \
    --zone=$ZONE \
    --format='value(privateClusterConfig.peeringName)')

gcloud compute networks peerings update $GKE_PEERING_NAME \
    --network=$VPC_GKE \
    --export-custom-routes \
    --no-export-subnet-routes-with-public-ip

# Create the VPC peering connection from Worker Pools to GKE master
gcloud compute addresses create $VPC_PEERING_RANGE \
    --global \
    --purpose=VPC_PEERING \
    --addresses=$PRIVATE_POOL_NETWORK \
    --prefix-length=$PRIVATE_POOL_PREFIX \
    --network=$VPC_PRIVATE_POOL

gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=$VPC_PEERING_RANGE \
    --network=$VPC_PRIVATE_POOL

gcloud compute networks peerings update servicenetworking-googleapis-com \
    --network=$VPC_PRIVATE_POOL \
    --export-custom-routes \
    --no-export-subnet-routes-with-public-ip

# Create the private worker pool
gcloud builds worker-pools create $WORKER_POOL \
   --region=$REGION \
   --peered-network=projects/$PROJECT_NUMBER/global/networks/$VPC_PRIVATE_POOL

# Create VPN between the 2 custom VPC
gcloud compute vpn-gateways create $GW_PRIVATE_POOL \
   --network=$VPC_PRIVATE_POOL \
   --region=$REGION

gcloud compute vpn-gateways create $GW_GKE \
   --network=$VPC_GKE \
   --region=$REGION

# Create the 2 router (plus NAT for k8s nodes)
gcloud compute routers create $ROUTER_PRIVATE_POOL \
   --region=$REGION \
   --network=$VPC_PRIVATE_POOL \
   --asn=$ASN_PRIVATE_POOL

gcloud compute routers create $ROUTER_GKE \
    --network=$VPC_GKE \
    --region=$REGION \
    --asn=$ASN_GKE

gcloud compute routers nats create $NAT_GKE \
    --router $ROUTER_GKE \
    --region=$REGION \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges

# Create the 2 HA vpn tunnels
gcloud compute vpn-tunnels create $TUNNEL_PRIVATE_POOL_IF0\
    --peer-gcp-gateway=$GW_GKE \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$VPN_SHARED_SECRET \
    --router=$ROUTER_PRIVATE_POOL \
    --vpn-gateway=$GW_PRIVATE_POOL \
    --interface=0

gcloud compute vpn-tunnels create $TUNNEL_PRIVATE_POOL_IF1\
    --peer-gcp-gateway=$GW_GKE \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$VPN_SHARED_SECRET \
    --router=$ROUTER_PRIVATE_POOL \
    --vpn-gateway=$GW_PRIVATE_POOL \
    --interface=1


gcloud compute vpn-tunnels create $TUNNEL_GKE_IF0\
    --peer-gcp-gateway=$GW_PRIVATE_POOL \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$VPN_SHARED_SECRET \
    --router=$ROUTER_GKE \
    --vpn-gateway=$GW_GKE \
    --interface=0

gcloud compute vpn-tunnels create $TUNNEL_GKE_IF1\
    --peer-gcp-gateway=$GW_PRIVATE_POOL \
    --region=$REGION \
    --ike-version=2 \
    --shared-secret=$VPN_SHARED_SECRET \
    --router=$ROUTER_GKE \
    --vpn-gateway=$GW_GKE \
    --interface=1

# Create bgp sessions
gcloud compute routers add-interface $ROUTER_PRIVATE_POOL \
    --interface-name=$ROUTER_PRIVATE_POOL_IF0 \
    --ip-address=$IP_PRIVATE_POOL_IF0 \
    --mask-length=$MASK_LENGTH \
    --vpn-tunnel=$TUNNEL_PRIVATE_POOL_IF0 \
    --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_PRIVATE_POOL \
    --peer-name=$PEER_PRIVATE_POOL_IF0 \
    --interface=$ROUTER_PRIVATE_POOL_IF0 \
    --peer-ip-address=$IP_GKE_IF0 \
    --peer-asn=$ASN_GKE \
    --region=$REGION

gcloud compute routers add-interface $ROUTER_PRIVATE_POOL \
    --interface-name=$ROUTER_PRIVATE_POOL_IF1 \
    --ip-address=$IP_PRIVATE_POOL_IF1 \
    --mask-length=$MASK_LENGTH \
    --vpn-tunnel=$TUNNEL_PRIVATE_POOL_IF1 \
    --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_PRIVATE_POOL \
    --peer-name=$PEER_PRIVATE_POOL_IF1 \
    --interface=$ROUTER_PRIVATE_POOL_IF1 \
    --peer-ip-address=$IP_GKE_IF1 \
    --peer-asn=$ASN_GKE \
    --region=$REGION


gcloud compute routers add-interface $ROUTER_GKE \
    --interface-name=$ROUTER_GKE_IF0 \
    --ip-address=$IP_GKE_IF0 \
    --mask-length=$MASK_LENGTH \
    --vpn-tunnel=$TUNNEL_GKE_IF0 \
    --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_GKE \
    --peer-name=$PEER_GKE_IF0 \
    --interface=$ROUTER_GKE_IF0 \
    --peer-ip-address=$IP_PRIVATE_POOL_IF0 \
    --peer-asn=$ASN_PRIVATE_POOL \
    --region=$REGION

gcloud compute routers add-interface $ROUTER_GKE \
    --interface-name=$ROUTER_GKE_IF1 \
    --ip-address=$IP_GKE_IF1 \
    --mask-length=$MASK_LENGTH \
    --vpn-tunnel=$TUNNEL_GKE_IF1 \
    --region=$REGION

gcloud compute routers add-bgp-peer $ROUTER_GKE \
    --peer-name=$PEER_GKE_IF1 \
    --interface=$ROUTER_GKE_IF1 \
    --peer-ip-address=$IP_PRIVATE_POOL_IF1 \
    --peer-asn=$ASN_PRIVATE_POOL \
    --region=$REGION


# Advertise routes to private pool VPC network and GKE cluster control plane VPC network
gcloud compute routers update-bgp-peer $ROUTER_PRIVATE_POOL \
    --peer-name=$PEER_PRIVATE_POOL_IF0 \
    --region=$REGION \
    --advertisement-mode=CUSTOM \
    --set-advertisement-ranges=$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX

gcloud compute routers update-bgp-peer $ROUTER_PRIVATE_POOL \
    --peer-name=$PEER_PRIVATE_POOL_IF1 \
    --region=$REGION \
    --advertisement-mode=CUSTOM \
    --set-advertisement-ranges=$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX

gcloud compute routers update-bgp-peer $ROUTER_GKE \
    --peer-name=$PEER_GKE_IF0 \
    --region=$REGION \
    --advertisement-mode=CUSTOM \
    --set-advertisement-ranges=$CLUSTER_CONTROL_PLANE_CIDR

gcloud compute routers update-bgp-peer $ROUTER_GKE \
    --peer-name=$PEER_GKE_IF1 \
    --region=$REGION \
    --advertisement-mode=CUSTOM \
    --set-advertisement-ranges=$CLUSTER_CONTROL_PLANE_CIDR

# Authorize Cloud Build VPC network to GKE master
gcloud container clusters update $CLUSTER \
    --enable-master-authorized-networks \
    --zone=$ZONE \
    --master-authorized-networks=$PRIVATE_POOL_NETWORK/$PRIVATE_POOL_PREFIX

# Create the 2 Source Repositories
gcloud source repos create $APP_REPO
gcloud source repos create $ENV_REPO

# Grant the Cloud Build service account access to the cluster
gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
    --member=serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com \
    --role=roles/container.developer

# Grant Cloud Build SA the Source Repo Writer IAM role to push to repo
cat >/tmp/$ENV_REPO-policy.yaml <<EOF
bindings:
- members:
  - serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com
  role: roles/source.writer
EOF

gcloud source repos set-iam-policy \
    $ENV_REPO /tmp/$ENV_REPO-policy.yaml


# Prepare local app repo
cd app
git init
git add . 
git commit -m "App code first commit"
git remote add google \
    "https://source.developers.google.com/p/${PROJECT_ID}/r/${APP_REPO}"
git config credential.helper gcloud.sh
git push --set-upstream google master
cd ..

# Initialize the env repository
cd env
git init
git checkout -b production
git add . 
git commit -m "Env code first commit"
git remote add google \
    "https://source.developers.google.com/p/${PROJECT_ID}/r/${ENV_REPO}"
git config credential.helper gcloud.sh
git push google production
git checkout -b test
git push --set-upstream google test
cd ..


# Create Cloud Build Trigger to Push image to GCR after a Source Repository push
gcloud builds triggers create cloud-source-repositories \
    --name=$APP_TRIGGER \
    --repo=$APP_REPO \
    --branch-pattern="^master$" \
    --build-config="cloudbuild.yaml" \
    --substitutions _PROJECT_ID=$PROJECT_ID,_APP_IMAGE=$APP_IMAGE,_ENV_REPO=$ENV_REPO,_ENV_NAME=test

# Create Cloud Build Trigger for the Continuous Deployment pipeline
gcloud builds triggers create cloud-source-repositories \
    --name=$ENV_TRIGGER \
    --repo=$ENV_REPO \
    --branch-pattern="^test$" \
    --build-config="cloudbuild.yaml" \
    --substitutions _ZONE=$ZONE,_CLUSTER=$CLUSTER,_REGION=$REGION,_WORKERPOOL_ID=$WORKER_POOL