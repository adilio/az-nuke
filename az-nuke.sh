#!/bin/bash

#################################################################
#                         AZ-NUKE TOOL                          #
#               Destructive Azure Subscription Wiper            #
#################################################################

# Initialize quiet mode as off
QUIET_MODE=false

# Parse flags
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -q|--quiet) QUIET_MODE=true ;;
    *) echo "❌ Unknown option: $1"; exit 1 ;;
  esac
  shift
done

#################################################################
#                   AZURE SUBSCRIPTION CONFIG                   #
#################################################################

# Fetch the current subscription ID
default_sub=$(az account show --query id -o tsv 2>/dev/null)

# Prompt user to accept default or input another
read -p "📦 Enter Azure Subscription ID [Press Enter to use $default_sub]: " SUBSCRIPTION_ID

# Use default if input is empty
SUBSCRIPTION_ID=${SUBSCRIPTION_ID:-$default_sub}

# Try to set the subscription and validate it
if ! az account set --subscription "$SUBSCRIPTION_ID" 2>/dev/null; then
  echo "❌ ERROR: Unable to set Azure subscription. Please check the ID or Name and try again."
  exit 1
fi


# Get the subscription name for display
SUBSCRIPTION_NAME=$(az account show --query "name" -o tsv)

if [ "$QUIET_MODE" = false ]; then
  echo ""
  echo "☢️  WARNING: You are about to NUKE everything in the following Azure subscription:"
  echo "------------------------------------------------------------------------------------------"
  echo " Subscription Name : $SUBSCRIPTION_NAME"
  echo " Subscription ID   : $SUBSCRIPTION_ID"
  echo ""
  echo " This script will permanently delete:"
  echo "   - All Resource Groups and Resources"
  echo "   - All Role Assignments and Custom Roles"
  echo "   - All Service Principals (excluding Microsoft internal)"
  echo "   - All Managed Identities"
  echo "   - All Policy Assignments and Definitions"
  echo "   - All Blueprints"
  echo "   - All soft-deleted Key Vaults (purged)"
  echo ""
  echo "⚠️  THIS ACTION CANNOT BE UNDONE. PROCEED WITH EXTREME CAUTION."
  echo ""

  read -p "Type 'y' to confirm and begin the destruction of '$SUBSCRIPTION_NAME': " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Aborted. Nothing was deleted."
    exit 1
  fi
fi

echo "✅ Starting az-nuke process for subscription: $SUBSCRIPTION_NAME"


# CONFIGURATION
POLL_INTERVAL=10                # seconds
MAX_WAIT_MINUTES=20             # wait time for RG deletion
MAX_RETRIES=3                   # for each resource deletion
RETRY_DELAY=5                   # seconds between retries

# Utility: retry command with backoff
retry() {
  local n=1
  until [ $n -gt $MAX_RETRIES ]; do
    "$@" && break || {
      echo "Attempt $n failed. Retrying in $RETRY_DELAY seconds..."
      sleep $RETRY_DELAY
    }
    ((n++))
  done
  if [ $n -gt $MAX_RETRIES ]; then
    echo "Command failed after $MAX_RETRIES attempts: $*"
  fi
}

##############################################
# Step 1: Delete all resource groups
##############################################
echo "Deleting all resource groups..."
for rg in $(az group list --query "[].name" -o tsv); do
  echo "Initiating deletion of Resource Group: $rg"
  retry az group delete --name "$rg" --yes --no-wait
done

# Poll until all RGs are deleted
echo "Waiting for resource groups to finish deleting..."
elapsed=0
while true; do
  count=$(az group list --query "length(@)" -o tsv)
  if [[ "$count" -eq 0 ]]; then
    echo "All resource groups deleted."
    break
  fi
  if (( elapsed >= MAX_WAIT_MINUTES * 60 )); then
    echo "Timeout: Resource groups still exist after $MAX_WAIT_MINUTES minutes."
    break
  fi
  echo "Still waiting... $count resource group(s) remaining."
  sleep $POLL_INTERVAL
  ((elapsed+=POLL_INTERVAL))
