# ☢️ az-nuke

`azure-nuke` is a powerful and **irreversible** script that **completely wipes an Azure subscription** using the Azure CLI.

This tool is ideal for teardown scenarios, lab resets, CI cleanup tasks, or safely decommissioning test environments.

> ⚠️ Use with **extreme caution**. This script deletes everything.

---

## 📑 Table of Contents

- [⚠️ WARNING](#️-warning)
- [✅ What It Does](#-what-it-does)
- [🚀 Usage](#-usage)
- [🔧 Prerequisites](#-prerequisites)
- [🛑 Exclusions](#-exclusions)
- [🧪 Post-Execution](#-post-execution)
- [💡 Future Improvements](#-future-improvements)
- [👤 Author](#-author)

---

## ⚠️ WARNING

This script **irreversibly deletes** everything in the specified Azure subscription:

- All **resource groups** and all contained resources
- All **custom role definitions** and **role assignments**
- All **service principals** (excluding Microsoft internal SPs)
- All **user-assigned managed identities**
- All **policy assignments** and **custom policy definitions**
- All **soft-deleted Key Vaults** (purged permanently)
- *(Disabled for now)* All **Azure Blueprints** — block commented out due to current API issues

> Once run, there's no going back. Be absolutely sure you're targeting the right subscription.

---

## ✅ What It Does

The script performs the following steps in order:

1. Prompts for (or accepts) the **Azure Subscription ID or Name**
2. **Displays a warning** including the subscription name, unless run with `-q`
3. **Deletes all resource groups** (waits for confirmation they are fully removed)
4. **Deletes custom role definitions**
5. **Removes all role assignments**
6. **Deletes all non-Microsoft service principals**
7. **Deletes all user-assigned managed identities**
8. **Deletes all policy assignments**
9. **Deletes all custom policy definitions**
10. *(Commented out)* Blueprint deletion is skipped (known `az blueprint` bugs)
11. **Purges soft-deleted Key Vaults**
12. **Deletes any remaining standalone resources**
13. **Performs a full final status report**, listing any remaining resource types

---

## 🚀 Usage

### 🔹 Standard Mode (with confirmation)

```bash
./azure-nuke.sh
````

You will be prompted to:

* Enter the subscription ID (if not preset)
* Confirm before execution begins

### 🔹 Quiet Mode (skip prompts)

```bash
./azure-nuke.sh -q
```

Use this only in CI/CD or automated pipelines **when you're absolutely sure**.

---

## 🔧 Prerequisites

To run `azure-nuke`, you must have:

* [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
* Logged in with `az login`
* Sufficient permissions to delete:

  * Resource groups
  * Role assignments
  * Service principals
  * Policies and Blueprints
  * Key Vaults
* The subscription **must not be locked** or set to read-only

---

## 🛑 Exclusions

This script **skips deletion** of **well-known Microsoft internal service principals**, using a hardcoded list of `appId`s.

These are typically essential for Azure to function and should not be deleted.

You can customize the exclusions by modifying the array in the `az ad sp delete` section of the script.

---

## 🧪 Post-Execution

After everything runs, the script prints a **status report** showing which Azure objects remain, such as:

```text
[✓] Resource Groups: CLEAN
[✓] Resources: CLEAN
[✓] Role Assignments: CLEAN
[✗] Service Principals: 2 remaining
...
```

If all components are marked ✅ CLEAN, the subscription is safe to:

* Cancel (via Azure Portal > Cost Management + Billing)
* Delete the tenant (Azure Active Directory > Manage Tenants > Delete)

---

## 💡 Future Improvements

Planned features:

* Re-enable Azure Blueprint support when stable
* Add support for deleting Azure AD users and groups
* Accept `--subscription-id` as a CLI flag
* Generate audit logs of deleted entities

---

## 👤 Author

> `azure-nuke` was built by security automation pros tired of click-ops.
>
> Use responsibly. Destroy confidently. Rebuild intentionally.
