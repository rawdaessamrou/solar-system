# Solar System — DevOps CI/CD Project

A full end-to-end DevOps project that containerizes and deploys a Node.js Solar System web app to AWS EKS using Docker, Terraform, Kubernetes, and GitHub Actions. The goal of this project is to simulate a real-world DevOps workflow — from writing code to having it automatically built, tested, and deployed to a production-like cloud environment with zero manual intervention.

---

## What This Project Does

This project takes a simple Node.js web application that displays information about the Solar System and its planets, and wraps it in a complete DevOps lifecycle:

1. **Clones** the Solar System app from a GitLab repository as the source code base.
2. **Dockerizes** the app by writing a Dockerfile that packages the Node.js app and its dependencies into a portable container image.
3. **Pushes the image** to AWS Elastic Container Registry (ECR), a private Docker registry on AWS, so that Kubernetes can pull it securely.
4. **Provisions cloud infrastructure** from scratch using Terraform — including a Virtual Private Cloud (VPC), public and private subnets, a NAT Gateway for outbound traffic, and a fully managed EKS (Elastic Kubernetes Service) cluster with EC2 worker nodes.
5. **Deploys the app** to the Kubernetes cluster using manifest files that define how the app should run and how it should be exposed to the internet via a LoadBalancer.
6. **Automates everything** using a GitHub Actions CI/CD pipeline, so that every time code is pushed to the main branch, the entire build and deployment process runs automatically without any manual steps.

---

## Architecture Overview

```
Developer (git push)
        │
        ▼
  GitHub Actions
  ┌─────────────────────────────────┐
  │  1. Checkout code               │
  │  2. Authenticate with AWS       │
  │  3. Build Docker image          │
  │  4. Push image to ECR           │
  │  5. Connect kubectl to EKS      │
  │  6. Apply Kubernetes manifests  │
  │  7. Wait for pod to be healthy  │
  │  8. Print public app URL        │
  └─────────────────────────────────┘
        │
        ▼
   AWS Cloud (us-east-1)
  ┌─────────────────────────────────┐
  │  VPC                            │
  │  ├── Public Subnets             │
  │  │    ├── NAT Gateway           │
  │  │    └── LoadBalancer (port 80)│
  │  └── Private Subnets            │
  │       └── EKS Worker Node       │
  │            └── Pod              │
  │                 └── Node.js App │
  └─────────────────────────────────┘
        │
        ▼
   User opens EXTERNAL-IP in browser
```

---

## Tools & Technologies

| Tool | Purpose |
|------|---------|
| **Node.js** | The application runtime. The Solar System app is a simple Express.js server that connects to MongoDB and serves planet data through a web interface. |
| **MongoDB Atlas** | A cloud-hosted MongoDB database that stores the Solar System planet data. The app connects to it using a connection string passed as an environment variable. |
| **Docker** | Used to containerize the Node.js app into a portable image. The Dockerfile installs dependencies and defines how the app starts inside a container. |
| **AWS ECR** | Amazon's private container registry where Docker images are stored and versioned. Each image is tagged with the Git commit SHA so deployments are always traceable. |
| **Terraform** | Infrastructure-as-Code tool used to define and provision all AWS resources — VPC, subnets, NAT Gateway, IAM roles, and the EKS cluster — in a reproducible and automated way. |
| **AWS EKS** | Amazon's managed Kubernetes service. It runs the Kubernetes control plane so you only need to manage the worker nodes and your app deployments. |
| **Kubernetes** | The container orchestration platform that manages deployment, scaling, and networking of the app inside the EKS cluster. |
| **GitHub Actions** | The CI/CD platform that automates the build and deploy workflow. It is triggered on every push to the main branch and runs jobs to build the image and deploy to EKS. |
| **AWS S3** | Used as a remote backend to store the Terraform state file, allowing infrastructure state to be shared and persisted across machines. |

---

## Prerequisites

Before running this project, make sure the following tools are installed and configured on your machine:

- **Git** — to clone the repo and push changes that trigger the pipeline
- **Docker** — to build and test the container image locally
- **AWS CLI** — to authenticate with AWS and interact with EKS and ECR
- **Terraform** — to provision and destroy the cloud infrastructure
- **kubectl** — to interact with the Kubernetes cluster after it's created
- An **AWS account** with an IAM user that has AdministratorAccess permissions
- A **GitHub account** with a repository created for this project

---

## Project Structure