done

##############################################
# Step 2: Delete custom role definitions
##############################################
echo "Deleting custom roles..."
for role in $(az role definition list --custom-role-only true --query "[].name" -o tsv); do
  echo "Deleting Custom Role: $role"
  retry az role definition delete --name "$role"
done

##############################################
# Step 3: Remove all role assignments
##############################################
echo "Deleting all role assignments..."
for assignment in $(az role assignment list --query "[].id" -o tsv); do
  echo "Removing Role Assignment: $assignment"
  retry az role assignment delete --ids "$assignment"
done


echo "Deleting all non-Microsoft service principals..."

# List of internal Microsoft SP appIds to exclude
EXCLUDED_SP_IDS=(
  "00000001-0000-0000-c000-000000000000"
  "d73f4b35-55c9-48c7-8b10-651f6f2acb2e"
  "5da7367f-09c8-493e-8fd4-638089cddec3"
  "8fca0a66-c008-4564-a876-ab3ae0fd5cff"
  "8e0e8db5-b713-4e91-98e6-470fed0aa4c2"
  "cb1bda4c-1213-4e8b-911a-0a8c83c5d3b7"
  "eb86249-8ea3-49e2-900b-54cc8e308f85"
  "37182072-3c9c-4f6a-a4b3-b3f91cacffce"
  "b5a60e17-278b-4c92-a4e2-b9262e66bb28"
  "a1bfe852-bf44-4da0-a9c1-37af2d5e6df9"
  "6872b314-67ab-4a16-98e7-a663b0f772c3"
  "a57aca87-cbc0-4f3c-8b9e-dc095fdc8978"
  "b4bddae8-ab25-483e-8670-df09b9f1d0ea"
  "00000002-0000-0000-c000-000000000000"
  "0000000c-0000-0000-c000-000000000000"
  "50d8616b-fd4f-4fac-a1c9-a6a9440d7fe0"
  "797f4846-ba00-4fd7-ba43-dac1f8f63013"
  "ea890292-c8c8-4433-b5ea-b09d0668e1a6"
  "0bf30f3b-4a52-48df-9a82-234910c4a086"
  "00000003-0000-0000-c000-000000000000"
  "1b912ec3-a9dd-4c4d-a53e-76aa7adb28d7"
  "5861f7fb-5582-4c1a-83c0-fc5ffdb531a6"
  "c728155f-7b2a-4502-a08b-b8af9b269319"
  "aa9ecb1e-fd53-4aaa-a8fe-7a54de2c1334"
  "aeb86249-8ea3-49e2-900b-54cc8e308f85"
  "a68e1e61-ad4f-45b6-897d-0a1ea8786345"
  "de247707-4e4a-47d6-89fd-3c632f870b34"
  "d8c767ef-3e9a-48c4-aef9-562696539b39"
  "b2cc270f-563e-4d8a-af47-f00963a71dcd"
  "51b5e278-ed7e-42c6-8787-7ff93e92f577"
  "fc03f97a-9db0-4627-a216-ec98ce54e018"

)

# Loop through all service principal appIds
for sp_id in $(az ad sp list --all --query "[].appId" -o tsv); do
  # Check if this SP is in the exclusion list
  if printf '%s\n' "${EXCLUDED_SP_IDS[@]}" | grep -qx "$sp_id"; then
    echo "Skipping Microsoft internal SP: $sp_id"
    continue
  fi

  echo "Deleting service principal: $sp_id"
  retry az ad sp delete --id "$sp_id"
done

##############################################
# Step 5: Delete managed identities
##############################################
echo "Deleting managed identities..."
for identity_id in $(az identity list --query "[].id" -o tsv); do
  echo "Deleting Identity: $identity_id"
  retry az resource delete --ids "$identity_id"
done

