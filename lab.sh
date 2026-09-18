#!/bin/bash

set -Eeuo pipefail

# ============================================================
# AWS THREE-TIER LAB
# Terraform / CodePipeline bootstrap and teardown helper
#
# Architecture:
#
#   terraform/pipeline
#       CodePipeline
#       CodeBuild
#       Artifact bucket
#       Terraform state bucket
#
#   terraform/app
#       VPC
#       ALB
#       ASG / EC2
#       RDS
#       SSM
#       VPC Flow Logs
#
# Pipeline behavior:
#   Apply -> verify application
#       PASS -> keep infrastructure
#       FAIL -> destroy application infrastructure
#
# IMPORTANT BOOTSTRAP DESIGN:
#   The pipeline stack owns the S3 Terraform state bucket.
#   Therefore `up` MUST bootstrap the pipeline stack BEFORE
#   initializing the application Terraform backend.
# ============================================================

EXPECTED_REGION="ap-south-1"
EXPECTED_ACCOUNT="812114845397"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TERRAFORM_ROOT="$SCRIPT_DIR/terraform"
APP_DIR="$TERRAFORM_ROOT/app"
PIPELINE_DIR="$TERRAFORM_ROOT/pipeline"

MAX_WAIT_SECONDS=600
HEALTH_CHECK_INTERVAL=10

ASG_NAME="three-tier-app-asg"
ALB_NAME="three-tier-app-alb"
TARGET_GROUP_NAME="three-tier-app-tg"
LAUNCH_TEMPLATE_NAME="three-tier-app-template"

EXPECTED_APP_TEXT="Hello from the AWS Three-Tier Architecture"

STATE_BUCKET="three-tier-terraform-state-${EXPECTED_ACCOUNT}"
STATE_KEY="app/terraform.tfstate"


# ============================================================
# Logging
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
    require_command grep
    require_command wc

    success "Required tools are installed"
}


check_project() {
    log "Checking project structure"

    [ -d "$TERRAFORM_ROOT" ] || \
        die "Terraform directory not found: $TERRAFORM_ROOT"

    [ -d "$APP_DIR" ] || \
        die "Application Terraform directory not found: $APP_DIR"

    [ -d "$PIPELINE_DIR" ] || \
        die "Pipeline Terraform directory not found: $PIPELINE_DIR"

    [ -f "$APP_DIR/main.tf" ] || \
        die "Application main.tf not found"

    [ -f "$APP_DIR/user_data.sh" ] || \
        die "Application user_data.sh not found"

    [ -f "$PIPELINE_DIR/codepipeline.tf" ] || \
        die "Pipeline CodePipeline configuration not found"

    success "Project structure looks correct"
}


# ============================================================
# AWS safety checks
# ============================================================

check_aws() {
    log "Checking AWS credentials and account"

    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials are missing or expired."
        echo
        echo "Run:"
        echo "  aws login"
        echo
        exit 1
    fi

    local current_account
    local current_region

    current_account="$(
        aws sts get-caller-identity \
            --query Account \
            --output text
    )"

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
# Application validation
# ============================================================

validate_user_data() {
    log "Validating application user-data"

    bash -n "$APP_DIR/user_data.sh"

    success "user_data.sh syntax PASSED"
}


validate_app_terraform() {
    log "Formatting application Terraform"

    terraform -chdir="$APP_DIR" fmt -check=false

    log "Initializing application Terraform for validation"

    # IMPORTANT:
    # This is validation-only initialization.
    # We deliberately disable the backend so this function does
    # not depend on the pipeline-managed S3 state bucket.
    #
    # -reconfigure also prevents stale local .terraform backend
    # configuration from interfering after a previous deployment
    # or destroy.
    terraform -chdir="$APP_DIR" init \
        -backend=false \
        -input=false \
        -reconfigure

    log "Validating application Terraform"

    terraform -chdir="$APP_DIR" validate

    success "Application Terraform validation PASSED"
}


# ============================================================
# Pipeline Terraform validation
# ============================================================

validate_pipeline_terraform() {
    log "Formatting pipeline Terraform"

    terraform -chdir="$PIPELINE_DIR" fmt -check=false

    log "Initializing pipeline Terraform"

    terraform -chdir="$PIPELINE_DIR" init \
        -input=false

    log "Validating pipeline Terraform"

    terraform -chdir="$PIPELINE_DIR" validate

    success "Pipeline Terraform validation PASSED"
}


