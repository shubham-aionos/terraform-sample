#!/bin/bash

set -e

EXPECTED_REGION="ap-south-1"
EXPECTED_ACCOUNT="812114845397"

check_aws() {
    echo "=== Checking AWS credentials ==="

    CURRENT_ACCOUNT=$(aws sts get-caller-identity \
        --query Account \
        --output text)

    CURRENT_REGION=$(aws configure get region 2>/dev/null || true)

    if [ "$CURRENT_ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
        echo "ERROR: Wrong AWS account!"
        echo "Expected: $EXPECTED_ACCOUNT"
        echo "Found:    $CURRENT_ACCOUNT"
        exit 1
    fi

    if [ "$CURRENT_REGION" != "$EXPECTED_REGION" ]; then
        echo "ERROR: Wrong AWS region!"
        echo "Expected: $EXPECTED_REGION"
        echo "Found:    $CURRENT_REGION"
        exit 1
    fi

    echo "AWS account: $CURRENT_ACCOUNT"
    echo "AWS region:  $CURRENT_REGION"
    echo "AWS safety check: PASSED"
}

case "$1" in

  up)
    check_aws

    echo "=== Formatting Terraform ==="
    cd terraform
    terraform fmt

    echo "=== Validating Terraform ==="
    terraform validate

    echo "=== Creating Terraform Plan ==="
    terraform plan -out=tfplan

    echo
    echo "========================================"
    echo "Review the plan above."
    echo "========================================"
    echo

    read -p "Apply this plan? Type YES to continue: " confirmation

    if [ "$confirmation" = "YES" ]; then
        terraform apply tfplan
    else
        echo "Apply cancelled."
    fi
    ;;

  down)
    check_aws

    cd terraform

    echo "=== Creating destroy plan ==="
    terraform plan -destroy -out=destroy.tfplan

    echo
    echo "========================================"
    echo "WARNING: The resources above will be DESTROYED."
    echo "========================================"
    echo

    read -p "Destroy everything? Type DESTROY to continue: " confirmation

    if [ "$confirmation" = "DESTROY" ]; then
        terraform apply destroy.tfplan
    else
        echo "Destroy cancelled."
    fi
    ;;

  plan)
    check_aws

    cd terraform
    terraform fmt
    terraform validate
    terraform plan
    ;;

  *)
    echo "Usage:"
    echo "  ./lab.sh up       Deploy infrastructure"
    echo "  ./lab.sh plan     Preview changes"
    echo "  ./lab.sh down     Destroy infrastructure"
    ;;

esac
