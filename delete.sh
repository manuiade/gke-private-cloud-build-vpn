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


# Clear all resources

cd app
rm -rf .git
cd ..
cd env
rm -rf .git
cd ..

gcloud beta builds triggers delete $APP_TRIGGER --quiet
gcloud beta builds triggers delete $ENV_TRIGGER --quiet

gcloud source repos delete $APP_REPO --quiet
gcloud source repos delete $ENV_REPO --quiet

gcloud container clusters delete $CLUSTER --zone $ZONE --quiet

gcloud compute vpn-tunnels delete $TUNNEL_PRIVATE_POOL_IF0 --quiet
gcloud compute vpn-tunnels delete $TUNNEL_PRIVATE_POOL_IF1 --quiet
gcloud compute vpn-tunnels delete $TUNNEL_GKE_IF0 --quiet
gcloud compute vpn-tunnels delete $TUNNEL_GKE_IF1 --quiet
gcloud compute routers nats delete $NAT_GKE --quiet --router $ROUTER_GKE
gcloud compute routers delete $ROUTER_PRIVATE_POOL --quiet
gcloud compute routers delete $ROUTER_GKE --quiet
gcloud compute vpn-gateways delete $GW_PRIVATE_POOL --quiet
gcloud compute vpn-gateways delete $GW_GKE --quiet

gcloud builds worker-pools delete $WORKER_POOL --region=$REGION --quiet

gcloud compute networks subnets delete $VPC_GKE_SUBNETWORK --region $REGION --quiet
gcloud services vpc-peerings delete --network=$VPC_PRIVATE_POOL --quiet
gcloud compute addresses delete $VPC_PEERING_RANGE --global --quiet
gcloud compute networks delete $VPC_PRIVATE_POOL --quiet
gcloud compute networks delete $VPC_GKE --quiet