# ============================================================
# Pipeline bootstrap
# ============================================================

plan_pipeline() {
    log "Creating CodePipeline infrastructure plan"

    terraform -chdir="$PIPELINE_DIR" plan \
        -input=false
}


apply_pipeline() {
    log "Applying CodePipeline infrastructure"

    terraform -chdir="$PIPELINE_DIR" apply \
        -input=false \
        -auto-approve

    success "CodePipeline infrastructure is deployed"
}


# ============================================================
# State bucket helpers
# ============================================================

state_bucket_exists() {
    aws s3api head-bucket \
        --bucket "$STATE_BUCKET" \
        --region "$EXPECTED_REGION" \
        >/dev/null 2>&1
}


# ============================================================
# Application Terraform backend
# ============================================================

init_app_backend() {
    log "Initializing application Terraform with S3 state"

    if ! state_bucket_exists; then
        error "Terraform state bucket does not exist:"
        error "  $STATE_BUCKET"
        return 1
    fi

    terraform -chdir="$APP_DIR" init \
        -input=false \
        -reconfigure \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$STATE_KEY" \
        -backend-config="region=$EXPECTED_REGION" \
        -backend-config="encrypt=true" \
        -backend-config="use_lockfile=true"

    success "Application Terraform backend initialized"
}


# ============================================================
# Application state detection
# ============================================================

app_state_exists() {
    aws s3api head-object \
        --bucket "$STATE_BUCKET" \
        --key "$STATE_KEY" \
        --region "$EXPECTED_REGION" \
        >/dev/null 2>&1
}


# ============================================================
# Application discovery
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
# Wait for ASG
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

    return 1
}


# ============================================================
# Launch Template validation
# ============================================================

check_launch_template_versions() {
    log "Checking Launch Template versions"

    local latest_version

    latest_version="$(get_latest_launch_template_version || true)"

    if [ -z "$latest_version" ] || [ "$latest_version" = "None" ]; then
        error "Could not determine latest Launch Template version"
        return 1
    fi

    echo "Latest Launch Template version: $latest_version"

    local instances

    instances="$(get_instance_ids || true)"

    if [ -z "$instances" ] || [ "$instances" = "None" ]; then
        error "No InService instances found"
        return 1
    fi

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

            Failed|Cancelled|RollbackFailed|RollbackSuccessful)
                error "Instance refresh ended with status: $status"
                return 1
                ;;
        esac

        sleep "$HEALTH_CHECK_INTERVAL"

        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done

    error "Timed out waiting for instance refresh"
    return 1
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

    error "Timed out waiting for expected instances in SSM"
    return 1
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

    tg_arn="$(get_target_group_arn || true)"

    if [ -z "$tg_arn" ] || [ "$tg_arn" = "None" ]; then
        error "Could not find target group"
        return 1
    fi

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
        show_target_health "$tg_arn" || true

        sleep "$HEALTH_CHECK_INTERVAL"

        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))

        echo
        echo "Health check waiting... ${elapsed}s / ${MAX_WAIT_SECONDS}s"
    done

    error "ALB targets did not become healthy."

    echo
    echo "Final target health:"
    show_target_health "$tg_arn" || true

    return 1
}


# ============================================================
# Application test
# ============================================================

test_application() {
    log "Testing application through ALB"

    local dns

    dns="$(get_alb_dns || true)"

    if [ -z "$dns" ] || [ "$dns" = "None" ]; then
        error "Could not determine ALB DNS name"
        return 1
    fi

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
        error "Expected application content was not found"
        return 1
    fi

    success "End-to-end application test PASSED"
}


# ============================================================
# Application verification
# ============================================================

verify_deployment() {
    log "========================================"
    log "POST-DEPLOYMENT VERIFICATION"
    log "========================================"

    wait_for_instances || return 1

    check_launch_template_versions || return 1

    wait_for_instances || return 1

    wait_for_ssm || return 1

    wait_for_healthy_targets || return 1

    test_application
}


# ============================================================
# Destroy application stack
# ============================================================