##############################################
# Step 6: Delete policy assignments and definitions
##############################################
echo "Deleting policy assignments..."
for policy in $(az policy assignment list --query "[].name" -o tsv); do
  echo "Deleting Policy Assignment: $policy"
  retry az policy assignment delete --name "$policy"
done

echo "Deleting custom policy definitions..."
for policyDef in $(az policy definition list --query "[?policyType=='Custom'].name" -o tsv); do
  echo "Deleting Policy Definition: $policyDef"
  retry az policy definition delete --name "$policyDef"
done

# ###############################################################
# # Step 7: Delete blueprints - ERRORS - commenting out for now
# ###############################################################
# echo "Deleting blueprints..."
# for bp in $(az blueprint list --query "[].name" -o tsv); do
#   echo "Deleting Blueprint: $bp"
#   retry az blueprint delete --name "$bp"
# done

##############################################
# Step 8: Purge soft-deleted Key Vaults
##############################################
echo "🔐 Checking and purging soft-deleted Key Vaults..."

deleted_kvs=$(az keyvault list-deleted --query "[].name" -o tsv)

for kv in $deleted_kvs; do
  # Fetch location required to purge
  location=$(az keyvault list-deleted --query "[?name=='$kv'].location" -o tsv)
  
  if [[ -z "$location" ]]; then
    echo "⚠️  Skipping $kv – unable to determine location."
    continue
  fi

  # Check if purge protection is enabled
  protection=$(az keyvault show --name "$kv" --location "$location" --query "properties.enablePurgeProtection" -o tsv 2>/dev/null || echo "unknown")

  if [[ "$protection" == "true" ]]; then
    echo "⛔ Skipping purge of '$kv' (purge protection is enabled)"
  else
    echo "🗑️  Purging Key Vault: $kv"
    retry az keyvault purge --name "$kv" --location "$location"
  fi
done

##############################################
# Step 9: Delete any remaining resources
##############################################
echo "Deleting any leftover resources..."
for res_id in $(az resource list --query "[].id" -o tsv); do
  echo "Deleting Resource: $res_id"
  retry az resource delete --ids "$res_id"
done

# Final poll to confirm everything is gone
echo "Verifying no remaining resources..."
final_res=$(az resource list --query "[].id" -o tsv)
if [[ -z "$final_res" ]]; then
  echo "All resources successfully deleted."
else
  echo "WARNING: Some resources remain:"
  echo "$final_res"
fi

##############################################
# Final Status Report
##############################################

echo ""
echo "========================================"
echo " FINAL CLEANUP STATUS REPORT"
echo "========================================"

# Function to count remaining items and print summary
check_remaining() {
  local description="$1"
  local command="$2"
  local count=$(eval "$command")
  if [[ "$count" -eq 0 ]]; then
    echo "[✓] $description: CLEAN"
  else
    echo "[✗] $description: $count remaining"
  fi
}

check_remaining "Resource Groups"        "az group list --query 'length(@)' -o tsv"
check_remaining "Resources"              "az resource list --query 'length(@)' -o tsv"
check_remaining "Custom Roles"           "az role definition list --custom-role-only true --query 'length(@)' -o tsv"
check_remaining "Role Assignments"       "az role assignment list --query 'length(@)' -o tsv"
check_remaining "Service Principals (Remaining are likely MSFT Internal)"     "az ad sp list --all --query 'length(@)' -o tsv"
check_remaining "Managed Identities"     "az identity list --query 'length(@)' -o tsv"
check_remaining "Policy Assignments"     "az policy assignment list --query 'length(@)' -o tsv"
check_remaining "Custom Policy Definitions" "az policy definition list --query '[?policyType==\`Custom\`]' -o tsv | wc -l"
check_remaining "Deleted Key Vaults"     "az keyvault list-deleted --query 'length(@)' -o tsv"

echo ""
echo "========================================"
echo " ✅ SCRIPT COMPLETE"
echo "If everything above shows as CLEAN, you're ready to delete the tenant via the Azure Portal."
echo "Portal: Azure Active Directory > Manage Tenants > Delete"
echo "========================================"