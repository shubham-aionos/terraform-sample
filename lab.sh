#!/bin/bash

set -Eeuo pipefail

# ============================================================
# AWS THREE-TIER LAB
# Safe Terraform deployment / destruction helper
# ============================================================

EXPECTED_REGION="ap-south-1"
EXPECTED_ACCOUNT="812114845397"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/terraform"

PLAN_FILE="$TERRAFORM_DIR/tfplan"
DESTROY_PLAN_FILE="$TERRAFORM_DIR/destroy.tfplan"

MAX_WAIT_SECONDS=600
HEALTH_CHECK_INTERVAL=10

ASG_NAME="three-tier-app-asg"
ALB_NAME="three-tier-app-alb"
TARGET_GROUP_NAME="three-tier-app-tg"
LAUNCH_TEMPLATE_NAME="three-tier-app-template"

EXPECTED_APP_TEXT="Hello from the AWS Three-Tier Architecture"


# ============================================================
# Logging / error handling
# ============================================================

log() {
    echo
    echo "[$(date '+%H:%M:%S')] $*"
}

success() {
    echo
    echo "✓ $*"
}

warn() {
    echo
    echo "WARNING: $*" >&2
}

error() {
    echo
    echo "ERROR: $*" >&2
}

die() {
    error "$*"
    exit 1
}

cleanup() {
    rm -f "$PLAN_FILE"
    rm -f "$DESTROY_PLAN_FILE"
}

on_error() {
    local exit_code=$?

    error "Command failed."
    error "Line: ${BASH_LINENO[0]}"
    error "Command: ${BASH_COMMAND}"

    exit "$exit_code"
}

trap cleanup EXIT
trap on_error ERR


# ============================================================
# Basic checks
# ============================================================

require_command() {
    command -v "$1" >/dev/null 2>&1 || \
        die "Required command not found: $1"
}

check_tools() {
    log "Checking required tools"

    require_command aws
    require_command terraform
    require_command bash
    require_command curl
    require_command awk
    require_command grep
    require_command wc

    success "Required tools are installed"
}

check_project() {
    log "Checking project structure"

    [ -d "$TERRAFORM_DIR" ] || \
        die "Terraform directory not found: $TERRAFORM_DIR"

    [ -f "$TERRAFORM_DIR/main.tf" ] || \
        die "main.tf not found"

    [ -f "$TERRAFORM_DIR/user_data.sh" ] || \
        die "user_data.sh not found"

    success "Project structure looks correct"
}


# ============================================================
# AWS safety checks
# ============================================================

check_aws() {
    log "Checking AWS credentials and account"

    local identity

    identity="$(aws sts get-caller-identity 2>/dev/null)" || {
        error "AWS credentials are missing or expired."
        echo
        echo "Run:"
        echo "  aws login"
        echo
        exit 1
    }

    local current_account

    current_account="$(
        aws sts get-caller-identity \
            --query Account \
            --output text
    )"

    local current_region

    current_region="$(aws configure get region 2>/dev/null || true)"

    [ -n "$current_account" ] || \
        die "Could not determine AWS account"

    [ -n "$current_region" ] || \
        die "AWS CLI region is not configured"

    if [ "$current_account" != "$EXPECTED_ACCOUNT" ]; then
        error "WRONG AWS ACCOUNT!"
        error "Expected: $EXPECTED_ACCOUNT"
        error "Found:    $current_account"
        exit 1
    fi

    if [ "$current_region" != "$EXPECTED_REGION" ]; then
        error "WRONG AWS REGION!"
        error "Expected: $EXPECTED_REGION"
        error "Found:    $current_region"
        exit 1
    fi

    echo "AWS account: $current_account"
    echo "AWS region:  $current_region"

    success "AWS safety check PASSED"
}


# ============================================================
# Local validation
# ============================================================

validate_user_data() {
    log "Validating user-data shell script"

    bash -n "$TERRAFORM_DIR/user_data.sh"

    success "user_data.sh syntax PASSED"
}

validate_terraform() {
    log "Formatting Terraform"

    terraform -chdir="$TERRAFORM_DIR" fmt -check=false

    log "Initializing Terraform"

    terraform -chdir="$TERRAFORM_DIR" init -input=false

    log "Validating Terraform"

    terraform -chdir="$TERRAFORM_DIR" validate

    success "Terraform validation PASSED"
}