destroy_app() {
    log "Destroying application infrastructure"

    if ! state_bucket_exists; then
        warn "Terraform state bucket does not exist."
        warn "There is no application state to destroy."
        return 0
    fi

    init_app_backend || return 1

    if ! app_state_exists; then
        success "No application Terraform state exists. Nothing to destroy."
        return 0
    fi

    terraform -chdir="$APP_DIR" destroy \
        -input=false \
        -auto-approve

    success "Application infrastructure destroyed"
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

    # ========================================================
    # IMPORTANT BOOTSTRAP ORDER
    #
    # The pipeline Terraform stack owns the S3 state bucket.
    # Therefore DO NOT initialize the application backend
    # before the pipeline stack has been created.
    # ========================================================

    log "Validating pipeline Terraform"

    validate_pipeline_terraform

    echo
    echo "========================================"
    echo "This command bootstraps the persistent"
    echo "CodePipeline / CodeBuild control plane."
    echo
    echo "The application infrastructure is NOT"
    echo "created directly by this command."
    echo
    echo "After bootstrap:"
    echo
    echo "  GitHub push"
    echo "      ↓"
    echo "  CodePipeline"
    echo "      ↓"
    echo "  Validate + Checkov"
    echo "      ↓"
    echo "  Terraform Apply"
    echo "      ↓"
    echo "  Application verification"
    echo "      ↓"
    echo "  PASS → KEEP"
    echo "  FAIL → DESTROY APP"
    echo "========================================"
    echo

    plan_pipeline

    echo
    read -r -p "Create/update the pipeline control plane? Type YES to continue: " confirmation

    if [ "$confirmation" != "YES" ]; then
        echo "Bootstrap cancelled."
        exit 0
    fi

    apply_pipeline

    # ========================================================
    # The pipeline stack has now created the S3 state bucket.
    # Application Terraform can safely be initialized now.
    # ========================================================

    validate_app_terraform

    if ! state_bucket_exists; then
        die "Pipeline was applied, but Terraform state bucket was not created: $STATE_BUCKET"
    fi

    success "Terraform state bucket is available"

    echo
    echo "========================================"
    echo "       PIPELINE BOOTSTRAPPED"
    echo "========================================"
    echo
    echo "Next:"
    echo "  Push to GitHub to trigger the pipeline."
    echo
    echo "The pipeline will:"
    echo "  1. Validate Terraform"
    echo "  2. Run Checkov"
    echo "  3. Apply application infrastructure"
    echo "  4. Verify the application"
    echo "  5. KEEP infrastructure if verification passes"
    echo "  6. DESTROY application infrastructure if verification fails"
    echo
    echo "To tear down the lab:"
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
    validate_app_terraform
    validate_pipeline_terraform

    echo
    echo "========== PIPELINE PLAN =========="
    terraform -chdir="$PIPELINE_DIR" plan -input=false

    echo
    echo "========== APPLICATION PLAN =========="
    echo "The application uses an S3 backend created"
    echo "by the pipeline stack."

    if state_bucket_exists; then
        init_app_backend

        terraform -chdir="$APP_DIR" plan -input=false
    else
        warn "State bucket does not exist yet."
        warn "Run ./lab.sh up first to bootstrap the pipeline."
    fi
}


# ============================================================
# DOWN
# ============================================================

down() {
    log "Starting disposable lab teardown"

    echo

    # Application infrastructure is always destroyed first.
    destroy_app

    echo

    log "Destroying pipeline control plane while preserving GitHub connection"

    # Keep the Terraform-managed GitHub CodeConnections connection.
    # Everything else in the pipeline state is disposable.

    local targets=()
    local resource

    while IFS= read -r resource; do
        if [ "$resource" = "aws_codestarconnections_connection.github" ]; then
            log "Preserving GitHub connection: $resource"
            continue
        fi

        targets+=("-target=$resource")
    done < <(
        terraform -chdir="$PIPELINE_DIR" state list
    )

    if [ "${#targets[@]}" -gt 0 ]; then
        local terraform_args=(
            -input=false
            -auto-approve
        )

        terraform_args+=("${targets[@]}")

        terraform -chdir="$PIPELINE_DIR" destroy "${terraform_args[@]}"
    else
        log "No disposable pipeline resources found"
    fi

    echo

    success "Disposable lab destroyed"
    success "GitHub connection preserved"

    echo
    echo "Preserved connection:"
    echo "  aws_codestarconnections_connection.github"
    echo
    echo "Run './lab.sh up' to recreate the lab using the existing GitHub connection."
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
        echo "  ./lab.sh up       Bootstrap pipeline infrastructure"
        echo "  ./lab.sh plan     Preview pipeline and app changes"
        echo "  ./lab.sh down     Destroy app, then pipeline"
        echo
        exit 1
        ;;

esac