```
solar-system/
├── .github/
│   └── workflows/
│       └── cicd.yaml        # Defines the full CI/CD pipeline with two jobs:
│                            # build (Docker + ECR) and deploy (kubectl to EKS)
├── k8s/
│   ├── deployment.yaml      # Tells Kubernetes how to run the app — which image
│   │                        # to use, how many replicas, env variables, and
│   │                        # the deployment strategy (Recreate for small nodes)
│   └── service.yaml         # Creates an AWS LoadBalancer that exposes the app
│                            # on port 80 and forwards traffic to the container
│                            # on port 3000
├── terraform/
│   ├── main.tf              # The core infrastructure file — defines the VPC
│   │                        # module (subnets, NAT gateway) and the EKS module
│   │                        # (cluster, node group, IAM roles)
│   ├── variables.tf         # Declares input variables like AWS region and
│   │                        # cluster name so the config is reusable
│   ├── outputs.tf           # Prints useful info after apply — cluster name,
│   │                        # endpoint, and region
│   ├── versions.tf          # Pins the AWS provider version to avoid breaking
│   │                        # changes from provider upgrades
│   └── backend.tf           # Configures S3 as the remote backend so Terraform
│                            # state is stored safely in the cloud
└── Dockerfile               # Multi-step build: installs Node dependencies
                             # and defines the container startup command
```

---

## How the CI/CD Pipeline Works

The pipeline lives in `.github/workflows/cicd.yaml` and is triggered automatically on every `git push` to the `main` branch. It is split into two sequential jobs:

**Job 1 — Build & Push**

This job runs on a fresh Ubuntu runner. It checks out the latest code, authenticates with AWS using stored GitHub Secrets, logs into ECR, then builds a Docker image from the Dockerfile. The image is tagged with the Git commit SHA — this ensures every deployment is uniquely identified and traceable back to a specific code change. The image is then pushed to the ECR repository.

**Job 2 — Deploy**

This job only runs after Job 1 succeeds. It connects `kubectl` to the EKS cluster by updating the kubeconfig using the AWS CLI. It then deletes the existing deployment to free up resources on the small t3.micro node, applies the updated `deployment.yaml` and `service.yaml` manifests, and waits for the new pod to reach a healthy `Running` state. Finally, it prints the LoadBalancer's public URL so you can immediately verify the deployment in a browser.

---

## Key Configuration Decisions

**Why t3.micro?**
The project is designed to run within the AWS Free Tier. The t3.micro instance type is used for the EKS worker node, which has limited CPU, memory, and a maximum of 4 pods. This means the deployment is kept at 1 replica and system pods (CoreDNS, kube-proxy) are carefully managed to avoid hitting pod limits.

**Why Recreate strategy?**
Kubernetes normally uses a rolling update strategy which spins up a new pod before terminating the old one. On a t3.micro node with very limited resources, this causes the new pod to stay stuck in `Pending` because there aren't enough resources to run both pods at the same time. The `Recreate` strategy solves this by terminating the old pod first, then creating the new one.

**Why S3 backend for Terraform?**
Storing the Terraform state file locally means it could be lost or become inconsistent. Using an S3 bucket as a remote backend ensures the state is safe, versioned, and accessible from any machine — including the GitHub Actions runner.

**Why tag images with commit SHA?**
Using `latest` as the image tag makes it impossible to know which version of the code is running. Tagging with the Git commit SHA makes every deployment fully traceable — you can always look at the running pod's image tag and know exactly which commit it came from.

---

## Common Issues & How They Were Solved

| Problem | Root Cause | Solution Applied |
|---------|-----------|-----------------|
| `Too many pods` | t3.micro supports only 4 pods max | Kept app at 1 replica, scaled CoreDNS to 1 |
| `Failed to assign IP` | t3.micro runs out of ENI IP slots | Enabled prefix delegation on the aws-node daemonset |
| `CrashLoopBackOff` | App crashed because MONGO_URI was undefined | Added MongoDB env vars to deployment.yaml |
| `Pending termination` in pipeline | Rolling update needs 2 pods but node only fits 1 | Switched deployment strategy to `Recreate` |
| `AccessDenied` on Terraform | IAM user missing required permissions | Attached AdministratorAccess policy to the IAM user |
| `Unsupported Kubernetes version` | AWS dropped support for older k8s versions | Upgraded cluster version to 1.31 |
| `DNS_PROBE_FINISHED_NXDOMAIN` | LoadBalancer DNS takes time to propagate | Waited 2-3 minutes and retried with correct URL |

---

## Estimated AWS Costs

All resources together cost roughly **$0.18/hour** when running. Here is the breakdown:

| Resource | What it does | ~Monthly Cost |
|----------|-------------|--------------|
| EKS Cluster | Runs the Kubernetes control plane | $72 |
| EC2 t3.micro | Worker node that runs the app pod | $7 |
| NAT Gateway | Allows private subnet to reach the internet | $33 |
| LoadBalancer | Exposes the app publicly on port 80 | $18 |
| S3 Bucket | Stores Terraform state file | ~$0 |
| **Total** | | **~$130/month** |

> ⚠️ The NAT Gateway is the sneakiest cost — it charges just for existing, even when no traffic flows through it. Always run `terraform destroy` when you are done working to bring costs to zero.

---

## Cleanup

To stop all running AWS resources and avoid ongoing charges, delete the Kubernetes service first (which removes the LoadBalancer), then destroy all infrastructure with Terraform. After running these two steps, all resources — EKS cluster, EC2 nodes, NAT Gateway, VPC, and subnets — will be fully deleted and billing will stop.

```bash
kubectl delete -f k8s/
cd terraform/ && terraform destroy -auto-approve
```