# ============================================================
# Terraform plan
# ============================================================

create_plan() {
    log "Creating Terraform plan"

    rm -f "$PLAN_FILE"

    terraform -chdir="$TERRAFORM_DIR" plan \
        -input=false \
        -out="$PLAN_FILE"

    [ -f "$PLAN_FILE" ] || \
        die "Terraform plan file was not created"

    success "Terraform plan created"
}

create_destroy_plan() {
    log "Creating Terraform destroy plan"

    rm -f "$DESTROY_PLAN_FILE"

    terraform -chdir="$TERRAFORM_DIR" plan \
        -destroy \
        -input=false \
        -out="$DESTROY_PLAN_FILE"

    [ -f "$DESTROY_PLAN_FILE" ] || \
        die "Destroy plan file was not created"

    success "Terraform destroy plan created"
}


# ============================================================
# Terraform apply
# ============================================================

apply_plan() {
    log "Applying the reviewed Terraform plan"

    terraform -chdir="$TERRAFORM_DIR" apply \
        -input=false \
        "$PLAN_FILE"

    success "Terraform apply completed"
}


# ============================================================
# AWS resource discovery
# ============================================================

get_instance_ids() {
    aws autoscaling describe-auto-scaling-instances \
        --region "$EXPECTED_REGION" \
        --query \
        "AutoScalingInstances[?AutoScalingGroupName==\`$ASG_NAME\` && LifecycleState==\`InService\`].InstanceId" \
        --output text
}

get_target_group_arn() {
    aws elbv2 describe-target-groups \
        --region "$EXPECTED_REGION" \
        --names "$TARGET_GROUP_NAME" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text
}

get_alb_dns() {
    aws elbv2 describe-load-balancers \
        --region "$EXPECTED_REGION" \
        --names "$ALB_NAME" \
        --query 'LoadBalancers[0].DNSName' \
        --output text
}

get_latest_launch_template_version() {
    aws ec2 describe-launch-template-versions \
        --launch-template-name "$LAUNCH_TEMPLATE_NAME" \
        --versions '$Latest' \
        --region "$EXPECTED_REGION" \
        --query 'LaunchTemplateVersions[0].VersionNumber' \
        --output text
}


# ============================================================
# Wait for ASG instances
# ============================================================

wait_for_instances() {
    log "Waiting for ASG instances"

    local elapsed=0
    local instances=""

    while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do

        instances="$(get_instance_ids || true)"

        if [ -n "$instances" ] && [ "$instances" != "None" ]; then

            local count

            count="$(echo "$instances" | wc -w)"

            if [ "$count" -ge 2 ]; then
                success "ASG has $count InService instances"
                echo "$instances"
                return 0
            fi
        fi

        sleep "$HEALTH_CHECK_INTERVAL"

        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        echo "Waiting... ${elapsed}s / ${MAX_WAIT_SECONDS}s"
    done

    die "Timed out waiting for ASG instances"
}


# ============================================================
# Launch Template version validation
# ============================================================

check_launch_template_versions() {
    log "Checking Launch Template versions"

    local latest_version

    latest_version="$(get_latest_launch_template_version)"

    [ -n "$latest_version" ] && \
        [ "$latest_version" != "None" ] || \
        die "Could not determine latest Launch Template version"

    echo "Latest Launch Template version: $latest_version"

    local instances

    instances="$(get_instance_ids || true)"

    [ -n "$instances" ] && \
        [ "$instances" != "None" ] || \
        die "No InService instances found"

    local stale_instances=""

    for instance_id in $instances; do

        local instance_version

        instance_version="$(
            aws autoscaling describe-auto-scaling-instances \
                --region "$EXPECTED_REGION" \
                --query \
                "AutoScalingInstances[?InstanceId==\`$instance_id\`].LaunchTemplate.Version" \
                --output text \
                2>/dev/null || true
        )"
        echo "Instance $instance_id → Launch Template version $instance_version"

        if [ "$instance_version" != "$latest_version" ]; then
            stale_instances="$stale_instances $instance_id"
        fi
    done

    if [ -z "$stale_instances" ]; then
        success "All instances use the latest Launch Template"
        return 0
    fi

    warn "Some instances use an older Launch Template version."

    echo
    echo "Stale instances:"
    echo "$stale_instances"

    log "Starting Auto Scaling instance refresh"

    local refresh_id

    refresh_id="$(
        aws autoscaling start-instance-refresh \
            --auto-scaling-group-name "$ASG_NAME" \
            --region "$EXPECTED_REGION" \
            --preferences MinHealthyPercentage=50 \
            --query 'InstanceRefreshId' \
            --output text
    )"

    echo "Instance refresh ID: $refresh_id"

    local elapsed=0

    while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do

        local status

        status="$(
            aws autoscaling describe-instance-refreshes \
                --auto-scaling-group-name "$ASG_NAME" \
                --instance-refresh-ids "$refresh_id" \
                --region "$EXPECTED_REGION" \
                --query 'InstanceRefreshes[0].Status' \
                --output text
        )"

        echo "Instance refresh status: $status"

        case "$status" in

            Successful)
                success "Instance refresh completed"
                return 0
                ;;

            Failed|Cancelled|RollbackFailed)
                die "Instance refresh ended with status: $status"
                ;;

            RollbackSuccessful)
                die "Instance refresh rolled back successfully, meaning the refresh failed"
                ;;

        esac

        sleep "$HEALTH_CHECK_INTERVAL"

        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done

    die "Timed out waiting for instance refresh"
}


