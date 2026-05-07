# Secure Cloud Tasks

Secure Cloud Tasks is a production-style, cloud-native CRUD app deployed on AWS with Terraform.
It demonstrates practical cloud engineering: private networking, least-privilege IAM, hardened bootstrapping, and end-to-end app delivery.

## Live Demo

- App: [http://secure2026050217342274690000000f-610663488.us-east-2.elb.amazonaws.com](http://secure2026050217342274690000000f-610663488.us-east-2.elb.amazonaws.com)
- Health check: [http://secure2026050217342274690000000f-610663488.us-east-2.elb.amazonaws.com/health](http://secure2026050217342274690000000f-610663488.us-east-2.elb.amazonaws.com/health)

## Why I Built This (First Principles)

I wanted a project that proves I can do more than run commands: I can design and operate a secure service from first principles.

- Real systems fail at boundaries (networking, identity, dependency bootstrap), so this project intentionally includes those concerns.
- Instead of a single VM demo, I built a 3-tier architecture with private compute and managed database.
- Everything is codified in Terraform so infrastructure is reviewable, reproducible, and auditable.

## Architecture Overview

High-level flow:

1. User hits internet-facing ALB.
2. ALB forwards to Flask/Gunicorn on private EC2 (port 5000).
3. App reads/writes tasks in private RDS PostgreSQL.

Core AWS components:

- **VPC** with segmented subnets:
  - Public subnets: ALB + NAT
  - Private app subnets: EC2 app tier
  - Private data subnets: RDS
- **ALB** with HTTP health checks to `/health`
- **EC2 (Amazon Linux 2023)** running Flask + Gunicorn as a `systemd` service
- **RDS PostgreSQL** in private data subnets
- **Secrets Manager** for DB credentials
- **IAM instance role** for scoped S3/Secrets/SSM access
- **VPC Endpoints** for private AWS API access where possible
- **Terraform modules** for composable infrastructure (`vpc`, `networking`, `security`, `iam`, `database`, `alb`, `compute`, etc.)

## Security Decisions

- **Private-by-default compute/data**: EC2 and RDS are not public.
- **Least-privilege IAM**:
  - EC2 role can read only required S3 objects and DB secret.
  - No long-lived static credentials on instances.
- **Network segmentation + defense in depth**:
  - Security Groups enforce service-level access.
  - NACLs enforce subnet-level policy with explicit return-path handling.
- **Secrets handling**:
  - DB connection details come from Secrets Manager at bootstrap.
  - Runtime env is written via controlled system config file permissions.
- **Operational hardening**:
  - `systemd` service with restart policy and health probe.
  - Deterministic app packaging and wheel-based Python dependency install for restricted networks.

## Application Features

- REST API for tasks:
  - `GET /health`
  - `GET /tasks`
  - `POST /tasks`
  - `PUT /tasks/<id>`
  - `DELETE /tasks/<id>`
- Lightweight frontend (Tailwind + vanilla JS):
  - Create task form
  - Task list
  - Toggle complete/incomplete
  - Delete task
  - Auto-refresh after each action

## Project Structure

```text
secure-cloud-tasks/
  app/                          # Flask app + frontend template + wheels
    app.py
    requirements.txt
    templates/index.html
    wheels/
  terraform/                    # Root Terraform + modules
    main.tf
    variables.tf
    outputs.tf
    modules/
      vpc/
      networking/
      security/
      iam/
      database/
      alb/
      compute/
      app_bundle/
      vpc_endpoints/
```

## Local IaC Workflow

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Interview Talking Points

- Diagnosed and fixed real ALB/target health failures across layers (NACL return paths, bootstrap dependencies, runtime startup).
- Designed secure private-tier architecture using least privilege and network segmentation.
- Built robust EC2 bootstrap process (`cloud-init` + `systemd`) with retries, service checks, and deterministic package handling.
- Implemented full-stack functionality (backend API + lightweight frontend) and validated end-to-end behavior in production-like AWS infra.
- Managed infrastructure lifecycle safely with Terraform modules and targeted applies during incident-like debugging.

## Resume Bullet Ideas

- Built and operated a secure 3-tier AWS task application (ALB, private EC2, private RDS) using modular Terraform.
- Implemented least-privilege IAM, subnet segmentation, NACL/SG controls, and Secrets Manager integration for secure service operation.
- Troubleshot and resolved live infrastructure/app failures (health checks, bootstrap networking, dependency installation) to restore service health.
- Delivered full CRUD web experience with Flask/Gunicorn + vanilla JS frontend and production-style monitoring endpoints.