# ============================================================
# SSM validation
# ============================================================

wait_for_ssm() {
    log "Waiting for SSM"

    local elapsed=0

    while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do

        local instances

        instances="$(get_instance_ids || true)"

        if [ -n "$instances" ] && [ "$instances" != "None" ]; then

            local online=0

            for instance_id in $instances; do

                local status

                status="$(
                    aws ssm describe-instance-information \
                        --region "$EXPECTED_REGION" \
                        --filters "Key=InstanceIds,Values=$instance_id" \
                        --query \
                        'InstanceInformationList[0].PingStatus' \
                        --output text \
                        2>/dev/null || true
                )"

                if [ "$status" = "Online" ]; then
                    online=$((online + 1))
                fi
            done

            if [ "$online" -ge 2 ]; then
                success "All expected instances are ONLINE in SSM"
                return 0
            fi
        fi

        sleep "$HEALTH_CHECK_INTERVAL"

        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        echo "SSM waiting... ${elapsed}s / ${MAX_WAIT_SECONDS}s"
    done

    die "Timed out waiting for expected instances in SSM"
}


# ============================================================
# Target group validation
# ============================================================

show_target_health() {
    local tg_arn="$1"

    aws elbv2 describe-target-health \
        --target-group-arn "$tg_arn" \
        --region "$EXPECTED_REGION" \
        --query \
        'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason,TargetHealth.Description]' \
        --output table
}

wait_for_healthy_targets() {
    log "Waiting for ALB target health"

    local tg_arn

    tg_arn="$(get_target_group_arn)"

    [ -n "$tg_arn" ] && \
        [ "$tg_arn" != "None" ] || \
        die "Could not find target group"

    local elapsed=0

    while [ "$elapsed" -lt "$MAX_WAIT_SECONDS" ]; do

        local healthy

        healthy="$(
            aws elbv2 describe-target-health \
                --target-group-arn "$tg_arn" \
                --region "$EXPECTED_REGION" \
                --query \
                'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
                --output text
        )"

        if [ "$healthy" -ge 2 ]; then
            success "All expected ALB targets are HEALTHY"
            return 0
        fi

        echo
        echo "Current target health:"
        show_target_health "$tg_arn"

        sleep "$HEALTH_CHECK_INTERVAL"

        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        echo
        echo "Health check waiting... ${elapsed}s / ${MAX_WAIT_SECONDS}s"
    done

    error "ALB targets did not become healthy."

    echo
    echo "Final target health:"
    show_target_health "$tg_arn"

    echo
    echo "Possible causes:"
    echo "  - Application is not listening on port 8080"
    echo "  - User-data failed"
    echo "  - Application crashed"
    echo "  - Security group blocks ALB -> EC2"
    echo "  - Target health-check path is incorrect"

    return 1
}


# ============================================================
# Application validation
# ============================================================

test_application() {
    log "Testing application through ALB"

    local dns

    dns="$(get_alb_dns)"

    [ -n "$dns" ] && \
        [ "$dns" != "None" ] || \
        die "Could not determine ALB DNS name"

    echo
    echo "ALB:"
    echo "http://$dns"
    echo

    local response

    response="$(
        curl \
            --silent \
            --show-error \
            --location \
            --max-time 15 \
            --write-out $'\nHTTP_STATUS:%{http_code}\n' \
            "http://$dns"
    )" || {
        error "Could not connect to ALB"
        return 1
    }

    echo "$response"

    local status

    status="$(
        echo "$response" |
        awk -F: '/HTTP_STATUS:/ {print $2}'
    )"

    if [ "$status" != "200" ]; then
        error "Application returned HTTP $status"
        return 1
    fi

    if ! echo "$response" | grep -q "$EXPECTED_APP_TEXT"; then
        error "HTTP 200 received, but expected application content was not found"
        return 1
    fi

    success "End-to-end application test PASSED"
}


# ============================================================
# Deployment verification
# ============================================================

verify_deployment() {
    log "========================================"
    log "POST-DEPLOYMENT VERIFICATION"
    log "========================================"

    wait_for_instances

    check_launch_template_versions

    # Refresh may have replaced the instances.
    # Re-check that the ASG has its expected fleet.
    wait_for_instances

    wait_for_ssm

    if ! wait_for_healthy_targets; then

        error "Deployment verification FAILED"

        echo
        echo "Useful diagnostics:"
        echo
        echo "Check ASG:"
        echo "  aws autoscaling describe-auto-scaling-instances --region $EXPECTED_REGION"
        echo
        echo "Check target health:"
        echo "  aws elbv2 describe-target-health --target-group-arn <ARN> --region $EXPECTED_REGION"
        echo
        echo "Check SSM:"
        echo "  aws ssm describe-instance-information --region $EXPECTED_REGION"

        return 1
    fi

    test_application
}


# ============================================================
# UP
# ============================================================

up() {
    echo
    echo "========================================"
    echo "       AWS THREE-TIER LAB - UP"
    echo "========================================"

    check_tools
    check_project
    check_aws

    validate_user_data
    validate_terraform

    create_plan

    echo
    echo "========================================"
    echo "Review the Terraform plan above."
    echo "========================================"
    echo

    read -r -p "Apply this EXACT plan? Type YES to continue: " confirmation

    if [ "$confirmation" != "YES" ]; then
        echo "Apply cancelled."
        exit 0
    fi

    apply_plan

    verify_deployment

    echo
    echo "========================================"
    echo "       DEPLOYMENT SUCCESSFUL"
    echo "========================================"

    local dns

    dns="$(get_alb_dns)"

    echo
    echo "Application:"
    echo "http://$dns"
    echo

    echo "Remember to destroy the lab when finished:"
    echo
    echo "  ./lab.sh down"
    echo
}


# ============================================================
# PLAN
# ============================================================

plan() {
    echo
    echo "========================================"
    echo "       AWS THREE-TIER LAB - PLAN"
    echo "========================================"

    check_tools
    check_project
    check_aws

    validate_user_data
    validate_terraform

    terraform -chdir="$TERRAFORM_DIR" plan
}


# ============================================================
# DOWN
# ============================================================

down() {
    echo
    echo "========================================"
    echo "       AWS THREE-TIER LAB - DOWN"
    echo "========================================"

    check_tools
    check_project
    check_aws

    create_destroy_plan

    echo
    echo "========================================"
    echo "WARNING: EVERYTHING IN THIS TERRAFORM"
    echo "STATE WILL BE DESTROYED."
    echo "========================================"
    echo

    read -r -p "Destroy everything? Type DESTROY to continue: " confirmation

    if [ "$confirmation" != "DESTROY" ]; then
        echo "Destroy cancelled."
        exit 0
    fi

    log "Applying destroy plan"

    terraform -chdir="$TERRAFORM_DIR" apply \
        -input=false \
        "$DESTROY_PLAN_FILE"

    success "Terraform destroy completed"

    echo
    echo "========================================"
    echo "       LAB DESTROYED"
    echo "========================================"
}


# ============================================================
# MAIN
# ============================================================

case "${1:-}" in

    up)
        up
        ;;

    plan)
        plan
        ;;

    down)
        down
        ;;

    *)
        echo
        echo "Usage:"
        echo "  ./lab.sh up       Validate, deploy, and verify"
        echo "  ./lab.sh plan     Validate and preview changes"
        echo "  ./lab.sh down     Safely destroy the lab"
        echo
        exit 1
        ;;

esac
